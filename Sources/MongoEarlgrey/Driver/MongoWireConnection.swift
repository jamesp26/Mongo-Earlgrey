import Foundation
import Network
import Security

public enum MongoDriverError: LocalizedError {
    case connectionFailed(String)
    case connectionTimedOut
    case protocolError(String)
    case commandFailed(code: Int?, message: String)
    case notConnected

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg):
            return "Connection failed: \(msg)"
        case .connectionTimedOut:
            return "Operation timed out. Check host, port, firewall, and network access."
        case .protocolError(let msg):
            return "Wire protocol error: \(msg)"
        case .commandFailed(let code, let message):
            if let code = code {
                return "MongoError [\(code)]: \(message)"
            }
            return "MongoError: \(message)"
        case .notConnected:
            return "Not connected to a MongoDB server."
        }
    }
}

private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func tryResume(_ block: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !resumed else { return }
        resumed = true
        block()
    }
}

public actor MongoWireConnection {
    public let host: String
    public let port: UInt16
    public let useTLS: Bool
    public let tlsAllowInvalidCertificates: Bool

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.earlgrey.mongo.wire", qos: .userInitiated)
    private var nextRequestId: Int32 = 1
    private(set) public var isConnected: Bool = false
    private(set) public var serverHello: BSONDocument?

    public init(host: String, port: UInt16, useTLS: Bool, tlsAllowInvalidCertificates: Bool = false) {
        self.host = host
        self.port = port
        self.useTLS = useTLS
        self.tlsAllowInvalidCertificates = tlsAllowInvalidCertificates
    }

    public func connect(timeout: TimeInterval = 7.0) async throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw MongoDriverError.connectionFailed("Invalid port \(port)")
        }

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        tcpOptions.connectionTimeout = Int(timeout)
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 60
        tcpOptions.keepaliveInterval = 15

        let parameters: NWParameters
        if useTLS {
            let tlsOptions = NWProtocolTLS.Options()
            sec_protocol_options_set_tls_server_name(tlsOptions.securityProtocolOptions, host)
            if tlsAllowInvalidCertificates {
                sec_protocol_options_set_verify_block(
                    tlsOptions.securityProtocolOptions,
                    { _, _, completionHandler in
                        completionHandler(true)
                    },
                    queue
                )
            }
            parameters = NWParameters(tls: tlsOptions, tcp: tcpOptions)
        } else {
            parameters = NWParameters(tls: nil, tcp: tcpOptions)
        }

        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
        self.connection = conn

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ResumeGate()

            conn.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    gate.tryResume {
                        continuation.resume()
                    }
                case .failed(let err):
                    Task { await self?.markDisconnected() }
                    gate.tryResume {
                        continuation.resume(throwing: MongoDriverError.connectionFailed(err.localizedDescription))
                    }
                case .cancelled:
                    Task { await self?.markDisconnected() }
                    gate.tryResume {
                        continuation.resume(throwing: MongoDriverError.connectionFailed("Connection cancelled."))
                    }
                default:
                    break
                }
            }

            conn.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeout) {
                gate.tryResume {
                    conn.cancel()
                    continuation.resume(throwing: MongoDriverError.connectionTimedOut)
                }
            }
        }

        self.isConnected = true
    }

    private func markDisconnected() {
        isConnected = false
    }

    public func close() {
        isConnected = false
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
    }

    /// Perform initial `hello` handshake and optional SCRAM authentication
    public func handshakeAndAuthenticate(
        username: String?,
        password: String?,
        authDatabase: String
    ) async throws -> BSONDocument {
        var helloCmd: BSONDocument = [
            "hello": .int32(1),
            "client": .document([
                "application": .document(["name": .string("Mongo Earlgrey")]),
                "driver": .document([
                    "name": .string("MongoEarlgreySwift"),
                    "version": .string("1.0.0")
                ]),
                "os": .document([
                    "type": .string("Darwin"),
                    "name": .string("macOS")
                ])
            ]),
            "$db": .string("admin")
        ]

        if let user = username, !user.isEmpty {
            helloCmd["saslSupportedMechs"] = .string("\(authDatabase).\(user)")
        }

        let helloReply = try await sendCommand(helloCmd)
        self.serverHello = helloReply

        if let user = username, !user.isEmpty, let pass = password {
            // Check supported mechanisms from server hello
            var preferredMechanism: SCRAMMechanism = .scramSHA256
            if case .array(let mechs) = helloReply["saslSupportedMechs"] {
                let mechStrings = mechs.compactMap(\.stringValue)
                if mechStrings.contains("SCRAM-SHA-256") {
                    preferredMechanism = .scramSHA256
                } else if mechStrings.contains("SCRAM-SHA-1") {
                    preferredMechanism = .scramSHA1
                }
            }

            try await authenticateSCRAM(
                username: user,
                password: pass,
                authDatabase: authDatabase,
                mechanism: preferredMechanism
            )
        }

        return helloReply
    }

    private func authenticateSCRAM(
        username: String,
        password: String,
        authDatabase: String,
        mechanism: SCRAMMechanism
    ) async throws {
        let step1 = SCRAMAuthenticator.createStep1(
            username: username,
            authDatabase: authDatabase,
            mechanism: mechanism
        )
        let serverFirst = try await sendCommand(step1.saslStartCommand)
        let step2 = try SCRAMAuthenticator.createStep2(
            username: username,
            password: password,
            authDatabase: authDatabase,
            mechanism: mechanism,
            step1: step1,
            serverFirstResponse: serverFirst
        )
        var serverFinal = try await sendCommand(step2.saslContinueCommand)
        try SCRAMAuthenticator.verifyServerFinal(
            serverFinalResponse: serverFinal,
            expectedServerSignature: step2.expectedServerSignature
        )

        // Some servers require an empty final saslContinue step if done == false
        var safetyCounter = 0
        while serverFinal["done"]?.boolValue == false && safetyCounter < 3 {
            safetyCounter += 1
            let emptyContinue: BSONDocument = [
                "saslContinue": .int32(1),
                "conversationId": step2.conversationId,
                "payload": .binary(subtype: 0, data: Data()),
                "$db": .string(authDatabase)
            ]
            serverFinal = try await sendCommand(emptyContinue)
            if let ok = serverFinal["ok"]?.doubleValue, ok == 0 {
                let msg = serverFinal["errmsg"]?.stringValue ?? "Authentication failed."
                throw SCRAMError.authenticationFailed(msg)
            }
        }
    }

    /// Send an OP_MSG (opcode 2013) command and await the decoded BSONDocument response
    public func sendCommand(_ command: BSONDocument, timeout: TimeInterval = 30.0) async throws -> BSONDocument {
        guard let conn = connection, isConnected else {
            throw MongoDriverError.notConnected
        }

        let requestId = nextRequestId
        nextRequestId &+= 1
        if nextRequestId <= 0 { nextRequestId = 1 }

        let bsonPayload = BSONCoder.encode(command)
        // OP_MSG header (16 bytes) + flagBits (4 bytes) + sectionKind 0 (1 byte) + bsonPayload
        let totalLength = Int32(16 + 4 + 1 + bsonPayload.count)

        var frame = Data(capacity: Int(totalLength))
        appendInt32LE(totalLength, into: &frame)
        appendInt32LE(requestId, into: &frame)
        appendInt32LE(0, into: &frame)          // responseTo
        appendInt32LE(2013, into: &frame)       // opCode = 2013 (OP_MSG)
        appendInt32LE(0, into: &frame)          // flagBits = 0
        frame.append(0x00)                      // section kind 0 (body document)
        frame.append(bsonPayload)

        do {
            try await sendData(conn: conn, data: frame, timeout: timeout)

            // Read 16-byte response MsgHeader
            let headerData = try await receiveExact(conn: conn, length: 16, timeout: timeout)
            let headerBytes = [UInt8](headerData)
            var offset = 0
            let messageLength = Int(readInt32LE(headerBytes, offset: &offset))
            let _ = readInt32LE(headerBytes, offset: &offset) // responseRequestId
            let responseTo = readInt32LE(headerBytes, offset: &offset)
            let opCode = readInt32LE(headerBytes, offset: &offset)

            guard responseTo == requestId else {
                throw MongoDriverError.protocolError("Mismatched responseTo (\(responseTo)) for request \(requestId)")
            }

            guard messageLength >= 21, messageLength <= 64 * 1024 * 1024 else {
                throw MongoDriverError.protocolError("Invalid message length: \(messageLength)")
            }

            let bodyLength = messageLength - 16
            let bodyData = try await receiveExact(conn: conn, length: bodyLength, timeout: timeout)
            let bodyBytes = [UInt8](bodyData)

            if opCode == 2013 {
                var bodyOffset = 0
                guard bodyBytes.count >= 5 else {
                    throw MongoDriverError.protocolError("Truncated OP_MSG body")
                }
                let flagBits = readInt32LE(bodyBytes, offset: &bodyOffset)
                let checksumPresent = (flagBits & 0x0001) != 0
                let payloadEnd = checksumPresent ? bodyBytes.count - 4 : bodyBytes.count
                guard bodyOffset < payloadEnd else {
                    throw MongoDriverError.protocolError("Truncated OP_MSG sections")
                }

                let sectionKind = bodyBytes[bodyOffset]
                bodyOffset += 1
                if sectionKind == 0 {
                    return try BSONCoder.decodeDocument(from: bodyBytes, offset: &bodyOffset, limit: payloadEnd)
                } else {
                    throw MongoDriverError.protocolError("Unsupported OP_MSG section kind \(sectionKind)")
                }
            } else if opCode == 1 {
                // Legacy OP_REPLY fallback
                var bodyOffset = 20
                guard bodyOffset < bodyBytes.count else {
                    throw MongoDriverError.protocolError("Truncated OP_REPLY body")
                }
                return try BSONCoder.decodeDocument(from: bodyBytes, offset: &bodyOffset, limit: bodyBytes.count)
            } else {
                throw MongoDriverError.protocolError("Unexpected wire opcode \(opCode)")
            }
        } catch {
            // Never reuse a stream that experienced partial read/write or protocol desync
            close()
            throw error
        }
    }

    private func sendData(conn: NWConnection, data: Data, timeout: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ResumeGate()
            conn.send(content: data, completion: .contentProcessed { error in
                gate.tryResume {
                    if let error = error {
                        continuation.resume(throwing: MongoDriverError.connectionFailed(error.localizedDescription))
                    } else {
                        continuation.resume()
                    }
                }
            })
            queue.asyncAfter(deadline: .now() + timeout) {
                gate.tryResume {
                    continuation.resume(throwing: MongoDriverError.connectionTimedOut)
                }
            }
        }
    }

    private func receiveExact(conn: NWConnection, length: Int, timeout: TimeInterval) async throws -> Data {
        var accumulated = Data(capacity: length)
        while accumulated.count < length {
            let remaining = length - accumulated.count
            let chunk = try await receiveChunk(conn: conn, minLength: 1, maxLength: remaining, timeout: timeout)
            if chunk.isEmpty {
                isConnected = false
                throw MongoDriverError.connectionFailed("Server closed the connection.")
            }
            accumulated.append(chunk)
        }
        return accumulated
    }

    private func receiveChunk(conn: NWConnection, minLength: Int, maxLength: Int, timeout: TimeInterval) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            let gate = ResumeGate()
            conn.receive(minimumIncompleteLength: minLength, maximumLength: maxLength) { data, _, _, error in
                gate.tryResume {
                    if let error = error {
                        continuation.resume(throwing: MongoDriverError.connectionFailed(error.localizedDescription))
                    } else if let data = data, !data.isEmpty {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(returning: Data())
                    }
                }
            }
            queue.asyncAfter(deadline: .now() + timeout) {
                gate.tryResume {
                    continuation.resume(throwing: MongoDriverError.connectionTimedOut)
                }
            }
        }
    }

    private func appendInt32LE(_ value: Int32, into data: inout Data) {
        let le = value.littleEndian
        withUnsafeBytes(of: le) { data.append(contentsOf: $0) }
    }

    private func readInt32LE(_ bytes: [UInt8], offset: inout Int) -> Int32 {
        let b0 = Int32(bytes[offset])
        let b1 = Int32(bytes[offset + 1]) << 8
        let b2 = Int32(bytes[offset + 2]) << 16
        let b3 = Int32(bytes[offset + 3]) << 24
        offset += 4
        return b0 | b1 | b2 | b3
    }
}

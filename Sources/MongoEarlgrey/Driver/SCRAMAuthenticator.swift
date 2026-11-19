import Foundation
import CryptoKit
import CommonCrypto

public enum SCRAMMechanism: String, Sendable {
    case scramSHA256 = "SCRAM-SHA-256"
    case scramSHA1 = "SCRAM-SHA-1"
}

public enum SCRAMError: LocalizedError {
    case invalidServerResponse(String)
    case authenticationFailed(String)
    case serverSignatureMismatch

    public var errorDescription: String? {
        switch self {
        case .invalidServerResponse(let msg):
            return "Invalid SCRAM server response: \(msg)"
        case .authenticationFailed(let msg):
            return "Authentication failed: \(msg)"
        case .serverSignatureMismatch:
            return "Server signature verification failed during SCRAM authentication."
        }
    }
}

public struct SCRAMAuthenticator {
    public struct Step1Result {
        public let clientFirstMessageBare: String
        public let clientNonce: String
        public let saslStartCommand: BSONDocument
    }

    public static func createStep1(
        username: String,
        authDatabase: String,
        mechanism: SCRAMMechanism
    ) -> Step1Result {
        var nonceBytes = [UInt8](repeating: 0, count: 24)
        for i in 0..<24 {
            nonceBytes[i] = UInt8.random(in: 0...255)
        }
        let clientNonce = Data(nonceBytes).base64EncodedString()
        let sanitizedUser = username
            .replacingOccurrences(of: "=", with: "=3D")
            .replacingOccurrences(of: ",", with: "=2C")
        let clientFirstBare = "n=\(sanitizedUser),r=\(clientNonce)"
        let fullPayload = "n,,\(clientFirstBare)"
        let payloadData = Data(fullPayload.utf8)

        let cmd: BSONDocument = [
            "saslStart": .int32(1),
            "mechanism": .string(mechanism.rawValue),
            "payload": .binary(subtype: 0, data: payloadData),
            "autoAuthorize": .int32(1),
            "options": .document(["skipEmptyExchange": .bool(true)]),
            "$db": .string(authDatabase)
        ]

        return Step1Result(
            clientFirstMessageBare: clientFirstBare,
            clientNonce: clientNonce,
            saslStartCommand: cmd
        )
    }

    public struct Step2Result {
        public let saslContinueCommand: BSONDocument
        public let expectedServerSignature: Data
        public let conversationId: BSONValue
    }

    public static func createStep2(
        username: String,
        password: String,
        authDatabase: String,
        mechanism: SCRAMMechanism,
        step1: Step1Result,
        serverFirstResponse: BSONDocument
    ) throws -> Step2Result {
        if let ok = serverFirstResponse["ok"]?.doubleValue, ok == 0 {
            let errmsg = serverFirstResponse["errmsg"]?.stringValue ?? "Unknown auth error"
            throw SCRAMError.authenticationFailed(errmsg)
        }

        guard let conversationId = serverFirstResponse["conversationId"],
              case .binary(_, let payloadData) = serverFirstResponse["payload"],
              let serverFirstMessage = String(data: payloadData, encoding: .utf8) else {
            throw SCRAMError.invalidServerResponse("Missing payload or conversationId in saslStart reply.")
        }

        let attributes = parseAttributes(serverFirstMessage)
        guard let combinedNonce = attributes["r"],
              let saltBase64 = attributes["s"],
              let saltData = Data(base64Encoded: saltBase64),
              let iterStr = attributes["i"],
              let iterations = Int(iterStr),
              iterations >= 1 && iterations <= 1_000_000 else {
            throw SCRAMError.invalidServerResponse(serverFirstMessage)
        }

        guard combinedNonce.hasPrefix(step1.clientNonce) else {
            throw SCRAMError.invalidServerResponse("Server nonce does not start with client nonce.")
        }

        let clientFinalWithoutProof = "c=biws,r=\(combinedNonce)"
        let authMessage = "\(step1.clientFirstMessageBare),\(serverFirstMessage),\(clientFinalWithoutProof)"
        let authMessageData = Data(authMessage.utf8)

        // Compute digested password according to mechanism
        let passwordKeyData: Data
        switch mechanism {
        case .scramSHA256:
            // RFC 7677 / MongoDB spec: normalize password via Unicode NFKC for SCRAM-SHA-256
            let normalized = password.precomposedStringWithCompatibilityMapping
            passwordKeyData = Data(normalized.utf8)
        case .scramSHA1:
            // MongoDB SCRAM-SHA-1 uses hex MD5 of "<username>:mongo:<password>"
            let raw = "\(username):mongo:\(password)"
            let digest = Insecure.MD5.hash(data: Data(raw.utf8))
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            passwordKeyData = Data(hex.utf8)
        }

        let saltedPassword = pbkdf2(
            password: passwordKeyData,
            salt: saltData,
            iterations: iterations,
            mechanism: mechanism
        )

        let clientKey = hmac(key: saltedPassword, data: Data("Client Key".utf8), mechanism: mechanism)
        let storedKey = hash(data: clientKey, mechanism: mechanism)
        let clientSignature = hmac(key: storedKey, data: authMessageData, mechanism: mechanism)
        let clientProof = xor(clientKey, clientSignature)

        let serverKey = hmac(key: saltedPassword, data: Data("Server Key".utf8), mechanism: mechanism)
        let expectedServerSignature = hmac(key: serverKey, data: authMessageData, mechanism: mechanism)

        let clientFinalMessage = "\(clientFinalWithoutProof),p=\(clientProof.base64EncodedString())"
        let continueCmd: BSONDocument = [
            "saslContinue": .int32(1),
            "conversationId": conversationId,
            "payload": .binary(subtype: 0, data: Data(clientFinalMessage.utf8)),
            "$db": .string(authDatabase)
        ]

        return Step2Result(
            saslContinueCommand: continueCmd,
            expectedServerSignature: expectedServerSignature,
            conversationId: conversationId
        )
    }

    /// Verify the server's final SCRAM signature (`v=<base64>`) against the expected ServerSignature
    /// in constant time to guarantee mutual authentication.
    public static func verifyServerFinal(
        serverFinalResponse: BSONDocument,
        expectedServerSignature: Data
    ) throws {
        if let ok = serverFinalResponse["ok"]?.doubleValue, ok == 0 {
            let errmsg = serverFinalResponse["errmsg"]?.stringValue ?? "Authentication failed."
            throw SCRAMError.authenticationFailed(errmsg)
        }

        guard case .binary(_, let payloadData) = serverFinalResponse["payload"],
              let serverFinalMessage = String(data: payloadData, encoding: .utf8) else {
            throw SCRAMError.serverSignatureMismatch
        }

        let attributes = parseAttributes(serverFinalMessage)
        if let serverError = attributes["e"] {
            throw SCRAMError.authenticationFailed(serverError)
        }

        guard let vBase64 = attributes["v"],
              let serverSig = Data(base64Encoded: vBase64),
              serverSig.count == expectedServerSignature.count else {
            throw SCRAMError.serverSignatureMismatch
        }

        // Constant-time comparison to prevent timing side-channels
        var diff: UInt8 = 0
        for i in 0..<expectedServerSignature.count {
            diff |= serverSig[i] ^ expectedServerSignature[i]
        }
        guard diff == 0 else {
            throw SCRAMError.serverSignatureMismatch
        }
    }

    private static func parseAttributes(_ message: String) -> [String: String] {
        var dict: [String: String] = [:]
        for part in message.split(separator: ",") {
            guard part.count >= 2 else { continue }
            let idx = part.index(part.startIndex, offsetBy: 1)
            if part[idx] == "=" {
                let key = String(part[..<idx])
                let valStart = part.index(after: idx)
                let val = String(part[valStart...])
                dict[key] = val
            }
        }
        return dict
    }

    private static func hmac(key: Data, data: Data, mechanism: SCRAMMechanism) -> Data {
        let symKey = SymmetricKey(data: key)
        switch mechanism {
        case .scramSHA256:
            let mac = HMAC<SHA256>.authenticationCode(for: data, using: symKey)
            return Data(mac)
        case .scramSHA1:
            let mac = HMAC<Insecure.SHA1>.authenticationCode(for: data, using: symKey)
            return Data(mac)
        }
    }

    private static func hash(data: Data, mechanism: SCRAMMechanism) -> Data {
        switch mechanism {
        case .scramSHA256:
            return Data(SHA256.hash(data: data))
        case .scramSHA1:
            return Data(Insecure.SHA1.hash(data: data))
        }
    }

    private static func xor(_ a: Data, _ b: Data) -> Data {
        var result = Data(count: min(a.count, b.count))
        for i in 0..<result.count {
            result[i] = a[i] ^ b[i]
        }
        return result
    }

    private static func pbkdf2(password: Data, salt: Data, iterations: Int, mechanism: SCRAMMechanism) -> Data {
        let keyLength = (mechanism == .scramSHA256) ? Int(CC_SHA256_DIGEST_LENGTH) : Int(CC_SHA1_DIGEST_LENGTH)
        let prf = (mechanism == .scramSHA256)
            ? CCPBKDFAlgorithm(kCCPRFHmacAlgSHA256)
            : CCPBKDFAlgorithm(kCCPRFHmacAlgSHA1)

        let safePass = password.isEmpty ? Data([0]) : password
        let safeSalt = salt.isEmpty ? Data([0]) : salt
        var derivedKey = Data(repeating: 0, count: keyLength)
        let status: Int32 = derivedKey.withUnsafeMutableBytes { derivedPtr in
            safeSalt.withUnsafeBytes { saltPtr in
                safePass.withUnsafeBytes { passPtr in
                    let passBase = passPtr.bindMemory(to: Int8.self).baseAddress
                    let saltBase = saltPtr.bindMemory(to: UInt8.self).baseAddress
                    let derivedBase = derivedPtr.bindMemory(to: UInt8.self).baseAddress
                    return CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passBase,
                        password.count,
                        saltBase,
                        salt.count,
                        prf,
                        UInt32(iterations),
                        derivedBase,
                        keyLength
                    )
                }
            }
        }

        if status == kCCSuccess {
            return derivedKey
        }

        // Safe fallback if CommonCrypto unavailable
        var saltAndBlock = salt
        saltAndBlock.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
        var u = hmac(key: password, data: saltAndBlock, mechanism: mechanism)
        var output = u
        if iterations > 1 {
            for _ in 2...iterations {
                u = hmac(key: password, data: u, mechanism: mechanism)
                for i in 0..<output.count {
                    output[i] ^= u[i]
                }
            }
        }
        return output
    }
}

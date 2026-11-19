import Foundation

public struct DatabaseSummary: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public let name: String
    public let sizeOnDisk: Int64
    public let empty: Bool
    public var collections: [CollectionSummary]
}

public struct CollectionSummary: Identifiable, Hashable, Sendable {
    public var id: String { "\(database).\(name)" }
    public let database: String
    public let name: String
    public let type: String
}

public struct QueryExecutionResult: Sendable {
    public let documents: [BSONDocument]
    public let totalCount: Int?
    public let executionTimeMs: Double
    public let statusText: String
}

public actor MongoClient {
    public let config: ConnectionConfig
    private var wire: MongoWireConnection?
    private var resolvedEndpoint: ConnectionConfig.ResolvedEndpoint?
    private var demoStore: DemoMongoStore?

    public init(config: ConnectionConfig) {
        self.config = config
        if config.isDemoMode {
            self.demoStore = DemoMongoStore()
        }
    }

    public func connect() async throws -> String {
        if config.isDemoMode {
            try await Task.sleep(nanoseconds: 40_000_000) // 40ms realistic feel
            return "MongoDB 7.0.12 (Earlgrey In-Memory Engine)"
        }

        var endpoint = try config.resolveEndpoint()
        var hosts = endpoint.seedHosts
        var authDB = endpoint.authDatabase

        if endpoint.isSRV, let firstSeed = hosts.first {
            let srvResult = await SRVResolver.resolveMongoSRVAsync(domain: firstSeed.host)
            guard !srvResult.hosts.isEmpty else {
                throw MongoDriverError.connectionFailed("DNS SRV lookup failed for _mongodb._tcp.\(firstSeed.host). Check hostname, VPN, or DNS settings.")
            }
            hosts = srvResult.hosts
            if !endpoint.authSourceExplicit,
               let txtAuthSource = srvResult.txtOptions["authSource"] ?? srvResult.txtOptions["authsource"],
               !txtAuthSource.isEmpty {
                authDB = txtAuthSource
                endpoint.authDatabase = txtAuthSource
            }
        }

        self.resolvedEndpoint = endpoint

        var lastError: Error?
        for candidate in hosts {
            let conn = MongoWireConnection(
                host: candidate.host,
                port: candidate.port,
                useTLS: endpoint.useTLS,
                tlsAllowInvalidCertificates: endpoint.tlsAllowInvalidCertificates
            )
            do {
                try await conn.connect(timeout: 7.0)
                let hello = try await conn.handshakeAndAuthenticate(
                    username: endpoint.username,
                    password: endpoint.password,
                    authDatabase: authDB
                )

                // Check if this is a secondary in a replica set and a primary host is advertised
                // (Skip primary redirection if directConnection is explicitly enabled, e.g., SSH tunnel)
                let isWritablePrimary = hello["isWritablePrimary"]?.boolValue ?? hello["ismaster"]?.boolValue ?? true
                if !endpoint.directConnection, !isWritablePrimary, let primaryStr = hello["primary"]?.stringValue {
                    let parts = primaryStr.split(separator: ":")
                    if let primaryHost = parts.first.map(String.init) {
                        let primaryPort = parts.count > 1 ? (UInt16(parts[1]) ?? candidate.port) : candidate.port
                        if primaryHost != candidate.host || primaryPort != candidate.port {
                            let primaryConn = MongoWireConnection(
                                host: primaryHost,
                                port: primaryPort,
                                useTLS: endpoint.useTLS,
                                tlsAllowInvalidCertificates: endpoint.tlsAllowInvalidCertificates
                            )
                            if let _ = try? await primaryConn.connect(timeout: 5.0),
                               let primaryHello = try? await primaryConn.handshakeAndAuthenticate(
                                   username: endpoint.username,
                                   password: endpoint.password,
                                   authDatabase: authDB
                               ) {
                                await conn.close()
                                self.wire = primaryConn
                                return await formatConnectedBanner(host: primaryHost, port: primaryPort, tls: endpoint.useTLS, hello: primaryHello, conn: primaryConn)
                            } else {
                                await primaryConn.close()
                            }
                        }
                    }
                }

                self.wire = conn
                return await formatConnectedBanner(host: candidate.host, port: candidate.port, tls: endpoint.useTLS, hello: hello, conn: conn)
            } catch {
                await conn.close()
                lastError = error
            }
        }

        throw lastError ?? MongoDriverError.connectionFailed("Unable to connect to any MongoDB host.")
    }

    private func formatConnectedBanner(
        host: String,
        port: UInt16,
        tls: Bool,
        hello: BSONDocument,
        conn: MongoWireConnection
    ) async -> String {
        var parts = ["\(host):\(port)"]
        if let buildReply = try? await conn.sendCommand(["buildInfo": .int32(1), "$db": .string("admin")], timeout: 3.0),
           let version = buildReply["version"]?.stringValue {
            parts.append("MongoDB \(version)")
        } else if let setName = hello["setName"]?.stringValue, !setName.isEmpty {
            parts.append("RS: \(setName)")
        }
        if tls {
            parts.append("TLS")
        }
        return parts.joined(separator: " • ")
    }

    public func disconnect() async {
        if let wire = wire {
            await wire.close()
        }
        wire = nil
    }

    private func ensureWire() async throws -> MongoWireConnection {
        if let w = wire, await w.isConnected {
            return w
        }
        _ = try await connect()
        guard let w = wire else {
            throw MongoDriverError.notConnected
        }
        return w
    }

    public func listDatabasesWithCollections() async throws -> [DatabaseSummary] {
        if let demo = demoStore {
            return await demo.listDatabasesWithCollections()
        }

        let conn = try await ensureWire()
        let cmd: BSONDocument = [
            "listDatabases": .int32(1),
            "nameOnly": .bool(false),
            "$db": .string("admin")
        ]

        var dbSummaries: [DatabaseSummary] = []

        do {
            let reply = try await conn.sendCommand(cmd)
            try checkCommandReply(reply)
            if case .array(let dbArray) = reply["databases"] {
                for item in dbArray {
                    guard case .document(let doc) = item,
                          let name = doc["name"]?.stringValue else { continue }
                    let size = Int64(doc["sizeOnDisk"]?.intValue ?? 0)
                    let empty = doc["empty"]?.boolValue ?? false
                    let collections = (try? await listCollections(inDatabase: name, using: conn)) ?? []
                    dbSummaries.append(DatabaseSummary(
                        name: name,
                        sizeOnDisk: size,
                        empty: empty,
                        collections: collections
                    ))
                }
            }
        } catch {
            // Fallback for database-scoped users without cluster-wide listDatabases permission
            let fallbackDB = resolvedEndpoint?.defaultDatabase ?? resolvedEndpoint?.authDatabase ?? "test"
            let collections = try await listCollections(inDatabase: fallbackDB, using: conn)
            dbSummaries.append(DatabaseSummary(
                name: fallbackDB,
                sizeOnDisk: 0,
                empty: collections.isEmpty,
                collections: collections
            ))
        }

        // Also ensure defaultDatabase is listed if it wasn't returned
        if let defDB = resolvedEndpoint?.defaultDatabase,
           !defDB.isEmpty,
           !dbSummaries.contains(where: { $0.name == defDB }) {
            let cols = (try? await listCollections(inDatabase: defDB, using: conn)) ?? []
            dbSummaries.insert(DatabaseSummary(name: defDB, sizeOnDisk: 0, empty: cols.isEmpty, collections: cols), at: 0)
        }

        return dbSummaries.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func listCollections(inDatabase dbName: String) async throws -> [CollectionSummary] {
        if let demo = demoStore {
            return await demo.listCollections(inDatabase: dbName)
        }
        let conn = try await ensureWire()
        return try await listCollections(inDatabase: dbName, using: conn)
    }

    private func listCollections(inDatabase dbName: String, using conn: MongoWireConnection) async throws -> [CollectionSummary] {
        let cmd: BSONDocument = [
            "listCollections": .int32(1),
            "nameOnly": .bool(true),
            "$db": .string(dbName)
        ]
        let reply = try await conn.sendCommand(cmd)
        try checkCommandReply(reply)

        let rawDocs = try await drainCursor(
            initialReply: reply,
            database: dbName,
            collection: "$cmd.listCollections",
            maxDocs: 10_000,
            using: conn
        )

        var results: [CollectionSummary] = []
        results.reserveCapacity(rawDocs.count)
        for doc in rawDocs {
            guard let name = doc["name"]?.stringValue else { continue }
            let type = doc["type"]?.stringValue ?? "collection"
            results.append(CollectionSummary(database: dbName, name: name, type: type))
        }
        return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Execute Query
    public func executeQuery(
        database: String,
        defaultCollection: String,
        parsedQuery: ParsedMongoQuery,
        fallbackLimit: Int = 50,
        fallbackSkip: Int = 0
    ) async throws -> QueryExecutionResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        let targetCollection = parsedQuery.collection ?? defaultCollection

        if let demo = demoStore {
            let result = await demo.executeQuery(
                database: database,
                collection: targetCollection,
                parsedQuery: parsedQuery,
                fallbackLimit: fallbackLimit,
                fallbackSkip: fallbackSkip
            )
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            return QueryExecutionResult(
                documents: result.documents,
                totalCount: result.totalCount,
                executionTimeMs: max(0.4, elapsedMs),
                statusText: result.statusText
            )
        }

        let conn = try await ensureWire()

        switch parsedQuery.operation {
        case .count:
            let countCmd: BSONDocument = [
                "count": .string(targetCollection),
                "query": .document(parsedQuery.filter),
                "$db": .string(database)
            ]
            let n: Int
            do {
                let reply = try await conn.sendCommand(countCmd)
                try checkCommandReply(reply)
                n = reply["n"]?.intValue ?? 0
            } catch {
                // Fall back to $match + $count aggregation (for Atlas Serverless / Stable API)
                let pipeline: [BSONValue] = [
                    .document(["$match": .document(parsedQuery.filter)]),
                    .document(["$count": .string("n")])
                ]
                let aggCmd: BSONDocument = [
                    "aggregate": .string(targetCollection),
                    "pipeline": .array(pipeline),
                    "cursor": .document([:]),
                    "$db": .string(database)
                ]
                let aggReply = try await conn.sendCommand(aggCmd)
                try checkCommandReply(aggReply)
                let aggDocs = try await drainCursor(
                    initialReply: aggReply,
                    database: database,
                    collection: targetCollection,
                    maxDocs: 1,
                    using: conn
                )
                n = aggDocs.first?["n"]?.intValue ?? 0
            }
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            let countDoc: BSONDocument = ["count": .int64(Int64(n))]
            return QueryExecutionResult(
                documents: [countDoc],
                totalCount: n,
                executionTimeMs: elapsedMs,
                statusText: "Count: \(n)"
            )

        case .aggregate(let pipeline):
            let maxDocs = max(1, parsedQuery.limit ?? fallbackLimit)
            let aggCmd: BSONDocument = [
                "aggregate": .string(targetCollection),
                "pipeline": .array(pipeline),
                "cursor": .document(["batchSize": .int32(Int32(min(maxDocs, 250)))]),
                "$db": .string(database)
            ]
            let reply = try await conn.sendCommand(aggCmd)
            try checkCommandReply(reply)
            let docs = try await drainCursor(
                initialReply: reply,
                database: database,
                collection: targetCollection,
                maxDocs: maxDocs,
                using: conn
            )
            let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            return QueryExecutionResult(
                documents: docs,
                totalCount: docs.count,
                executionTimeMs: elapsedMs,
                statusText: "\(docs.count) \(docs.count == 1 ? "document" : "documents")"
            )

        case .find:
            let effectiveLimit = parsedQuery.limit ?? fallbackLimit
            let effectiveSkip = parsedQuery.skip ?? fallbackSkip

            var findElements: [BSONElement] = [
                BSONElement(key: "find", value: .string(targetCollection)),
                BSONElement(key: "filter", value: .document(parsedQuery.filter))
            ]
            if let proj = parsedQuery.projection, !proj.isEmpty {
                findElements.append(BSONElement(key: "projection", value: .document(proj)))
            }
            if let sort = parsedQuery.sort, !sort.isEmpty {
                findElements.append(BSONElement(key: "sort", value: .document(sort)))
            }
            if effectiveSkip > 0 {
                findElements.append(BSONElement(key: "skip", value: .int32(Int32(effectiveSkip))))
            }
            let drainCap: Int
            if effectiveLimit > 0 {
                findElements.append(BSONElement(key: "limit", value: .int32(Int32(effectiveLimit))))
                findElements.append(BSONElement(key: "batchSize", value: .int32(Int32(effectiveLimit))))
                drainCap = effectiveLimit
            } else {
                findElements.append(BSONElement(key: "batchSize", value: .int32(100)))
                drainCap = 5_000
            }
            findElements.append(BSONElement(key: "$db", value: .string(database)))

            let findCmd = BSONDocument(elements: findElements)
            let reply = try await conn.sendCommand(findCmd)
            try checkCommandReply(reply)
            let docs = try await drainCursor(
                initialReply: reply,
                database: database,
                collection: targetCollection,
                maxDocs: drainCap,
                using: conn
            )

            // Fetch total matching count with a 1500ms cap so massive collection scans never block UI
            let countCmd: BSONDocument = [
                "count": .string(targetCollection),
                "query": .document(parsedQuery.filter),
                "maxTimeMS": .int32(1500),
                "$db": .string(database)
            ]
            let countReply = try? await conn.sendCommand(countCmd, timeout: 2.5)
            let countReplyOk = (countReply?["ok"]?.doubleValue ?? 0) != 0
            let totalMatching = countReplyOk ? countReply?["n"]?.intValue : nil

            let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            let status: String
            if let total = totalMatching {
                let rangeStart = effectiveSkip + (docs.isEmpty ? 0 : 1)
                let rangeEnd = effectiveSkip + docs.count
                if docs.isEmpty {
                    status = "0 of \(total) \(total == 1 ? "doc" : "docs")"
                } else {
                    status = "Showing \(rangeStart)–\(rangeEnd) of \(total) \(total == 1 ? "doc" : "docs")"
                }
            } else {
                status = "\(docs.count) \(docs.count == 1 ? "doc" : "docs")"
            }

            return QueryExecutionResult(
                documents: docs,
                totalCount: totalMatching,
                executionTimeMs: elapsedMs,
                statusText: status
            )
        }
    }

    // MARK: - Replace / Update Document
    public func replaceDocument(
        database: String,
        collection: String,
        originalId: BSONValue,
        replacement: BSONDocument
    ) async throws {
        if let demo = demoStore {
            try await demo.replaceDocument(
                database: database,
                collection: collection,
                originalId: originalId,
                replacement: replacement
            )
            return
        }

        let conn = try await ensureWire()
        var docToSave = replacement
        if docToSave["_id"] == nil {
            var elems = [BSONElement(key: "_id", value: originalId)]
            elems.append(contentsOf: docToSave.elements)
            docToSave = BSONDocument(elements: elems)
        }

        let updateSpec: BSONDocument = [
            "q": .document(["_id": originalId]),
            "u": .document(docToSave),
            "upsert": .bool(false)
        ]
        let cmd: BSONDocument = [
            "update": .string(collection),
            "updates": .array([.document(updateSpec)]),
            "$db": .string(database)
        ]

        let reply = try await conn.sendCommand(cmd)
        try checkCommandReply(reply)
        if case .array(let writeErrors) = reply["writeErrors"],
           let firstErr = writeErrors.first?.documentValue {
            let msg = firstErr["errmsg"]?.stringValue ?? "Failed to update document."
            let code = firstErr["code"]?.intValue
            throw MongoDriverError.commandFailed(code: code, message: msg)
        }
    }

    // MARK: - Insert Document
    public func insertDocument(
        database: String,
        collection: String,
        document: BSONDocument
    ) async throws {
        if let demo = demoStore {
            try await demo.insertDocument(database: database, collection: collection, document: document)
            return
        }

        let conn = try await ensureWire()
        var docToInsert = document
        if docToInsert["_id"] == nil {
            var elems = [BSONElement(key: "_id", value: .objectId(BSONObjectId.generate()))]
            elems.append(contentsOf: docToInsert.elements)
            docToInsert = BSONDocument(elements: elems)
        }

        let cmd: BSONDocument = [
            "insert": .string(collection),
            "documents": .array([.document(docToInsert)]),
            "$db": .string(database)
        ]

        let reply = try await conn.sendCommand(cmd)
        try checkCommandReply(reply)
        if case .array(let writeErrors) = reply["writeErrors"],
           let firstErr = writeErrors.first?.documentValue {
            let msg = firstErr["errmsg"]?.stringValue ?? "Failed to insert document."
            let code = firstErr["code"]?.intValue
            throw MongoDriverError.commandFailed(code: code, message: msg)
        }
    }

    private func drainCursor(
        initialReply: BSONDocument,
        database: String,
        collection: String,
        maxDocs: Int,
        using conn: MongoWireConnection
    ) async throws -> [BSONDocument] {
        guard case .document(let cursor) = initialReply["cursor"],
              case .array(let firstBatch) = cursor["firstBatch"] else {
            return []
        }

        var collected = firstBatch.compactMap(\.documentValue)
        var cursorId = cursor["id"]?.intValue.map(Int64.init) ?? 0
        if case .int64(let id64) = cursor["id"] {
            cursorId = id64
        }

        // Extract collection name from cursor namespace "db.collection" if available
        let nsCollection: String
        if let ns = cursor["ns"]?.stringValue, let dotIdx = ns.firstIndex(of: ".") {
            nsCollection = String(ns[ns.index(after: dotIdx)...])
        } else {
            nsCollection = collection
        }

        while cursorId != 0 && collected.count < maxDocs {
            let remaining = max(1, maxDocs - collected.count)
            let getMoreCmd: BSONDocument = [
                "getMore": .int64(cursorId),
                "collection": .string(nsCollection),
                "batchSize": .int32(Int32(min(remaining, 250))),
                "$db": .string(database)
            ]
            let moreReply = try await conn.sendCommand(getMoreCmd)
            try checkCommandReply(moreReply)
            guard case .document(let nextCursor) = moreReply["cursor"] else {
                break
            }
            if case .array(let nextBatch) = nextCursor["nextBatch"] {
                collected.append(contentsOf: nextBatch.compactMap(\.documentValue))
            }
            if case .int64(let nextId) = nextCursor["id"] {
                cursorId = nextId
            } else {
                cursorId = nextCursor["id"]?.intValue.map(Int64.init) ?? 0
            }
        }

        // Always close any remaining server-side cursor to prevent leaks
        if cursorId != 0 {
            let killCmd: BSONDocument = [
                "killCursors": .string(nsCollection),
                "cursors": .array([.int64(cursorId)]),
                "$db": .string(database)
            ]
            _ = try? await conn.sendCommand(killCmd, timeout: 3.0)
        }

        if collected.count > maxDocs {
            return Array(collected.prefix(maxDocs))
        }
        return collected
    }

    private func checkCommandReply(_ reply: BSONDocument) throws {
        if let ok = reply["ok"]?.doubleValue, ok == 0 {
            let msg = reply["errmsg"]?.stringValue ?? "MongoDB command failed"
            let code = reply["code"]?.intValue
            throw MongoDriverError.commandFailed(code: code, message: msg)
        }
    }
}

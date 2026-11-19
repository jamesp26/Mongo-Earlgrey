import Foundation

public struct ConnectionConfig: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var colorName: String // "amber", "emerald", "blue", "purple", "rose", "teal"
    public var useURI: Bool
    public var uriString: String
    public var host: String
    public var port: Int
    public var authEnabled: Bool
    public var username: String
    public var password: String
    public var authDatabase: String
    public var defaultDatabase: String
    public var useTLS: Bool
    public var tlsAllowInvalidCertificates: Bool
    public var directConnection: Bool
    public var isDemoMode: Bool
    public var lastConnectedAt: Date?
    public var favoriteCollections: [String] // Array of "database.collection" identifiers
    public var hasStoredKeychainPassword: Bool

    public init(
        id: UUID = UUID(),
        name: String = "Local MongoDB",
        colorName: String = "emerald",
        useURI: Bool = true,
        uriString: String = "mongodb://127.0.0.1:27017",
        host: String = "127.0.0.1",
        port: Int = 27017,
        authEnabled: Bool = false,
        username: String = "",
        password: String = "",
        authDatabase: String = "admin",
        defaultDatabase: String = "",
        useTLS: Bool = false,
        tlsAllowInvalidCertificates: Bool = false,
        directConnection: Bool = false,
        isDemoMode: Bool = false,
        lastConnectedAt: Date? = nil,
        favoriteCollections: [String] = [],
        hasStoredKeychainPassword: Bool = false
    ) {
        self.id = id
        self.name = name
        self.colorName = colorName
        self.useURI = useURI
        self.uriString = uriString
        self.host = host
        self.port = port
        self.authEnabled = authEnabled
        self.username = username
        self.password = password
        self.authDatabase = authDatabase
        self.defaultDatabase = defaultDatabase
        self.useTLS = useTLS
        self.tlsAllowInvalidCertificates = tlsAllowInvalidCertificates
        self.directConnection = directConnection
        self.isDemoMode = isDemoMode
        self.lastConnectedAt = lastConnectedAt
        self.favoriteCollections = favoriteCollections
        self.hasStoredKeychainPassword = hasStoredKeychainPassword
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.colorName = try container.decode(String.self, forKey: .colorName)
        self.useURI = try container.decode(Bool.self, forKey: .useURI)
        self.uriString = try container.decode(String.self, forKey: .uriString)
        self.host = try container.decode(String.self, forKey: .host)
        self.port = try container.decode(Int.self, forKey: .port)
        self.authEnabled = try container.decode(Bool.self, forKey: .authEnabled)
        self.username = try container.decode(String.self, forKey: .username)
        self.password = try container.decodeIfPresent(String.self, forKey: .password) ?? ""
        self.authDatabase = try container.decode(String.self, forKey: .authDatabase)
        self.defaultDatabase = try container.decode(String.self, forKey: .defaultDatabase)
        self.useTLS = try container.decode(Bool.self, forKey: .useTLS)
        self.tlsAllowInvalidCertificates = try container.decodeIfPresent(Bool.self, forKey: .tlsAllowInvalidCertificates) ?? false
        self.directConnection = try container.decodeIfPresent(Bool.self, forKey: .directConnection) ?? false
        self.isDemoMode = try container.decode(Bool.self, forKey: .isDemoMode)
        self.lastConnectedAt = try container.decodeIfPresent(Date.self, forKey: .lastConnectedAt)
        self.favoriteCollections = try container.decodeIfPresent([String].self, forKey: .favoriteCollections) ?? []
        self.hasStoredKeychainPassword = try container.decodeIfPresent(Bool.self, forKey: .hasStoredKeychainPassword) ?? false
    }

    public struct ResolvedEndpoint: Sendable {
        public var isSRV: Bool
        public var seedHosts: [(host: String, port: UInt16)]
        public var username: String?
        public var password: String?
        public var authDatabase: String
        public var authSourceExplicit: Bool
        public var defaultDatabase: String?
        public var useTLS: Bool
        public var tlsAllowInvalidCertificates: Bool
        public var directConnection: Bool
    }

    public func resolveEndpoint() throws -> ResolvedEndpoint {
        if useURI {
            var resolved = try Self.parseMongoURI(uriString)
            // Supplement credentials or flags entered in form fields if URI lacks password
            if (resolved.password == nil || resolved.password?.isEmpty == true),
               authEnabled, !password.isEmpty {
                resolved.password = password
            }
            if tlsAllowInvalidCertificates {
                resolved.tlsAllowInvalidCertificates = true
            }
            if directConnection {
                resolved.directConnection = true
            }
            return resolved
        } else {
            let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedHost.isEmpty else {
                throw MongoDriverError.connectionFailed("Host cannot be empty.")
            }
            let validPort = UInt16(clamping: max(1, min(65535, port)))
            let user = authEnabled && !username.isEmpty ? username : nil
            let pass = authEnabled ? password : nil
            let cleanAuthDB = authDatabase.trimmingCharacters(in: .whitespacesAndNewlines)
            let authDB = cleanAuthDB.isEmpty ? "admin" : cleanAuthDB
            let defDB = defaultDatabase.trimmingCharacters(in: .whitespacesAndNewlines)
            return ResolvedEndpoint(
                isSRV: false,
                seedHosts: [(trimmedHost, validPort)],
                username: user,
                password: pass,
                authDatabase: authDB,
                authSourceExplicit: !cleanAuthDB.isEmpty,
                defaultDatabase: defDB.isEmpty ? nil : defDB,
                useTLS: useTLS,
                tlsAllowInvalidCertificates: tlsAllowInvalidCertificates,
                directConnection: directConnection
            )
        }
    }

    public mutating func syncFieldsFromURI() {
        guard let resolved = try? Self.parseMongoURI(uriString) else { return }
        if let first = resolved.seedHosts.first {
            self.host = first.host
            self.port = Int(first.port)
        }
        if let u = resolved.username, !u.isEmpty {
            self.authEnabled = true
            self.username = u
            if let p = resolved.password {
                self.password = p
            }
        } else {
            self.authEnabled = false
        }
        self.authDatabase = resolved.authDatabase
        self.defaultDatabase = resolved.defaultDatabase ?? ""
        self.useTLS = resolved.useTLS
        self.tlsAllowInvalidCertificates = resolved.tlsAllowInvalidCertificates
        self.directConnection = resolved.directConnection
    }

    public mutating func syncURIFromFields() {
        let isSRV = uriString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("mongodb+srv://")
        var out = isSRV ? "mongodb+srv://" : "mongodb://"

        if authEnabled && !username.isEmpty {
            let encUser = username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? username
            if !password.isEmpty {
                let encPass = password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? password
                out += "\(encUser):\(encPass)@"
            } else {
                out += "\(encUser)@"
            }
        }

        // Preserve additional comma-separated replica set hosts if already present in URI for non-SRV
        let rawHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryHost = rawHost.isEmpty ? "127.0.0.1" : rawHost
        let formattedHost = primaryHost.contains(":") && !primaryHost.hasPrefix("[") ? "[\(primaryHost)]" : primaryHost
        if isSRV {
            out += formattedHost
        } else {
            out += "\(formattedHost):\(port)"
        }

        let defDB = defaultDatabase.trimmingCharacters(in: .whitespacesAndNewlines)
        if !defDB.isEmpty {
            out += "/\(defDB)"
        }

        // Preserve any extra query parameters already in uriString (e.g. retryWrites, w, replicaSet, appName)
        var preservedParams: [(String, String)] = []
        let managedKeys: Set<String> = ["authsource", "tls", "ssl", "tlsallowinvalidcertificates", "tlsinsecure", "directconnection"]
        if let qIdx = uriString.firstIndex(of: "?") {
            let existingQuery = uriString[uriString.index(after: qIdx)...]
            for pair in existingQuery.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                if let kSub = kv.first {
                    let keyLower = String(kSub).lowercased()
                    if !managedKeys.contains(keyLower) {
                        let val = kv.count > 1 ? String(kv[1]) : ""
                        preservedParams.append((String(kSub), val))
                    }
                }
            }
        }

        var queryItems: [String] = preservedParams.map { $1.isEmpty ? $0 : "\($0)=\($1)" }
        let cleanAuthDB = authDatabase.trimmingCharacters(in: .whitespacesAndNewlines)
        if authEnabled && !cleanAuthDB.isEmpty && cleanAuthDB != "admin" {
            queryItems.append("authSource=\(cleanAuthDB)")
        }
        if useTLS && !isSRV {
            queryItems.append("tls=true")
        } else if !useTLS && isSRV {
            queryItems.append("tls=false")
        }
        if tlsAllowInvalidCertificates {
            queryItems.append("tlsAllowInvalidCertificates=true")
        }
        if directConnection && !isSRV {
            queryItems.append("directConnection=true")
        }
        if !queryItems.isEmpty {
            if defDB.isEmpty { out += "/" }
            out += "?" + queryItems.joined(separator: "&")
        }
        self.uriString = out
    }

    public static func parseMongoURI(_ rawURI: String) throws -> ResolvedEndpoint {
        let trimmed = rawURI.trimmingCharacters(in: .whitespacesAndNewlines)
        let isSRV: Bool
        let withoutScheme: String

        if trimmed.lowercased().hasPrefix("mongodb+srv://") {
            isSRV = true
            withoutScheme = String(trimmed.dropFirst("mongodb+srv://".count))
        } else if trimmed.lowercased().hasPrefix("mongodb://") {
            isSRV = false
            withoutScheme = String(trimmed.dropFirst("mongodb://".count))
        } else {
            throw MongoDriverError.connectionFailed("URI must start with mongodb:// or mongodb+srv://")
        }

        // Split authority and path/query
        let authorityAndRest = withoutScheme.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let authorityWithPossibleQuery = String(authorityAndRest[0])

        // Support mongodb://host?tls=true without slash before '?'
        let authority: String
        let pathAndQuery: String
        if authorityAndRest.count == 1, let qIdx = authorityWithPossibleQuery.firstIndex(of: "?") {
            authority = String(authorityWithPossibleQuery[..<qIdx])
            pathAndQuery = String(authorityWithPossibleQuery[qIdx...])
        } else {
            authority = authorityWithPossibleQuery
            pathAndQuery = authorityAndRest.count > 1 ? String(authorityAndRest[1]) : ""
        }

        var username: String?
        var password: String?
        let hostsPart: String

        if let atIndex = authority.lastIndex(of: "@") {
            let userInfo = String(authority[..<atIndex])
            hostsPart = String(authority[authority.index(after: atIndex)...])
            let userPass = userInfo.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            username = String(userPass[0]).removingPercentEncoding ?? String(userPass[0])
            if userPass.count > 1 {
                password = String(userPass[1]).removingPercentEncoding ?? String(userPass[1])
            }
        } else {
            hostsPart = authority
        }

        var seedHosts: [(host: String, port: UInt16)] = []
        for rawEntry in hostsPart.split(separator: ",") {
            let hostEntry = rawEntry.trimmingCharacters(in: .whitespaces)
            guard !hostEntry.isEmpty else { continue }

            let h: String
            var p: UInt16 = 27017

            if hostEntry.hasPrefix("[") {
                // Bracketed IPv6 literal, e.g. [::1]:27017 or [::1]
                if let closeBracket = hostEntry.firstIndex(of: "]") {
                    h = String(hostEntry[hostEntry.index(after: hostEntry.startIndex)..<closeBracket])
                    let remainder = hostEntry[hostEntry.index(after: closeBracket)...]
                    if remainder.hasPrefix(":"), let parsedPort = UInt16(remainder.dropFirst()) {
                        p = parsedPort
                    }
                } else {
                    h = hostEntry
                }
            } else {
                let hp = hostEntry.split(separator: ":", maxSplits: 1)
                h = String(hp[0]).trimmingCharacters(in: .whitespaces)
                if hp.count > 1, let parsedPort = UInt16(hp[1]) {
                    p = parsedPort
                }
            }

            if !h.isEmpty {
                seedHosts.append((h, p))
            }
        }

        guard !seedHosts.isEmpty else {
            throw MongoDriverError.connectionFailed("No host found in MongoDB URI.")
        }

        let pathAndQueryParts = pathAndQuery.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let dbPath = String(pathAndQueryParts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let queryString = pathAndQueryParts.count > 1 ? String(pathAndQueryParts[1]) : ""

        var queryOptions: [String: String] = [:]
        for pair in queryString.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.count == 2 {
                let k = String(kv[0]).lowercased()
                let v = String(kv[1]).removingPercentEncoding ?? String(kv[1])
                queryOptions[k] = v
            }
        }

        let defaultDB = dbPath.isEmpty ? nil : dbPath
        let explicitAuthSource = queryOptions["authsource"]
        let authDB = explicitAuthSource ?? defaultDB ?? "admin"

        let tlsOption = (queryOptions["tls"] ?? queryOptions["ssl"])?.lowercased()
        let useTLS: Bool
        if let tlsOpt = tlsOption {
            useTLS = (tlsOpt == "true" || tlsOpt == "1")
        } else {
            useTLS = isSRV
        }

        let allowInvalid = ["true", "1"].contains((queryOptions["tlsallowinvalidcertificates"] ?? "").lowercased())
            || ["true", "1"].contains((queryOptions["tlsinsecure"] ?? "").lowercased())
        let direct = ["true", "1"].contains((queryOptions["directconnection"] ?? "").lowercased())

        return ResolvedEndpoint(
            isSRV: isSRV,
            seedHosts: seedHosts,
            username: username,
            password: password,
            authDatabase: authDB,
            authSourceExplicit: explicitAuthSource != nil,
            defaultDatabase: defaultDB,
            useTLS: useTLS,
            tlsAllowInvalidCertificates: allowInvalid,
            directConnection: direct
        )
    }

    // MARK: - URI Password Redaction & Keychain Helpers
    public static func extractPasswordFromURI(_ uri: String) -> String? {
        guard let schemeRange = uri.range(of: "://") else { return nil }
        let afterScheme = uri[schemeRange.upperBound...]
        let authorityEnd = afterScheme.firstIndex(of: "/") ?? afterScheme.endIndex
        let authority = afterScheme[..<authorityEnd]
        guard let atIdx = authority.lastIndex(of: "@") else { return nil }
        let userInfo = authority[..<atIdx]
        guard let colonIdx = userInfo.firstIndex(of: ":") else { return nil }
        let rawPass = String(userInfo[userInfo.index(after: colonIdx)...])
        let decoded = rawPass.removingPercentEncoding ?? rawPass
        return decoded.isEmpty ? nil : decoded
    }

    public static func stripPasswordFromURI(_ uri: String) -> String {
        guard let schemeRange = uri.range(of: "://") else { return uri }
        let afterScheme = uri[schemeRange.upperBound...]
        let authorityEnd = afterScheme.firstIndex(of: "/") ?? afterScheme.endIndex
        let authority = afterScheme[..<authorityEnd]
        guard let atIdx = authority.lastIndex(of: "@") else { return uri }
        let userInfo = authority[..<atIdx]
        guard let colonIdx = userInfo.firstIndex(of: ":") else { return uri }
        let userOnly = uri[..<colonIdx]
        let hostAndRest = uri[atIdx...]
        return String(userOnly + hostAndRest)
    }

    public static func injectPasswordIntoURI(_ uri: String, password: String) -> String {
        guard !password.isEmpty,
              let schemeRange = uri.range(of: "://") else { return uri }
        let afterScheme = uri[schemeRange.upperBound...]
        let authorityEnd = afterScheme.firstIndex(of: "/") ?? afterScheme.endIndex
        let authority = afterScheme[..<authorityEnd]
        guard let atIdx = authority.lastIndex(of: "@") else { return uri }
        let userInfo = authority[..<atIdx]
        // Only inject if userInfo has a username with no ":password"
        guard !userInfo.isEmpty, !userInfo.contains(":") else { return uri }
        let encPass = password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? password
        return String(uri[..<atIdx]) + ":\(encPass)" + String(uri[atIdx...])
    }

    public static func maskedURI(_ uri: String) -> String {
        guard let schemeRange = uri.range(of: "://") else { return uri }
        let afterScheme = uri[schemeRange.upperBound...]
        let authorityEnd = afterScheme.firstIndex(of: "/") ?? afterScheme.endIndex
        let authority = afterScheme[..<authorityEnd]
        guard let atIdx = authority.lastIndex(of: "@") else { return uri }
        let userInfo = authority[..<atIdx]
        if let colonIdx = userInfo.firstIndex(of: ":") {
            let userOnly = uri[..<colonIdx]
            let hostAndRest = uri[atIdx...]
            return "\(userOnly):••••\(hostAndRest)"
        }
        return uri
    }

    public var displayAddress: String {
        if isDemoMode {
            return "Built-in Sample MongoDB (In-Memory)"
        }
        if useURI {
            return Self.maskedURI(uriString)
        }
        return "\(host):\(port)"
    }
}

public final class ConnectionStore {
    public static let shared = ConnectionStore()

    private let folderURL: URL
    private let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.folderURL = appSupport.appendingPathComponent("MongoEarlgrey", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folderURL.path)
        self.fileURL = folderURL.appendingPathComponent("connections.json")
    }

    public func loadConnections() -> [ConnectionConfig] {
        if let data = try? Data(contentsOf: fileURL),
           var decoded = try? JSONDecoder().decode([ConnectionConfig].self, from: data),
           !decoded.isEmpty {
            var needsMigrationSave = false
            for idx in decoded.indices {
                let connId = decoded[idx].id
                if decoded[idx].hasStoredKeychainPassword {
                    if let pw = KeychainStore.loadPassword(for: connId), !pw.isEmpty {
                        decoded[idx].password = pw
                        decoded[idx].uriString = ConnectionConfig.injectPasswordIntoURI(decoded[idx].uriString, password: pw)
                    }
                } else {
                    // Transparently migrate any legacy plaintext password into Keychain
                    let legacySecret = !decoded[idx].password.isEmpty
                        ? decoded[idx].password
                        : (ConnectionConfig.extractPasswordFromURI(decoded[idx].uriString) ?? "")
                    if !legacySecret.isEmpty {
                        decoded[idx].password = legacySecret
                        needsMigrationSave = true
                    }
                }
            }
            if needsMigrationSave {
                saveConnections(decoded)
            }
            return decoded
        }

        // Provide helpful starter connections on first launch
        let defaults: [ConnectionConfig] = [
            ConnectionConfig(
                name: "Localhost (27017)",
                colorName: "emerald",
                useURI: true,
                uriString: "mongodb://127.0.0.1:27017",
                host: "127.0.0.1",
                port: 27017
            ),
            ConnectionConfig(
                name: "Earlgrey Sandbox (Sample DB)",
                colorName: "amber",
                useURI: true,
                uriString: "mongodb://sandbox.local:27017/earlgrey_demo",
                host: "sandbox.local",
                port: 27017,
                isDemoMode: true
            )
        ]
        saveConnections(defaults)
        return defaults
    }

    public func saveConnections(_ connections: [ConnectionConfig]) {
        var sanitized: [ConnectionConfig] = []
        sanitized.reserveCapacity(connections.count)

        for conn in connections {
            var copy = conn
            let effectivePassword = !copy.password.isEmpty
                ? copy.password
                : (ConnectionConfig.extractPasswordFromURI(copy.uriString) ?? "")

            if !effectivePassword.isEmpty {
                if KeychainStore.savePassword(effectivePassword, for: copy.id) {
                    copy.password = ""
                    copy.uriString = ConnectionConfig.stripPasswordFromURI(copy.uriString)
                    copy.hasStoredKeychainPassword = true
                }
            } else {
                KeychainStore.deletePassword(for: copy.id)
                copy.hasStoredKeychainPassword = false
            }
            sanitized.append(copy)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(sanitized) {
            try? data.write(to: fileURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        }
    }
}

import Foundation

public actor DemoMongoStore {
    private var databases: [String: [String: [BSONDocument]]] = [:]

    public init() {
        self.databases = Self.makeSeedDatabases()
    }

    private static func makeSeedDatabases() -> [String: [String: [BSONDocument]]] {
        var databases: [String: [String: [BSONDocument]]] = [:]
        let now = Date()
        let customers: [BSONDocument] = [
            [
                "_id": .objectId(BSONObjectId(hex: "65f01a2b3c4d5e6f70819201")!),
                "name": .string("Eleanor Vance"),
                "email": .string("eleanor.vance@earlgrey.io"),
                "tier": .string("enterprise"),
                "active": .bool(true),
                "ordersCount": .int32(18),
                "lifetimeSpend": .double(4280.50),
                "address": .document([
                    "street": .string("42 Portobello Road"),
                    "city": .string("London"),
                    "postcode": .string("W11 2EB"),
                    "country": .string("UK")
                ]),
                "tags": .array([.string("vip"), .string("tea-club"), .string("london")]),
                "createdAt": .dateTime(now.addingTimeInterval(-86400 * 140))
            ],
            [
                "_id": .objectId(BSONObjectId(hex: "65f01a2b3c4d5e6f70819202")!),
                "name": .string("Arthur Pendelton"),
                "email": .string("arthur@pendelton.co.uk"),
                "tier": .string("pro"),
                "active": .bool(true),
                "ordersCount": .int32(7),
                "lifetimeSpend": .double(910.00),
                "address": .document([
                    "street": .string("19 King's Parade"),
                    "city": .string("Cambridge"),
                    "postcode": .string("CB2 1SJ"),
                    "country": .string("UK")
                ]),
                "tags": .array([.string("wholesale"), .string("bergamot")]),
                "createdAt": .dateTime(now.addingTimeInterval(-86400 * 95))
            ],
            [
                "_id": .objectId(BSONObjectId(hex: "65f01a2b3c4d5e6f70819203")!),
                "name": .string("Clara Lin"),
                "email": .string("clara.lin@studio-north.com"),
                "tier": .string("enterprise"),
                "active": .bool(true),
                "ordersCount": .int32(31),
                "lifetimeSpend": .double(8640.75),
                "address": .document([
                    "street": .string("88 George Street"),
                    "city": .string("Edinburgh"),
                    "postcode": .string("EH2 3BU"),
                    "country": .string("UK")
                ]),
                "tags": .array([.string("vip"), .string("annual-contract")]),
                "createdAt": .dateTime(now.addingTimeInterval(-86400 * 64))
            ],
            [
                "_id": .objectId(BSONObjectId(hex: "65f01a2b3c4d5e6f70819204")!),
                "name": .string("Marcus Thorne"),
                "email": .string("m.thorne@bristolroasters.org"),
                "tier": .string("starter"),
                "active": .bool(false),
                "ordersCount": .int32(2),
                "lifetimeSpend": .double(145.00),
                "address": .document([
                    "street": .string("14 Clifton Down"),
                    "city": .string("Bristol"),
                    "postcode": .string("BS8 4BF"),
                    "country": .string("UK")
                ]),
                "tags": .array([.string("trial")]),
                "createdAt": .dateTime(now.addingTimeInterval(-86400 * 30))
            ],
            [
                "_id": .objectId(BSONObjectId(hex: "65f01a2b3c4d5e6f70819205")!),
                "name": .string("Sophie Beaumont"),
                "email": .string("sophie@beaumont-hospitality.fr"),
                "tier": .string("pro"),
                "active": .bool(true),
                "ordersCount": .int32(12),
                "lifetimeSpend": .double(2390.20),
                "address": .document([
                    "street": .string("24 Rue des Rosiers"),
                    "city": .string("Paris"),
                    "postcode": .string("75004"),
                    "country": .string("France")
                ]),
                "tags": .array([.string("eu-export"), .string("tea-club")]),
                "createdAt": .dateTime(now.addingTimeInterval(-86400 * 14))
            ]
        ]

        let orders: [BSONDocument] = [
            [
                "_id": .objectId(BSONObjectId(hex: "65f02b3c4d5e6f7081920301")!),
                "orderNumber": .string("ORD-2026-1041"),
                "customerEmail": .string("eleanor.vance@earlgrey.io"),
                "status": .string("delivered"),
                "total": .double(348.50),
                "currency": .string("GBP"),
                "shipping": .document([
                    "carrier": .string("DPD Express"),
                    "trackingCode": .string("DPD884920194"),
                    "dispatchedAt": .dateTime(now.addingTimeInterval(-86400 * 5))
                ]),
                "items": .array([
                    .document(["sku": .string("TEA-EG-500G"), "qty": .int32(4), "unitPrice": .double(45.00)]),
                    .document(["sku": .string("TEA-OOL-250G"), "qty": .int32(3), "unitPrice": .double(56.16)])
                ]),
                "createdAt": .dateTime(now.addingTimeInterval(-86400 * 6))
            ],
            [
                "_id": .objectId(BSONObjectId(hex: "65f02b3c4d5e6f7081920302")!),
                "orderNumber": .string("ORD-2026-1042"),
                "customerEmail": .string("clara.lin@studio-north.com"),
                "status": .string("processing"),
                "total": .double(1120.00),
                "currency": .string("GBP"),
                "shipping": .document([
                    "carrier": .string("Royal Mail Special"),
                    "trackingCode": .string("RM991827361GB"),
                    "dispatchedAt": .null
                ]),
                "items": .array([
                    .document(["sku": .string("TEA-EG-IMP-1KG"), "qty": .int32(10), "unitPrice": .double(112.00)])
                ]),
                "createdAt": .dateTime(now.addingTimeInterval(-86400 * 2))
            ],
            [
                "_id": .objectId(BSONObjectId(hex: "65f02b3c4d5e6f7081920303")!),
                "orderNumber": .string("ORD-2026-1043"),
                "customerEmail": .string("arthur@pendelton.co.uk"),
                "status": .string("shipped"),
                "total": .double(215.00),
                "currency": .string("GBP"),
                "shipping": .document([
                    "carrier": .string("DHL UK"),
                    "trackingCode": .string("DHL77261524"),
                    "dispatchedAt": .dateTime(now.addingTimeInterval(-86400 * 1))
                ]),
                "items": .array([
                    .document(["sku": .string("TEA-DARJ-500G"), "qty": .int32(2), "unitPrice": .double(107.50)])
                ]),
                "createdAt": .dateTime(now.addingTimeInterval(-3600 * 30))
            ]
        ]

        let products: [BSONDocument] = [
            [
                "_id": .objectId(BSONObjectId(hex: "65f03c4d5e6f708192040101")!),
                "sku": .string("TEA-EG-IMP-1KG"),
                "name": .string("Imperial Calabrian Earl Grey"),
                "category": .string("Black Tea"),
                "inStock": .bool(true),
                "stockQty": .int32(142),
                "price": .double(112.00),
                "origin": .document([
                    "estate": .string("Ruhuna & Reggio Calabria"),
                    "harvest": .string("Spring 2026"),
                    "organic": .bool(true)
                ])
            ],
            [
                "_id": .objectId(BSONObjectId(hex: "65f03c4d5e6f708192040102")!),
                "sku": .string("TEA-DARJ-500G"),
                "name": .string("First Flush Margaret's Hope Darjeeling"),
                "category": .string("Black Tea"),
                "inStock": .bool(true),
                "stockQty": .int32(58),
                "price": .double(107.50),
                "origin": .document([
                    "estate": .string("Margaret's Hope"),
                    "harvest": .string("March 2026"),
                    "organic": .bool(true)
                ])
            ],
            [
                "_id": .objectId(BSONObjectId(hex: "65f03c4d5e6f708192040103")!),
                "sku": .string("TEA-OOL-250G"),
                "name": .string("Alishan High Mountain Oolong"),
                "category": .string("Oolong"),
                "inStock": .bool(false),
                "stockQty": .int32(0),
                "price": .double(56.16),
                "origin": .document([
                    "estate": .string("Chiayi County"),
                    "harvest": .string("Winter 2025"),
                    "organic": .bool(false)
                ])
            ]
        ]

        databases["earlgrey_store"] = [
            "customers": customers,
            "orders": orders,
            "products": products
        ]

        databases["analytics"] = [
            "events": [
                [
                    "_id": .objectId(BSONObjectId(hex: "65f04d5e6f70819205010001")!),
                    "event": .string("checkout.completed"),
                    "latencyMs": .int32(42),
                    "region": .string("eu-west-2"),
                    "meta": .document(["browser": .string("Safari 18"), "platform": .string("macOS")]),
                    "timestamp": .dateTime(now.addingTimeInterval(-1200))
                ],
                [
                    "_id": .objectId(BSONObjectId(hex: "65f04d5e6f70819205010002")!),
                    "event": .string("search.query"),
                    "latencyMs": .int32(11),
                    "region": .string("eu-west-2"),
                    "meta": .document(["query": .string("bergamot"), "results": .int32(9)]),
                    "timestamp": .dateTime(now.addingTimeInterval(-600))
                ]
            ]
        ]
        return databases
    }

    public func listDatabasesWithCollections() -> [DatabaseSummary] {
        databases.keys.sorted().map { dbName in
            let cols = listCollections(inDatabase: dbName)
            return DatabaseSummary(name: dbName, sizeOnDisk: 1024 * 64, empty: cols.isEmpty, collections: cols)
        }
    }

    public func listCollections(inDatabase dbName: String) -> [CollectionSummary] {
        let dict = databases[dbName] ?? [:]
        return dict.keys.sorted().map { colName in
            CollectionSummary(database: dbName, name: colName, type: "collection")
        }
    }

    public func executeQuery(
        database: String,
        collection: String,
        parsedQuery: ParsedMongoQuery,
        fallbackLimit: Int,
        fallbackSkip: Int
    ) -> QueryExecutionResult {
        let allDocs = databases[database]?[collection] ?? []
        let filtered = allDocs.filter { matchesFilter(document: $0, filter: parsedQuery.filter) }

        switch parsedQuery.operation {
        case .count:
            let countDoc: BSONDocument = ["count": .int64(Int64(filtered.count))]
            return QueryExecutionResult(
                documents: [countDoc],
                totalCount: filtered.count,
                executionTimeMs: 0.8,
                statusText: "Count: \(filtered.count)"
            )
        case .aggregate:
            return QueryExecutionResult(
                documents: filtered,
                totalCount: filtered.count,
                executionTimeMs: 1.1,
                statusText: "\(filtered.count) documents"
            )
        case .find:
            var sorted = filtered
            if let sortDoc = parsedQuery.sort, !sortDoc.isEmpty {
                sorted.sort { a, b in
                    for el in sortDoc.elements {
                        let dir = (el.value.intValue ?? 1) >= 0 ? 1 : -1
                        let va = a.value(atPath: el.key) ?? .null
                        let vb = b.value(atPath: el.key) ?? .null
                        let cmp = compareBSONValues(va, vb)
                        if cmp != 0 {
                            return dir > 0 ? (cmp < 0) : (cmp > 0)
                        }
                    }
                    return false
                }
            }

            let skip = max(0, parsedQuery.skip ?? fallbackSkip)
            let limit = max(1, parsedQuery.limit ?? fallbackLimit)
            let sliced = Array(sorted.dropFirst(skip).prefix(limit))

            let projected: [BSONDocument]
            if let proj = parsedQuery.projection, !proj.isEmpty {
                projected = sliced.map { applyProjection(document: $0, projection: proj) }
            } else {
                projected = sliced
            }

            let rangeStart = skip + (projected.isEmpty ? 0 : 1)
            let rangeEnd = skip + projected.count
            let status = projected.isEmpty
                ? "0 of \(filtered.count) \(filtered.count == 1 ? "doc" : "docs")"
                : "Showing \(rangeStart)–\(rangeEnd) of \(filtered.count) \(filtered.count == 1 ? "doc" : "docs")"

            return QueryExecutionResult(
                documents: projected,
                totalCount: filtered.count,
                executionTimeMs: 0.7,
                statusText: status
            )
        }
    }

    public func replaceDocument(
        database: String,
        collection: String,
        originalId: BSONValue,
        replacement: BSONDocument
    ) throws {
        var docs = databases[database]?[collection] ?? []
        guard let idx = docs.firstIndex(where: { $0["_id"] == originalId }) else {
            throw MongoDriverError.commandFailed(code: 404, message: "Document with matching _id not found.")
        }
        var updated = replacement
        if updated["_id"] == nil {
            var elems = [BSONElement(key: "_id", value: originalId)]
            elems.append(contentsOf: updated.elements)
            updated = BSONDocument(elements: elems)
        }
        docs[idx] = updated
        databases[database, default: [:]][collection] = docs
    }

    public func insertDocument(
        database: String,
        collection: String,
        document: BSONDocument
    ) throws {
        var docs = databases[database]?[collection] ?? []
        var docToInsert = document
        if docToInsert["_id"] == nil {
            var elems = [BSONElement(key: "_id", value: .objectId(BSONObjectId.generate()))]
            elems.append(contentsOf: docToInsert.elements)
            docToInsert = BSONDocument(elements: elems)
        }
        docs.insert(docToInsert, at: 0)
        databases[database, default: [:]][collection] = docs
    }

    // MARK: - Filter Evaluator
    private func matchesFilter(document: BSONDocument, filter: BSONDocument) -> Bool {
        if filter.isEmpty { return true }
        for el in filter.elements {
            if el.key == "$and", case .array(let clauses) = el.value {
                for clause in clauses {
                    if case .document(let subFilter) = clause, !matchesFilter(document: document, filter: subFilter) {
                        return false
                    }
                }
                continue
            }
            if el.key == "$or", case .array(let clauses) = el.value {
                let anyMatch = clauses.contains { clause in
                    if case .document(let subFilter) = clause {
                        return matchesFilter(document: document, filter: subFilter)
                    }
                    return false
                }
                if !anyMatch { return false }
                continue
            }
            if el.key == "$nor", case .array(let clauses) = el.value {
                let anyMatch = clauses.contains { clause in
                    if case .document(let subFilter) = clause {
                        return matchesFilter(document: document, filter: subFilter)
                    }
                    return false
                }
                if anyMatch { return false }
                continue
            }

            let docValue = document.value(atPath: el.key) ?? .null
            if !matchesFieldCondition(docValue: docValue, condition: el.value) {
                return false
            }
        }
        return true
    }

    private func matchesFieldCondition(docValue: BSONValue, condition: BSONValue) -> Bool {
        if case .document(let condDoc) = condition,
           let firstKey = condDoc.keys.first,
           firstKey.hasPrefix("$") {
            for op in condDoc.elements {
                switch op.key {
                case "$eq":
                    if !valuesEqual(docValue, op.value) { return false }
                case "$ne":
                    if valuesEqual(docValue, op.value) { return false }
                case "$not":
                    if matchesFieldCondition(docValue: docValue, condition: op.value) { return false }
                case "$size":
                    if case .array(let arr) = docValue, let targetSize = op.value.intValue {
                        if arr.count != targetSize { return false }
                    } else {
                        return false
                    }
                case "$gt":
                    if compareBSONValues(docValue, op.value) <= 0 { return false }
                case "$gte":
                    if compareBSONValues(docValue, op.value) < 0 { return false }
                case "$lt":
                    if compareBSONValues(docValue, op.value) >= 0 { return false }
                case "$lte":
                    if compareBSONValues(docValue, op.value) > 0 { return false }
                case "$in":
                    if case .array(let list) = op.value {
                        let matched = list.contains { valuesEqual(docValue, $0) }
                        if !matched { return false }
                    }
                case "$nin":
                    if case .array(let list) = op.value {
                        let matched = list.contains { valuesEqual(docValue, $0) }
                        if matched { return false }
                    }
                case "$exists":
                    let shouldExist = op.value.boolValue ?? true
                    let exists = (docValue != .null && docValue != .undefined)
                    if shouldExist != exists { return false }
                case "$regex":
                    if let pattern = op.value.stringValue {
                        let options = condDoc["$options"]?.stringValue ?? ""
                        if !matchesRegex(docValue: docValue, pattern: pattern, options: options) {
                            return false
                        }
                    }
                default:
                    break
                }
            }
            return true
        }

        if case .regex(let pattern, let options) = condition {
            return matchesRegex(docValue: docValue, pattern: pattern, options: options)
        }

        if case .array(let arr) = docValue, !isArray(condition) {
            return arr.contains { valuesEqual($0, condition) }
        }

        return valuesEqual(docValue, condition)
    }

    private func isArray(_ v: BSONValue) -> Bool {
        if case .array = v { return true }
        return false
    }

    private func matchesRegex(docValue: BSONValue, pattern: String, options: String) -> Bool {
        guard let str = docValue.stringValue else { return false }
        var regexOpts: NSRegularExpression.Options = []
        if options.contains("i") { regexOpts.insert(.caseInsensitive) }
        if options.contains("m") { regexOpts.insert(.anchorsMatchLines) }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: regexOpts) else {
            return false
        }
        let range = NSRange(str.startIndex..<str.endIndex, in: str)
        return regex.firstMatch(in: str, options: [], range: range) != nil
    }

    private func valuesEqual(_ a: BSONValue, _ b: BSONValue) -> Bool {
        if a == b { return true }
        if let da = a.doubleValue, let db = b.doubleValue {
            return da == db
        }
        return false
    }

    private func compareBSONValues(_ a: BSONValue, _ b: BSONValue) -> Int {
        if let da = a.doubleValue, let db = b.doubleValue {
            if da < db { return -1 }
            if da > db { return 1 }
            return 0
        }
        if let sa = a.stringValue, let sb = b.stringValue {
            return sa.compare(sb).rawValue
        }
        if case .dateTime(let d1) = a, case .dateTime(let d2) = b {
            if d1 < d2 { return -1 }
            if d1 > d2 { return 1 }
            return 0
        }
        if case .objectId(let o1) = a, case .objectId(let o2) = b {
            return o1.hexString.compare(o2.hexString).rawValue
        }
        return a.displayCellText.compare(b.displayCellText).rawValue
    }

    private func applyProjection(document: BSONDocument, projection: BSONDocument) -> BSONDocument {
        let includeKeys = projection.elements.filter { ($0.value.intValue ?? 0) != 0 && $0.key != "_id" }.map(\.key)
        let excludeId = (projection["_id"]?.intValue ?? 1) == 0

        if !includeKeys.isEmpty {
            var elems: [BSONElement] = []
            if !excludeId, let idVal = document["_id"] {
                elems.append(BSONElement(key: "_id", value: idVal))
            }
            for k in includeKeys {
                if let v = document[k] {
                    elems.append(BSONElement(key: k, value: v))
                }
            }
            return BSONDocument(elements: elems)
        } else {
            let excludeKeys = Set(projection.elements.filter { ($0.value.intValue ?? 1) == 0 }.map(\.key))
            return BSONDocument(elements: document.elements.filter { !excludeKeys.contains($0.key) })
        }
    }
}

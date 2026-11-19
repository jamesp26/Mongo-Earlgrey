import Foundation
import JavaScriptCore

public struct ParsedMongoQuery: Sendable {
    public enum Operation: Sendable {
        case find
        case count
        case aggregate(pipeline: [BSONValue])
    }

    public var collection: String?
    public var operation: Operation
    public var filter: BSONDocument
    public var projection: BSONDocument?
    public var sort: BSONDocument?
    public var limit: Int?
    public var skip: Int?
}

public enum ShellParserError: LocalizedError {
    case emptyInput
    case syntaxError(String)
    case invalidDocumentRoot

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            return "Query cannot be empty."
        case .syntaxError(let msg):
            return "Syntax Error: \(msg)"
        case .invalidDocumentRoot:
            return "Document must evaluate to a valid JSON / BSON object {...}."
        }
    }
}

public final class ShellQueryParser {
    private static let bootstrapJS = #"""
    function ObjectId(hex) {
        if (!(this instanceof ObjectId)) return new ObjectId(hex);
        this.__bsonType = "ObjectId";
        this.value = (hex === undefined || hex === null) ? "" : String(hex);
    }
    function ISODate(str) {
        if (!(this instanceof ISODate)) return new ISODate(str);
        this.__bsonType = "Date";
        if (str === undefined || str === null) {
            this.value = new Date().toISOString();
        } else {
            var d = new Date(str);
            if (isNaN(d.getTime())) {
                throw new Error("Invalid ISODate value: " + str);
            }
            this.value = d.toISOString();
        }
    }
    function NumberLong(v) {
        if (!(this instanceof NumberLong)) return new NumberLong(v);
        this.__bsonType = "Int64";
        this.value = String(v);
    }
    function Long(v) {
        return NumberLong(v);
    }
    function NumberInt(v) {
        if (!(this instanceof NumberInt)) return new NumberInt(v);
        this.__bsonType = "Int32";
        var n = Number(v);
        if (!Number.isFinite(n) || Math.floor(n) !== n || n < -2147483648 || n > 2147483647) {
            throw new Error("Invalid Int32 / NumberInt value: " + v);
        }
        this.value = n;
    }
    function Int32(v) {
        return NumberInt(v);
    }
    function Double(v) {
        if (!(this instanceof Double)) return new Double(v);
        this.__bsonType = "Double";
        if (v === "NaN") { this.value = NaN; }
        else if (v === "Infinity") { this.value = Infinity; }
        else if (v === "-Infinity") { this.value = -Infinity; }
        else { this.value = Number(v); }
    }
    function NumberDecimal(v) {
        if (!(this instanceof NumberDecimal)) return new NumberDecimal(v);
        this.__bsonType = "Decimal128";
        this.value = String(v);
    }
    function Decimal128(v) {
        return NumberDecimal(v);
    }
    function UUID(v) {
        if (!(this instanceof UUID)) return new UUID(v);
        this.__bsonType = "UUID";
        this.value = String(v);
    }
    function BinData(subtype, base64) {
        if (!(this instanceof BinData)) return new BinData(subtype, base64);
        this.__bsonType = "BinData";
        this.subtype = Number(subtype || 0);
        this.value = String(base64 || "");
    }
    function Timestamp(t, i) {
        if (!(this instanceof Timestamp)) return new Timestamp(t, i);
        this.__bsonType = "Timestamp";
        this.t = Number(t || 0);
        this.i = Number(i || 0);
    }
    function MinKey() {
        if (!(this instanceof MinKey)) return new MinKey();
        this.__bsonType = "MinKey";
    }
    function MaxKey() {
        if (!(this instanceof MaxKey)) return new MaxKey();
        this.__bsonType = "MaxKey";
    }

    function __QueryCursor(collectionName, op, filter, projection) {
        this.__isQueryCursor = true;
        this.collection = collectionName;
        this.operation = op || "find";
        this.filter = filter || {};
        this.projection = projection || null;
        this._sort = null;
        this._limit = null;
        this._skip = null;
        this._pipeline = null;
    }
    __QueryCursor.prototype.sort = function(s) { this._sort = s; return this; };
    __QueryCursor.prototype.limit = function(n) { this._limit = Number(n); return this; };
    __QueryCursor.prototype.skip = function(n) { this._skip = Number(n); return this; };
    __QueryCursor.prototype.projection = function(p) { this.projection = p; return this; };
    __QueryCursor.prototype.project = function(p) { this.projection = p; return this; };
    __QueryCursor.prototype.count = function() { this.operation = "count"; return this; };
    __QueryCursor.prototype.pretty = function() { return this; };
    __QueryCursor.prototype.toArray = function() { return this; };

    function __CollectionHandle(name) {
        this._name = name;
    }
    __CollectionHandle.prototype.find = function(filter, projection) {
        return new __QueryCursor(this._name, "find", filter || {}, projection || null);
    };
    __CollectionHandle.prototype.findOne = function(filter, projection) {
        var c = new __QueryCursor(this._name, "find", filter || {}, projection || null);
        c._limit = 1;
        return c;
    };
    __CollectionHandle.prototype.count = function(filter) {
        return new __QueryCursor(this._name, "count", filter || {}, null);
    };
    __CollectionHandle.prototype.countDocuments = function(filter) {
        return new __QueryCursor(this._name, "count", filter || {}, null);
    };
    __CollectionHandle.prototype.aggregate = function(pipeline) {
        var c = new __QueryCursor(this._name, "aggregate", {}, null);
        c._pipeline = Array.isArray(pipeline) ? pipeline : [pipeline];
        return c;
    };

    var db = new Proxy({
        getCollection: function(name) {
            return new __CollectionHandle(String(name));
        }
    }, {
        get: function(target, prop) {
            if (prop in target) return target[prop];
            return new __CollectionHandle(String(prop));
        }
    });

    function __unescapeRegExpSource(src) {
        var out = "";
        for (var i = 0; i < src.length; i++) {
            if (src[i] === "\\" && i + 1 < src.length) {
                if (src[i + 1] === "/") {
                    out += "/";
                } else {
                    out += "\\" + src[i + 1];
                }
                i++;
            } else {
                out += src[i];
            }
        }
        return out;
    }

    function __serializeDouble(val) {
        if (Number.isNaN(val)) return { t: "double", v: "NaN" };
        if (!Number.isFinite(val)) return { t: "double", v: val > 0 ? "Infinity" : "-Infinity" };
        return { t: "double", v: val };
    }

    function __serializeBSONValue(val) {
        if (val === null) return { t: "null" };
        if (val === undefined) return { t: "undefined" };
        var type = typeof val;
        if (type === "boolean") return { t: "bool", v: val };
        if (type === "number") {
            if (Number.isNaN(val) || !Number.isFinite(val)) {
                return __serializeDouble(val);
            }
            if (Number.isInteger(val)) {
                if (val >= -2147483648 && val <= 2147483647) {
                    return { t: "int32", v: val };
                }
                return { t: "int64", v: String(val) };
            }
            return { t: "double", v: val };
        }
        if (type === "string") return { t: "string", v: val };
        if (val instanceof Date) {
            if (isNaN(val.getTime())) throw new Error("Invalid Date object");
            return { t: "date", v: val.toISOString() };
        }
        if (val instanceof RegExp) {
            var rxSource = __unescapeRegExpSource(val.source);
            if (rxSource === "(?:)") rxSource = "";
            return { t: "regex", p: rxSource, o: val.flags };
        }
        if (Array.isArray(val)) {
            return { t: "array", v: val.map(__serializeBSONValue) };
        }
        if (type === "object") {
            if (val.__bsonType === "ObjectId") return { t: "oid", v: String(val.value) };
            if (val.__bsonType === "Date") return { t: "date", v: String(val.value) };
            if (val.__bsonType === "Int64") return { t: "int64", v: String(val.value) };
            if (val.__bsonType === "Int32") return { t: "int32", v: Number(val.value) };
            if (val.__bsonType === "Double") return __serializeDouble(Number(val.value));
            if (val.__bsonType === "UUID") return { t: "uuid", v: String(val.value) };
            if (val.__bsonType === "BinData") return { t: "bindata", s: val.subtype, v: val.value };
            if (val.__bsonType === "Timestamp") return { t: "ts", t_sec: val.t, inc: val.i };
            if (val.__bsonType === "Decimal128") return { t: "dec128", v: val.value };
            if (val.__bsonType === "MinKey") return { t: "minKey" };
            if (val.__bsonType === "MaxKey") return { t: "maxKey" };

            // Support MongoDB Extended JSON v2 ($oid, $date, $numberLong, $numberDecimal, $binary, etc.)
            var keys = Reflect.ownKeys(val).filter(function(k) { return typeof k === "string"; });
            if (keys.length === 1) {
                var k0 = keys[0];
                var v0 = val[k0];
                if (k0 === "$oid") return { t: "oid", v: String(v0) };
                if (k0 === "$date") {
                    if (v0 && typeof v0 === "object" && v0["$numberLong"] !== undefined) {
                        var ms = Number(v0["$numberLong"]);
                        var d = new Date(ms);
                        if (isNaN(d.getTime())) throw new Error("Invalid $date timestamp");
                        return { t: "date", v: d.toISOString() };
                    }
                    return { t: "date", v: String(v0) };
                }
                if (k0 === "$numberLong") return { t: "int64", v: String(v0) };
                if (k0 === "$numberInt") {
                    var parsedInt = Number(v0);
                    if (!Number.isInteger(parsedInt) || parsedInt < -2147483648 || parsedInt > 2147483647) {
                        throw new Error("Invalid $numberInt value: " + v0);
                    }
                    return { t: "int32", v: parsedInt };
                }
                if (k0 === "$numberDouble") {
                    if (v0 === "NaN") return { t: "double", v: "NaN" };
                    if (v0 === "Infinity" || v0 === "+Infinity") return { t: "double", v: "Infinity" };
                    if (v0 === "-Infinity") return { t: "double", v: "-Infinity" };
                    return __serializeDouble(Number(v0));
                }
                if (k0 === "$numberDecimal") return { t: "dec128", v: String(v0) };
                if (k0 === "$uuid") return { t: "uuid", v: String(v0) };
                if (k0 === "$binary" && v0 && typeof v0 === "object") {
                    var sub = parseInt(v0.subType || "0", 16);
                    return { t: "bindata", s: isNaN(sub) ? 0 : sub, v: String(v0.base64 || "") };
                }
                if (k0 === "$regularExpression" && v0 && typeof v0 === "object") {
                    return { t: "regex", p: String(v0.pattern || ""), o: String(v0.options || "") };
                }
                if (k0 === "$timestamp" && v0 && typeof v0 === "object") {
                    return { t: "ts", t_sec: Number(v0.t || 0), inc: Number(v0.i || 0) };
                }
                if (k0 === "$minKey") return { t: "minKey" };
                if (k0 === "$maxKey") return { t: "maxKey" };
            }

            var entries = [];
            for (var i = 0; i < keys.length; i++) {
                var k = keys[i];
                entries.push([k, __serializeBSONValue(val[k])]);
            }
            return { t: "doc", v: entries };
        }
        return { t: "string", v: String(val) };
    }

    function __evaluateQueryInput(input) {
        var trimmed = input.trim();
        // Remove trailing semicolons
        while (trimmed.endsWith(";")) {
            trimmed = trimmed.slice(0, -1).trim();
        }
        var result;
        if (trimmed.startsWith("{")) {
            result = eval("(" + trimmed + ")");
        } else {
            result = eval(trimmed);
        }
        if (result && result.__isQueryCursor) {
            return JSON.stringify({
                kind: "cursor",
                collection: result.collection,
                operation: result.operation,
                filter: __serializeBSONValue(result.filter),
                projection: result.projection ? __serializeBSONValue(result.projection) : null,
                sort: result._sort ? __serializeBSONValue(result._sort) : null,
                limit: result._limit,
                skip: result._skip,
                pipeline: result._pipeline ? __serializeBSONValue(result._pipeline) : null
            });
        } else if (result && typeof result === "object" && !Array.isArray(result)) {
            return JSON.stringify({
                kind: "filterOnly",
                filter: __serializeBSONValue(result)
            });
        } else {
            throw new Error("Expected db.getCollection(\"...\").find({...}) or a filter object {...}");
        }
    }

    function __evaluateDocumentInput(input) {
        var trimmed = input.trim();
        while (trimmed.endsWith(";")) {
            trimmed = trimmed.slice(0, -1).trim();
        }
        var result = eval("(" + trimmed + ")");
        if (!result || typeof result !== "object" || Array.isArray(result)) {
            throw new Error("Root value must be a document object {...}");
        }
        return JSON.stringify(__serializeBSONValue(result));
    }
    """#

    /// Parse a Studio 3T / mongosh query string such as `db.getCollection("users").find({ active: true }).sort({ _id: -1 }).limit(50)`
    /// or a bare filter object `{ active: true }`.
    public static func parseQuery(_ queryText: String, defaultCollection: String? = nil) throws -> ParsedMongoQuery {
        let trimmed = queryText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ParsedMongoQuery(
                collection: defaultCollection,
                operation: .find,
                filter: BSONDocument(),
                projection: nil,
                sort: nil,
                limit: nil,
                skip: nil
            )
        }

        let context = JSContext()!
        var jsError: String?
        context.exceptionHandler = { _, exception in
            jsError = exception?.toString() ?? "Unknown JavaScript syntax error"
        }
        context.evaluateScript(bootstrapJS)

        let fn = context.objectForKeyedSubscript("__evaluateQueryInput")!
        let jsResult = fn.call(withArguments: [trimmed])

        if let err = jsError {
            throw ShellParserError.syntaxError(err)
        }

        guard let jsonString = jsResult?.toString(),
              let jsonData = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let kind = dict["kind"] as? String else {
            throw ShellParserError.syntaxError("Could not evaluate query expression.")
        }

        if kind == "filterOnly" {
            guard let filterObj = dict["filter"] as? [String: Any],
                  case .document(let filterDoc) = try decodeSerializedNode(filterObj) else {
                throw ShellParserError.invalidDocumentRoot
            }
            return ParsedMongoQuery(
                collection: defaultCollection,
                operation: .find,
                filter: filterDoc,
                projection: nil,
                sort: nil,
                limit: nil,
                skip: nil
            )
        }

        let collection = (dict["collection"] as? String) ?? defaultCollection
        let opString = (dict["operation"] as? String) ?? "find"

        var filterDoc = BSONDocument()
        if let filterObj = dict["filter"] as? [String: Any],
           case .document(let d) = try decodeSerializedNode(filterObj) {
            filterDoc = d
        }

        var projectionDoc: BSONDocument?
        if let projObj = dict["projection"] as? [String: Any],
           case .document(let d) = try decodeSerializedNode(projObj) {
            projectionDoc = d
        }

        var sortDoc: BSONDocument?
        if let sortObj = dict["sort"] as? [String: Any],
           case .document(let d) = try decodeSerializedNode(sortObj) {
            sortDoc = d
        }

        let limit = dict["limit"] as? Int
        let skip = dict["skip"] as? Int

        let operation: ParsedMongoQuery.Operation
        switch opString {
        case "count":
            operation = .count
        case "aggregate":
            if let pipeObj = dict["pipeline"] as? [String: Any],
               case .array(let arr) = try decodeSerializedNode(pipeObj) {
                operation = .aggregate(pipeline: arr)
            } else {
                operation = .aggregate(pipeline: [])
            }
        default:
            operation = .find
        }

        return ParsedMongoQuery(
            collection: collection,
            operation: operation,
            filter: filterDoc,
            projection: projectionDoc,
            sort: sortDoc,
            limit: limit,
            skip: skip
        )
    }

    /// Parse a Shell / Extended JSON document string into an ordered `BSONDocument`
    public static func parseDocument(_ text: String) throws -> BSONDocument {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ShellParserError.emptyInput
        }

        let context = JSContext()!
        var jsError: String?
        context.exceptionHandler = { _, exception in
            jsError = exception?.toString() ?? "Invalid document syntax"
        }
        context.evaluateScript(bootstrapJS)

        let fn = context.objectForKeyedSubscript("__evaluateDocumentInput")!
        let jsResult = fn.call(withArguments: [trimmed])

        if let err = jsError {
            throw ShellParserError.syntaxError(err)
        }

        guard let jsonString = jsResult?.toString(),
              let jsonData = jsonString.data(using: .utf8),
              let node = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              case .document(let doc) = try decodeSerializedNode(node) else {
            throw ShellParserError.invalidDocumentRoot
        }

        return doc
    }

    private static func decodeSerializedNode(_ node: [String: Any]) throws -> BSONValue {
        guard let type = node["t"] as? String else {
            return .null
        }
        switch type {
        case "null":
            return .null
        case "undefined":
            return .undefined
        case "bool":
            return .bool((node["v"] as? Bool) ?? false)
        case "int32":
            if let num = node["v"] as? NSNumber {
                return .int32(num.int32Value)
            }
            return .int32(0)
        case "int64":
            if let s = node["v"] as? String {
                let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let v = Int64(cleaned) else {
                    throw ShellParserError.syntaxError("Invalid NumberLong / Int64 value: '\(s)'")
                }
                return .int64(v)
            }
            if let num = node["v"] as? NSNumber {
                return .int64(num.int64Value)
            }
            throw ShellParserError.syntaxError("Missing NumberLong / Int64 value.")
        case "double":
            if let str = node["v"] as? String {
                switch str {
                case "NaN": return .double(.nan)
                case "Infinity": return .double(.infinity)
                case "-Infinity": return .double(-.infinity)
                default:
                    if let d = Double(str) { return .double(d) }
                    throw ShellParserError.syntaxError("Invalid Double value: '\(str)'")
                }
            }
            if let num = node["v"] as? NSNumber {
                return .double(num.doubleValue)
            }
            throw ShellParserError.syntaxError("Invalid Double value.")
        case "dec128":
            let str = (node["v"] as? String) ?? ""
            guard let bidData = BSONDecimal128.encodeFromString(str) else {
                throw ShellParserError.syntaxError("Invalid Decimal128 / NumberDecimal value: '\(str)'")
            }
            return .decimal128(bidData)
        case "string":
            return .string((node["v"] as? String) ?? "")
        case "oid":
            let hex = (node["v"] as? String) ?? ""
            if hex.isEmpty {
                return .objectId(BSONObjectId.generate())
            }
            guard let oid = BSONObjectId(hex: hex) else {
                throw ShellParserError.syntaxError("Invalid ObjectId hex string: '\(hex)' (must be 24 hex chars)")
            }
            return .objectId(oid)
        case "date":
            let str = (node["v"] as? String) ?? ""
            if let date = BSONValue.parseISODate(str) {
                return .dateTime(date)
            }
            throw ShellParserError.syntaxError("Invalid ISODate string: '\(str)'")
        case "regex":
            let p = (node["p"] as? String) ?? ""
            let o = (node["o"] as? String) ?? ""
            return .regex(pattern: p, options: o)
        case "uuid":
            let str = (node["v"] as? String) ?? ""
            if let uuid = UUID(uuidString: str) {
                let bytes = withUnsafeBytes(of: uuid.uuid) { Data($0) }
                return .binary(subtype: 4, data: bytes)
            }
            throw ShellParserError.syntaxError("Invalid UUID string: '\(str)'")
        case "bindata":
            let rawSubtype = (node["s"] as? Int) ?? 0
            guard rawSubtype >= 0 && rawSubtype <= 255 else {
                throw ShellParserError.syntaxError("Invalid BinData subtype: \(rawSubtype)")
            }
            let b64 = (node["v"] as? String) ?? ""
            guard let data = Data(base64Encoded: b64) else {
                throw ShellParserError.syntaxError("Invalid base64 string in BinData.")
            }
            return .binary(subtype: UInt8(rawSubtype), data: data)
        case "ts":
            let rawT = (node["t_sec"] as? NSNumber)?.int64Value ?? 0
            let rawI = (node["inc"] as? NSNumber)?.int64Value ?? 0
            guard rawT >= 0 && rawT <= Int64(UInt32.max) && rawI >= 0 && rawI <= Int64(UInt32.max) else {
                throw ShellParserError.syntaxError("Timestamp components must be unsigned 32-bit integers.")
            }
            let t = UInt64(rawT)
            let i = UInt64(rawI)
            return .timestamp((t << 32) | (i & 0xFFFFFFFF))
        case "minKey":
            return .minKey
        case "maxKey":
            return .maxKey
        case "array":
            let rawArr = (node["v"] as? [[String: Any]]) ?? []
            let values = try rawArr.map { try decodeSerializedNode($0) }
            return .array(values)
        case "doc":
            let rawEntries = (node["v"] as? [[Any]]) ?? []
            var elements: [BSONElement] = []
            elements.reserveCapacity(rawEntries.count)
            for pair in rawEntries {
                guard pair.count == 2,
                      let key = pair[0] as? String,
                      let valDict = pair[1] as? [String: Any] else { continue }
                let bsonVal = try decodeSerializedNode(valDict)
                elements.append(BSONElement(key: key, value: bsonVal))
            }
            return .document(BSONDocument(elements: elements))
        default:
            return .null
        }
    }
}

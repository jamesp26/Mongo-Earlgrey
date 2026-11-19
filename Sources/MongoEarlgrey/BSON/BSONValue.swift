import Foundation

// MARK: - BSON ObjectId (12-byte identifier)
public struct BSONObjectId: Hashable, Codable, Sendable, CustomStringConvertible {
    public let bytes: [UInt8] // Always 12 bytes

    public init(bytes: [UInt8]) {
        if bytes.count == 12 {
            self.bytes = bytes
        } else {
            var padded = Array(bytes.prefix(12))
            while padded.count < 12 { padded.append(0) }
            self.bytes = padded
        }
    }

    public init?(hex: String) {
        let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count == 24 else { return nil }
        var result: [UInt8] = []
        result.reserveCapacity(12)
        var index = clean.startIndex
        for _ in 0..<12 {
            let nextIndex = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<nextIndex], radix: 16) else { return nil }
            result.append(byte)
            index = nextIndex
        }
        self.bytes = result
    }

    public static func generate() -> BSONObjectId {
        var result: [UInt8] = []
        let timestamp = UInt32(Date().timeIntervalSince1970).bigEndian
        withUnsafeBytes(of: timestamp) { result.append(contentsOf: $0) }
        for _ in 0..<8 {
            result.append(UInt8.random(in: 0...255))
        }
        return BSONObjectId(bytes: result)
    }

    public var hexString: String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    public var description: String {
        "ObjectId(\"\(hexString)\")"
    }
}

// MARK: - Ordered BSON Document
public struct BSONElement: Equatable, Hashable, Sendable {
    public var key: String
    public var value: BSONValue

    public init(key: String, value: BSONValue) {
        self.key = key
        self.value = value
    }
}

public struct BSONDocument: Equatable, Hashable, Sendable, ExpressibleByDictionaryLiteral {
    public var elements: [BSONElement]

    public init(elements: [BSONElement] = []) {
        self.elements = elements
    }

    public init(dictionaryLiteral elements: (String, BSONValue)...) {
        self.elements = elements.map { BSONElement(key: $0.0, value: $0.1) }
    }

    public subscript(key: String) -> BSONValue? {
        get {
            elements.first(where: { $0.key == key })?.value
        }
        set {
            if let idx = elements.firstIndex(where: { $0.key == key }) {
                if let newValue = newValue {
                    elements[idx].value = newValue
                } else {
                    elements.remove(at: idx)
                }
            } else if let newValue = newValue {
                elements.append(BSONElement(key: key, value: newValue))
            }
        }
    }

    /// Access nested dot-path value (e.g. "address.city")
    public func value(atPath path: String) -> BSONValue? {
        if let direct = self[path] {
            return direct
        }
        let parts = path.split(separator: ".").map(String.init)
        guard parts.count > 1 else { return self[path] }
        var current: BSONValue = .document(self)
        for part in parts {
            switch current {
            case .document(let doc):
                guard let next = doc[part] else { return nil }
                current = next
            default:
                return nil
            }
        }
        return current
    }

    public var keys: [String] {
        elements.map(\.key)
    }

    public var isEmpty: Bool {
        elements.isEmpty
    }

    public var count: Int {
        elements.count
    }
}

// MARK: - BSON Value Enum
public indirect enum BSONValue: Equatable, Hashable, Sendable {
    case double(Double)
    case string(String)
    case document(BSONDocument)
    case array([BSONValue])
    case binary(subtype: UInt8, data: Data)
    case objectId(BSONObjectId)
    case bool(Bool)
    case dateTime(Date)
    case null
    case regex(pattern: String, options: String)
    case int32(Int32)
    case timestamp(UInt64)
    case int64(Int64)
    case decimal128(Data) // 16-byte IEEE 754-2008 decimal
    case minKey
    case maxKey
    case undefined

    public var typeLabel: String {
        switch self {
        case .double: return "Double"
        case .string: return "String"
        case .document: return "Object"
        case .array: return "Array"
        case .binary(let sub, _): return sub == 4 ? "UUID" : "Binary"
        case .objectId: return "ObjectId"
        case .bool: return "Boolean"
        case .dateTime: return "Date"
        case .null: return "Null"
        case .regex: return "Regex"
        case .int32: return "Int32"
        case .timestamp: return "Timestamp"
        case .int64: return "Int64"
        case .decimal128: return "Decimal128"
        case .minKey: return "MinKey"
        case .maxKey: return "MaxKey"
        case .undefined: return "Undefined"
        }
    }

    public var intValue: Int? {
        switch self {
        case .int32(let v): return Int(v)
        case .int64(let v): return Int(v)
        case .double(let v): return Int(v)
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .double(let v): return v
        case .int32(let v): return Double(v)
        case .int64(let v): return Double(v)
        default: return nil
        }
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var documentValue: BSONDocument? {
        if case .document(let d) = self { return d }
        return nil
    }

    public var arrayValue: [BSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        if let i = intValue { return i != 0 }
        return nil
    }

    /// Short display text for Table View cells
    public var displayCellText: String {
        switch self {
        case .double(let d):
            if d.isNaN { return "NaN" }
            if d.isInfinite { return d > 0 ? "Infinity" : "-Infinity" }
            if d.truncatingRemainder(dividingBy: 1) == 0 && abs(d) < 1e15 {
                return String(format: "%.1f", d)
            }
            return String(d)
        case .string(let s):
            return s
        case .document(let doc):
            return "{ \(doc.count) \(doc.count == 1 ? "field" : "fields") }"
        case .array(let arr):
            return "[ \(arr.count) \(arr.count == 1 ? "elem" : "elems") ]"
        case .binary(let subtype, let data):
            if subtype == 4, data.count == 16 {
                let uuid = data.withUnsafeBytes { ptr -> UUID in
                    let bytes = ptr.bindMemory(to: UInt8.self)
                    return UUID(uuid: (
                        bytes[0], bytes[1], bytes[2], bytes[3],
                        bytes[4], bytes[5], bytes[6], bytes[7],
                        bytes[8], bytes[9], bytes[10], bytes[11],
                        bytes[12], bytes[13], bytes[14], bytes[15]
                    ))
                }
                return "UUID(\"\(uuid.uuidString.lowercased())\")"
            }
            return "BinData(\(subtype), \(data.count)B)"
        case .objectId(let oid):
            return "ObjectId(\"\(oid.hexString)\")"
        case .bool(let b):
            return b ? "true" : "false"
        case .dateTime(let date):
            return Self.formatISODate(date)
        case .null:
            return "null"
        case .regex(let pattern, let options):
            return "/\(pattern)/\(options)"
        case .int32(let i):
            return String(i)
        case .timestamp(let ts):
            let t = UInt32(ts >> 32)
            let inc = UInt32(ts & 0xFFFFFFFF)
            return "Timestamp(\(t), \(inc))"
        case .int64(let i):
            return String(i)
        case .decimal128(let data):
            return BSONDecimal128.decodeToString(data)
        case .minKey:
            return "MinKey"
        case .maxKey:
            return "MaxKey"
        case .undefined:
            return "undefined"
        }
    }

    private static let isoLock = NSLock()
    private static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoFormatterWholeSeconds: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func formatISODate(_ date: Date) -> String {
        isoLock.lock()
        defer { isoLock.unlock() }
        return isoFormatterWithFractional.string(from: date)
    }

    public static func parseISODate(_ string: String) -> Date? {
        isoLock.lock()
        defer { isoLock.unlock() }
        return isoFormatterWithFractional.date(from: string) ?? isoFormatterWholeSeconds.date(from: string)
    }
}

// MARK: - Binary BSON Encoder & Decoder
public enum BSONError: LocalizedError {
    case invalidDocumentSize
    case unexpectedEOF
    case invalidUTF8String
    case unsupportedBSONType(UInt8)
    case malformedDocument(String)

    public var errorDescription: String? {
        switch self {
        case .invalidDocumentSize: return "Invalid BSON document size."
        case .unexpectedEOF: return "Unexpected end of BSON data."
        case .invalidUTF8String: return "Invalid UTF-8 string in BSON."
        case .unsupportedBSONType(let t): return String(format: "Unsupported BSON type: 0x%02X", t)
        case .malformedDocument(let msg): return "Malformed BSON document: \(msg)"
        }
    }
}

public struct BSONCoder {
    // MARK: Encode BSONDocument -> Data
    public static func encode(_ document: BSONDocument) -> Data {
        var body = Data()
        for element in document.elements {
            encodeElement(key: element.key, value: element.value, into: &body)
        }
        body.append(0x00) // Trailing document null terminator

        let totalLength = Int32(body.count + 4).littleEndian
        var result = Data(capacity: Int(totalLength))
        withUnsafeBytes(of: totalLength) { result.append(contentsOf: $0) }
        result.append(body)
        return result
    }

    private static func encodeCString(_ str: String, into data: inout Data) {
        if let utf8 = str.data(using: .utf8) {
            data.append(utf8)
        }
        data.append(0x00)
    }

    private static func encodeString(_ str: String, into data: inout Data) {
        let utf8 = str.data(using: .utf8) ?? Data()
        let len = Int32(utf8.count + 1).littleEndian
        withUnsafeBytes(of: len) { data.append(contentsOf: $0) }
        data.append(utf8)
        data.append(0x00)
    }

    private static func encodeElement(key: String, value: BSONValue, into data: inout Data) {
        switch value {
        case .double(let d):
            data.append(0x01)
            encodeCString(key, into: &data)
            let bits = d.bitPattern.littleEndian
            withUnsafeBytes(of: bits) { data.append(contentsOf: $0) }

        case .string(let s):
            data.append(0x02)
            encodeCString(key, into: &data)
            encodeString(s, into: &data)

        case .document(let doc):
            data.append(0x03)
            encodeCString(key, into: &data)
            data.append(encode(doc))

        case .array(let arr):
            data.append(0x04)
            encodeCString(key, into: &data)
            var arrayElements: [BSONElement] = []
            arrayElements.reserveCapacity(arr.count)
            for (idx, item) in arr.enumerated() {
                arrayElements.append(BSONElement(key: String(idx), value: item))
            }
            data.append(encode(BSONDocument(elements: arrayElements)))

        case .binary(let subtype, let binData):
            data.append(0x05)
            encodeCString(key, into: &data)
            if subtype == 0x02 {
                // Old binary subtype 2 wraps content with an additional 4-byte inner length prefix
                let outerLen = Int32(binData.count + 4).littleEndian
                let innerLen = Int32(binData.count).littleEndian
                withUnsafeBytes(of: outerLen) { data.append(contentsOf: $0) }
                data.append(subtype)
                withUnsafeBytes(of: innerLen) { data.append(contentsOf: $0) }
                data.append(binData)
            } else {
                let len = Int32(binData.count).littleEndian
                withUnsafeBytes(of: len) { data.append(contentsOf: $0) }
                data.append(subtype)
                data.append(binData)
            }

        case .undefined:
            data.append(0x06)
            encodeCString(key, into: &data)

        case .objectId(let oid):
            data.append(0x07)
            encodeCString(key, into: &data)
            data.append(contentsOf: oid.bytes)

        case .bool(let b):
            data.append(0x08)
            encodeCString(key, into: &data)
            data.append(b ? 0x01 : 0x00)

        case .dateTime(let date):
            data.append(0x09)
            encodeCString(key, into: &data)
            let ms = Int64((date.timeIntervalSince1970 * 1000.0).rounded()).littleEndian
            withUnsafeBytes(of: ms) { data.append(contentsOf: $0) }

        case .null:
            data.append(0x0A)
            encodeCString(key, into: &data)

        case .regex(let pattern, let options):
            data.append(0x0B)
            encodeCString(key, into: &data)
            encodeCString(pattern, into: &data)
            encodeCString(options, into: &data)

        case .int32(let i):
            data.append(0x10)
            encodeCString(key, into: &data)
            let le = i.littleEndian
            withUnsafeBytes(of: le) { data.append(contentsOf: $0) }

        case .timestamp(let ts):
            data.append(0x11)
            encodeCString(key, into: &data)
            let le = ts.littleEndian
            withUnsafeBytes(of: le) { data.append(contentsOf: $0) }

        case .int64(let i):
            data.append(0x12)
            encodeCString(key, into: &data)
            let le = i.littleEndian
            withUnsafeBytes(of: le) { data.append(contentsOf: $0) }

        case .decimal128(let dec):
            data.append(0x13)
            encodeCString(key, into: &data)
            if dec.count == 16 {
                data.append(dec)
            } else {
                data.append(Data(repeating: 0, count: 16))
            }

        case .minKey:
            data.append(0xFF)
            encodeCString(key, into: &data)

        case .maxKey:
            data.append(0x7F)
            encodeCString(key, into: &data)
        }
    }

    // MARK: Decode Data -> BSONDocument
    public static func decode(_ data: Data) throws -> BSONDocument {
        var offset = 0
        let bytes = [UInt8](data)
        return try decodeDocument(from: bytes, offset: &offset, limit: bytes.count)
    }

    public static func decodeDocument(from bytes: [UInt8], offset: inout Int, limit: Int? = nil) throws -> BSONDocument {
        let upperBound = limit ?? bytes.count
        let docLength = Int(try readInt32(bytes, offset: &offset, limit: upperBound))
        let docEnd = offset - 4 + docLength
        guard docLength >= 5, docEnd <= upperBound else {
            throw BSONError.invalidDocumentSize
        }

        var elements: [BSONElement] = []
        while offset < docEnd - 1 {
            let typeByte = bytes[offset]
            offset += 1
            if typeByte == 0x00 {
                break
            }
            let key = try readCString(bytes, offset: &offset, limit: docEnd)
            let value = try decodeValue(type: typeByte, bytes: bytes, offset: &offset, limit: docEnd)
            elements.append(BSONElement(key: key, value: value))
        }

        offset = docEnd
        return BSONDocument(elements: elements)
    }

    private static func decodeValue(type: UInt8, bytes: [UInt8], offset: inout Int, limit: Int) throws -> BSONValue {
        switch type {
        case 0x01: // Double
            let bits = try readUInt64(bytes, offset: &offset, limit: limit)
            return .double(Double(bitPattern: bits))

        case 0x02, 0x0D, 0x0E: // UTF-8 String, JavaScript code, Symbol
            let s = try readLengthPrefixedString(bytes, offset: &offset, limit: limit)
            return .string(s)

        case 0x03: // Embedded Document
            let doc = try decodeDocument(from: bytes, offset: &offset, limit: limit)
            return .document(doc)

        case 0x04: // Array
            let doc = try decodeDocument(from: bytes, offset: &offset, limit: limit)
            return .array(doc.elements.map(\.value))

        case 0x05: // Binary
            let binLen = Int(try readInt32(bytes, offset: &offset, limit: limit))
            guard offset + 1 <= limit else { throw BSONError.unexpectedEOF }
            let subtype = bytes[offset]
            offset += 1
            guard binLen >= 0, offset + binLen <= limit else { throw BSONError.unexpectedEOF }
            if subtype == 0x02 && binLen >= 4 {
                // Old binary subtype 2 has an extra 4-byte inner length
                var innerOffset = offset
                let innerLen = Int(try readInt32(bytes, offset: &innerOffset, limit: offset + binLen))
                guard innerLen >= 0 && innerOffset + innerLen <= offset + binLen else {
                    throw BSONError.malformedDocument("Invalid Binary subtype 2 inner length")
                }
                let slice = Data(bytes[innerOffset..<(innerOffset + innerLen)])
                offset += binLen
                return .binary(subtype: subtype, data: slice)
            }
            let slice = Data(bytes[offset..<(offset + binLen)])
            offset += binLen
            return .binary(subtype: subtype, data: slice)

        case 0x06: // Undefined
            return .undefined

        case 0x07: // ObjectId
            guard offset + 12 <= limit else { throw BSONError.unexpectedEOF }
            let oidBytes = Array(bytes[offset..<(offset + 12)])
            offset += 12
            return .objectId(BSONObjectId(bytes: oidBytes))

        case 0x08: // Boolean
            guard offset + 1 <= limit else { throw BSONError.unexpectedEOF }
            let b = bytes[offset] != 0
            offset += 1
            return .bool(b)

        case 0x09: // UTC DateTime
            let ms = Int64(bitPattern: try readUInt64(bytes, offset: &offset, limit: limit))
            return .dateTime(Date(timeIntervalSince1970: Double(ms) / 1000.0))

        case 0x0A: // Null
            return .null

        case 0x0B: // Regex
            let pattern = try readCString(bytes, offset: &offset, limit: limit)
            let options = try readCString(bytes, offset: &offset, limit: limit)
            return .regex(pattern: pattern, options: options)

        case 0x0C: // DBPointer (deprecated: string + 12 bytes)
            let ref = try readLengthPrefixedString(bytes, offset: &offset, limit: limit)
            guard offset + 12 <= limit else { throw BSONError.unexpectedEOF }
            offset += 12
            return .string("DBPointer(\(ref))")

        case 0x0F: // CodeWithScope
            let totalCodeLen = Int(try readInt32(bytes, offset: &offset, limit: limit))
            guard totalCodeLen >= 4, offset + (totalCodeLen - 4) <= limit else {
                throw BSONError.unexpectedEOF
            }
            offset += (totalCodeLen - 4)
            return .string("[CodeWithScope]")

        case 0x10: // Int32
            let v = try readInt32(bytes, offset: &offset, limit: limit)
            return .int32(v)

        case 0x11: // Timestamp
            let ts = try readUInt64(bytes, offset: &offset, limit: limit)
            return .timestamp(ts)

        case 0x12: // Int64
            let v = Int64(bitPattern: try readUInt64(bytes, offset: &offset, limit: limit))
            return .int64(v)

        case 0x13: // Decimal128
            guard offset + 16 <= limit else { throw BSONError.unexpectedEOF }
            let d = Data(bytes[offset..<(offset + 16)])
            offset += 16
            return .decimal128(d)

        case 0xFF:
            return .minKey

        case 0x7F:
            return .maxKey

        default:
            throw BSONError.unsupportedBSONType(type)
        }
    }

    private static func readInt32(_ bytes: [UInt8], offset: inout Int, limit: Int) throws -> Int32 {
        guard offset + 4 <= limit else { throw BSONError.unexpectedEOF }
        let b0 = Int32(bytes[offset])
        let b1 = Int32(bytes[offset + 1]) << 8
        let b2 = Int32(bytes[offset + 2]) << 16
        let b3 = Int32(bytes[offset + 3]) << 24
        offset += 4
        return b0 | b1 | b2 | b3
    }

    private static func readUInt64(_ bytes: [UInt8], offset: inout Int, limit: Int) throws -> UInt64 {
        guard offset + 8 <= limit else { throw BSONError.unexpectedEOF }
        var result: UInt64 = 0
        for i in 0..<8 {
            result |= UInt64(bytes[offset + i]) << (i * 8)
        }
        offset += 8
        return result
    }

    private static func readCString(_ bytes: [UInt8], offset: inout Int, limit: Int) throws -> String {
        let start = offset
        while offset < limit && bytes[offset] != 0 {
            offset += 1
        }
        guard offset < limit else { throw BSONError.unexpectedEOF }
        let slice = bytes[start..<offset]
        offset += 1 // skip null terminator
        return String(decoding: slice, as: UTF8.self)
    }

    private static func readLengthPrefixedString(_ bytes: [UInt8], offset: inout Int, limit: Int) throws -> String {
        let len = Int(try readInt32(bytes, offset: &offset, limit: limit))
        guard len >= 1, offset + len <= limit else { throw BSONError.unexpectedEOF }
        let slice = bytes[offset..<(offset + len - 1)]
        offset += len
        return String(decoding: slice, as: UTF8.self)
    }
}

// MARK: - Mongo Shell / Extended JSON Formatter
public struct BSONShellFormatter {
    public static func format(_ document: BSONDocument, indent: Int = 2) -> String {
        formatValue(.document(document), indent: indent, currentLevel: 0)
    }

    private static func formatValue(_ value: BSONValue, indent: Int, currentLevel: Int) -> String {
        let pad = String(repeating: " ", count: currentLevel * indent)
        let childPad = String(repeating: " ", count: (currentLevel + 1) * indent)

        switch value {
        case .document(let doc):
            if doc.isEmpty { return "{}" }
            var lines: [String] = ["{"]
            for (idx, el) in doc.elements.enumerated() {
                let comma = idx < doc.elements.count - 1 ? "," : ""
                let escapedKey = escapeJSONString(el.key)
                let formattedVal = formatValue(el.value, indent: indent, currentLevel: currentLevel + 1)
                lines.append("\(childPad)\"\(escapedKey)\": \(formattedVal)\(comma)")
            }
            lines.append("\(pad)}")
            return lines.joined(separator: "\n")

        case .array(let arr):
            if arr.isEmpty { return "[]" }
            var lines: [String] = ["["]
            for (idx, item) in arr.enumerated() {
                let comma = idx < arr.count - 1 ? "," : ""
                let formattedVal = formatValue(item, indent: indent, currentLevel: currentLevel + 1)
                lines.append("\(childPad)\(formattedVal)\(comma)")
            }
            lines.append("\(pad)]")
            return lines.joined(separator: "\n")

        case .string(let s):
            return "\"\(escapeJSONString(s))\""

        case .objectId(let oid):
            return "ObjectId(\"\(oid.hexString)\")"

        case .dateTime(let date):
            return "ISODate(\"\(BSONValue.formatISODate(date))\")"

        case .bool(let b):
            return b ? "true" : "false"

        case .null:
            return "null"

        case .undefined:
            return "undefined"

        case .int32(let i):
            return String(i)

        case .int64(let i):
            // Quote Int64 so values > 2^53 don't lose precision in JS and Int64 schema type is preserved
            return "NumberLong(\"\(i)\")"

        case .double(let d):
            if d.isNaN { return "NaN" }
            if d.isInfinite { return d > 0 ? "Infinity" : "-Infinity" }
            return String(d)

        case .regex(let pattern, let options):
            if pattern.isEmpty {
                return "new RegExp(\"\", \"\(escapeJSONString(options))\")"
            }
            return "/\(escapeRegexLiteral(pattern))/\(options)"

        case .binary(let subtype, let data):
            if subtype == 4, data.count == 16 {
                let uuid = data.withUnsafeBytes { ptr -> UUID in
                    let b = ptr.bindMemory(to: UInt8.self)
                    return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
                }
                return "UUID(\"\(uuid.uuidString.lowercased())\")"
            }
            return "BinData(\(subtype), \"\(data.base64EncodedString())\")"

        case .timestamp(let ts):
            let t = UInt32(ts >> 32)
            let inc = UInt32(ts & 0xFFFFFFFF)
            return "Timestamp(\(t), \(inc))"

        case .decimal128(let d):
            return "NumberDecimal(\"\(BSONDecimal128.decodeToString(d))\")"

        case .minKey:
            return "MinKey()"

        case .maxKey:
            return "MaxKey()"
        }
    }

    private static func escapeRegexLiteral(_ pattern: String) -> String {
        var out = ""
        out.reserveCapacity(pattern.count)
        var escaped = false
        for ch in pattern {
            if escaped {
                out.append(ch)
                escaped = false
                continue
            }
            if ch == "\\" {
                out.append(ch)
                escaped = true
            } else if ch == "/" {
                out.append("\\/")
            } else if ch == "\n" {
                out.append("\\n")
            } else if ch == "\r" {
                out.append("\\r")
            } else {
                out.append(ch)
            }
        }
        return out
    }

    private static func escapeJSONString(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out
    }
}

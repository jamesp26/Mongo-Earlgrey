import Foundation

/// Exact IEEE 754-2008 Binary Integer Decimal (BID) codec for MongoDB BSON Decimal128 (type 0x13).
public enum BSONDecimal128 {
    private static let exponentBias = 6176
    private static let minExponent = -6176
    private static let maxExponent = 6111
    private static let maxDigits = 34

    // Maximum valid Decimal128 coefficient: 10^34 - 1 = 0x0001_ED09_BEAD_87C0_378D_8E63_FFFF_FFFF
    private static let maxCoeffHi: UInt64 = 0x0001_ED09_BEAD_87C0
    private static let maxCoeffLo: UInt64 = 0x378D_8E63_FFFF_FFFF

    private static let infinityMask: UInt64 = 0x7800_0000_0000_0000
    private static let nanMask: UInt64      = 0x7C00_0000_0000_0000
    private static let specialTest: UInt64  = 0x7C00_0000_0000_0000
    private static let twoBitsMask: UInt64  = 0x6000_0000_0000_0000
    private static let signMask: UInt64     = 0x8000_0000_0000_0000

    public static func decodeToString(_ data: Data) -> String {
        guard data.count == 16 else {
            return "NaN"
        }

        let lo = readUInt64LE(data, offset: 0)
        let hi = readUInt64LE(data, offset: 8)
        let isNegative = (hi & signMask) != 0

        let top5 = hi & specialTest
        if top5 == nanMask {
            return "NaN"
        }
        if top5 == infinityMask {
            return isNegative ? "-Infinity" : "Infinity"
        }

        let biasedExponent: Int
        let coeffHi: UInt64
        let coeffLo: UInt64

        if (hi & twoBitsMask) == twoBitsMask {
            // Non-canonical combination field: implicit significand > 10^34 - 1, so treat coefficient as 0 per IEEE 754-2008.
            biasedExponent = Int((hi >> 47) & 0x3FFF)
            coeffHi = 0
            coeffLo = 0
        } else {
            biasedExponent = Int((hi >> 49) & 0x3FFF)
            let rawHi = hi & 0x0001_FFFF_FFFF_FFFF
            if rawHi > maxCoeffHi || (rawHi == maxCoeffHi && lo > maxCoeffLo) {
                coeffHi = 0
                coeffLo = 0
            } else {
                coeffHi = rawHi
                coeffLo = lo
            }
        }

        let exponent = biasedExponent - exponentBias
        let digits = decimalDigits(hi: coeffHi, lo: coeffLo)
        let signPrefix = isNegative ? "-" : ""
        let adjustedExponent = exponent + digits.count - 1

        // Canonical BSON Decimal128 string formatting rules
        if exponent > 0 || adjustedExponent < -6 {
            var body: String
            if digits.count > 1 {
                let first = digits.prefix(1)
                let rest = digits.dropFirst()
                body = "\(first).\(rest)"
            } else {
                body = digits
            }
            let expSign = adjustedExponent >= 0 ? "+" : ""
            return "\(signPrefix)\(body)E\(expSign)\(adjustedExponent)"
        } else if exponent == 0 {
            return "\(signPrefix)\(digits)"
        } else if adjustedExponent < 0 {
            let leadingZeros = max(0, (-exponent) - digits.count)
            return "\(signPrefix)0.\(String(repeating: "0", count: leadingZeros))\(digits)"
        } else {
            let splitIndex = digits.count + exponent
            let intPart = digits.prefix(splitIndex)
            let fracPart = digits.dropFirst(splitIndex)
            return "\(signPrefix)\(intPart).\(fracPart)"
        }
    }

    public static func encodeFromString(_ rawString: String) -> Data? {
        let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Support legacy 32-char hex representation when letters a-f/A-F are present
        if trimmed.count == 32,
           trimmed.allSatisfy({ $0.isHexDigit }),
           trimmed.contains(where: { ("a"..."f").contains($0) || ("A"..."F").contains($0) }),
           let hexData = dataFromHex(trimmed) {
            return hexData
        }

        var cursor = trimmed[...]
        var isNegative = false
        if let first = cursor.first {
            if first == "-" {
                isNegative = true
                cursor = cursor.dropFirst()
            } else if first == "+" {
                cursor = cursor.dropFirst()
            }
        }
        guard !cursor.isEmpty else { return nil }

        let lower = cursor.lowercased()
        if lower == "nan" {
            return pack(lo: 0, hi: nanMask)
        }
        if lower == "inf" || lower == "infinity" {
            return pack(lo: 0, hi: (isNegative ? signMask : 0) | infinityMask)
        }

        // Split optional exponent marker e / E
        let mantissaSlice: Substring
        var parsedExponent = 0
        if let expIdx = cursor.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            mantissaSlice = cursor[..<expIdx]
            let expStr = cursor[cursor.index(after: expIdx)...]
            guard !expStr.isEmpty, let expVal = Int(expStr) else {
                return nil
            }
            parsedExponent = expVal
        } else {
            mantissaSlice = cursor
        }

        guard !mantissaSlice.isEmpty else { return nil }

        // Parse digits with at most one decimal point
        var seenDot = false
        var significantDigits: [UInt8] = []
        significantDigits.reserveCapacity(40)
        var fractionDigitsCount = 0
        var totalDigitCount = 0

        for ch in mantissaSlice {
            if ch == "." {
                if seenDot { return nil }
                seenDot = true
            } else if let d = ch.asciiValue, d >= 48, d <= 57 {
                totalDigitCount += 1
                if seenDot {
                    fractionDigitsCount += 1
                }
                let digitVal = d - 48
                if !(significantDigits.isEmpty && digitVal == 0) {
                    significantDigits.append(digitVal)
                }
            } else {
                return nil
            }
        }

        guard totalDigitCount > 0 else { return nil }

        var exponent = parsedExponent - fractionDigitsCount

        if significantDigits.isEmpty {
            // Canonical zero preserves clamped exponent if possible
            exponent = min(maxExponent, max(minExponent, exponent))
            let biased = UInt64(exponent + exponentBias)
            let hi = (isNegative ? signMask : 0) | (biased << 49)
            return pack(lo: 0, hi: hi)
        }

        // Trim trailing zeros only if needed to fit within 34 significant digits
        while significantDigits.count > maxDigits, significantDigits.last == 0 {
            significantDigits.removeLast()
            exponent += 1
        }
        guard significantDigits.count <= maxDigits else {
            return nil
        }

        // Clamp high exponents down into trailing coefficient zeros when possible (IEEE 754 BID cohort clamping)
        while exponent > maxExponent && significantDigits.count < maxDigits {
            significantDigits.append(0)
            exponent -= 1
        }

        guard exponent >= minExponent && exponent <= maxExponent else {
            return nil
        }

        // Build 128-bit coefficient using 4 big-endian UInt32 limbs
        var limbs: [UInt32] = [0, 0, 0, 0]
        for digit in significantDigits {
            var carry = UInt64(digit)
            for i in stride(from: 3, through: 0, by: -1) {
                let prod = UInt64(limbs[i]) * 10 + carry
                limbs[i] = UInt32(prod & 0xFFFF_FFFF)
                carry = prod >> 32
            }
        }

        let coeffHi = (UInt64(limbs[0]) << 32) | UInt64(limbs[1])
        let coeffLo = (UInt64(limbs[2]) << 32) | UInt64(limbs[3])
        guard coeffHi <= maxCoeffHi && (coeffHi < maxCoeffHi || coeffLo <= maxCoeffLo) else {
            return nil
        }

        let biased = UInt64(exponent + exponentBias)
        let hi = (isNegative ? signMask : 0) | (biased << 49) | coeffHi
        return pack(lo: coeffLo, hi: hi)
    }

    private static func decimalDigits(hi: UInt64, lo: UInt64) -> String {
        if hi == 0 && lo == 0 {
            return "0"
        }
        var limbs: [UInt32] = [
            UInt32(hi >> 32),
            UInt32(hi & 0xFFFF_FFFF),
            UInt32(lo >> 32),
            UInt32(lo & 0xFFFF_FFFF)
        ]
        var revDigits: [UInt8] = []
        revDigits.reserveCapacity(36)

        while limbs[0] != 0 || limbs[1] != 0 || limbs[2] != 0 || limbs[3] != 0 {
            var rem: UInt64 = 0
            for i in 0..<4 {
                let cur = (rem << 32) | UInt64(limbs[i])
                limbs[i] = UInt32(cur / 10)
                rem = cur % 10
            }
            revDigits.append(UInt8(rem) + 48)
        }

        return String(decoding: revDigits.reversed(), as: UTF8.self)
    }

    private static func pack(lo: UInt64, hi: UInt64) -> Data {
        var data = Data(capacity: 16)
        let loLE = lo.littleEndian
        let hiLE = hi.littleEndian
        withUnsafeBytes(of: loLE) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: hiLE) { data.append(contentsOf: $0) }
        return data
    }

    private static func readUInt64LE(_ data: Data, offset: Int) -> UInt64 {
        var result: UInt64 = 0
        for i in 0..<8 {
            result |= UInt64(data[data.startIndex + offset + i]) << (i * 8)
        }
        return result
    }

    private static func dataFromHex(_ hex: String) -> Data? {
        guard hex.count == 32 else { return nil }
        var result = Data(capacity: 16)
        var idx = hex.startIndex
        for _ in 0..<16 {
            let next = hex.index(idx, offsetBy: 2)
            guard let b = UInt8(hex[idx..<next], radix: 16) else { return nil }
            result.append(b)
            idx = next
        }
        return result
    }
}

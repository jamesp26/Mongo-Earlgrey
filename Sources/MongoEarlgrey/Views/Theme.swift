import SwiftUI
import AppKit

public enum EarlgreyTheme {
    public static func connectionColor(_ name: String) -> Color {
        switch name.lowercased() {
        case "emerald": return Color(red: 0.16, green: 0.78, blue: 0.53)
        case "amber":   return Color(red: 0.95, green: 0.65, blue: 0.18)
        case "blue":    return Color(red: 0.24, green: 0.56, blue: 0.96)
        case "purple":  return Color(red: 0.64, green: 0.42, blue: 0.95)
        case "rose":    return Color(red: 0.94, green: 0.35, blue: 0.48)
        case "teal":    return Color(red: 0.18, green: 0.74, blue: 0.78)
        default:        return Color.accentColor
        }
    }

    public static let colorOptions: [(id: String, label: String)] = [
        ("emerald", "Emerald"),
        ("amber", "Amber"),
        ("blue", "Ocean"),
        ("purple", "Iris"),
        ("rose", "Crimson"),
        ("teal", "Teal")
    ]

    public static func bsonValueColor(_ value: BSONValue) -> Color {
        switch value {
        case .objectId:
            return Color(red: 0.92, green: 0.56, blue: 0.18)
        case .string:
            return Color.primary
        case .int32, .int64, .double, .decimal128:
            return Color(red: 0.25, green: 0.58, blue: 0.96)
        case .bool(let b):
            return b ? Color(red: 0.20, green: 0.75, blue: 0.50) : Color(red: 0.90, green: 0.40, blue: 0.45)
        case .dateTime, .timestamp:
            return Color(red: 0.18, green: 0.70, blue: 0.74)
        case .document:
            return Color(red: 0.62, green: 0.45, blue: 0.92)
        case .array:
            return Color(red: 0.82, green: 0.48, blue: 0.25)
        case .null, .undefined:
            return Color.secondary.opacity(0.65)
        case .regex, .binary, .minKey, .maxKey:
            return Color(red: 0.75, green: 0.42, blue: 0.68)
        }
    }
}

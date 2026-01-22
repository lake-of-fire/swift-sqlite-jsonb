import Foundation

enum SQLiteJSONBConfig {
    static let useDirectBuilder = envBool("SQLITEJSONB_DIRECT_BUILDER", default: true)
    static let useUnsafeUTF8 = envBool("SQLITEJSONB_UNSAFE_UTF8", default: true)
    static let useFastHeader = envBool("SQLITEJSONB_FAST_HEADER", default: true)
    static let useFastIntDecode = envBool("SQLITEJSONB_FAST_INT_DECODE", default: true)
    static let useFastFloatDecode = envBool("SQLITEJSONB_FAST_FLOAT_DECODE", default: true)
    static let useFastStringDecode = envBool("SQLITEJSONB_FAST_STRING_DECODE", default: true)
    static let useSmallObjectLinearSearch = envBool("SQLITEJSONB_SMALL_OBJECT_LINEAR_SEARCH", default: true)
    static let smallObjectLinearSearchThreshold = envInt("SQLITEJSONB_SMALL_OBJECT_LINEAR_SEARCH_THRESHOLD", default: 8)

    private static func envBool(_ key: String, default defaultValue: Bool) -> Bool {
        guard let raw = ProcessInfo.processInfo.environment[key]?.lowercased() else {
            return defaultValue
        }
        switch raw {
            case "1", "true", "yes", "y", "on": return true
            case "0", "false", "no", "n", "off": return false
            default: return defaultValue
        }
    }

    private static func envInt(_ key: String, default defaultValue: Int) -> Int {
        guard let raw = ProcessInfo.processInfo.environment[key],
              let value = Int(raw) else {
            return defaultValue
        }
        return value
    }
}

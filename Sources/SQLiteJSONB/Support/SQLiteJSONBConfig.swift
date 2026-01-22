import Foundation

enum SQLiteJSONBConfig {
    static let useDirectBuilder = envBool("SQLITEJSONB_DIRECT_BUILDER", default: true)
    static let useUnsafeUTF8 = envBool("SQLITEJSONB_UNSAFE_UTF8", default: true)
    static let useFastHeader = envBool("SQLITEJSONB_FAST_HEADER", default: true)
    static let useFastIntDecode = envBool("SQLITEJSONB_FAST_INT_DECODE", default: true)

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
}

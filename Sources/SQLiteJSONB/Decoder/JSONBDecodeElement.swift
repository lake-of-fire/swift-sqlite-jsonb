import Foundation

extension JSONB {
    /// Source bytes sliced (`ArraySlice`) into keyed and unkeyed caches
    enum DecodeElement {
        /// An unparsed JSONB value
        ///
        /// It may be a single value, appropriate for `SingleValueDecodingContainer`, or an
        /// (unkeyed) array or (keyed) object
        case raw(JSONBValue)
        /// `KeyedDecodingContainer` cache
        case keyed(KeyedDecodeElement)
        /// `UnkeyedDecodingContainer` cache
        case unkeyed(UnkeyedDecodeElement)

        init(from value: JSONBValue) { self = .raw(value) }
        init(from data: Data) throws { try self.init(from: JSONBValue(from: data)) }

        init?(from value: JSONBValue?) {
            if let value { self = .raw(value) } else { return nil }
        }

        init?(from data: Data?) throws {
            if let data {
                try self.init(from: JSONBValue(from: data))
            } else {
                return nil
            }
        }

        var type: JSONBType {
            switch self {
                case let .raw(value): value.type
                case .unkeyed: .array
                case .keyed: .object
            }
        }

        func decodeNil() -> Bool {
            if case let .raw(value) = self { return value.type == .null }
            return false
        }

        func decode(for keyPath: CodingKeyPath) throws -> Bool? {
            if case let .raw(jsonb) = self { return try jsonb.decode(for: keyPath) }
            return nil
        }

        func decode(for keyPath: CodingKeyPath) throws -> Data? {
            if case let .raw(jsonb) = self { return try jsonb.decode(for: keyPath) }
            return nil
        }

        func decode(for keyPath: CodingKeyPath) throws -> Date? {
            if case let .raw(jsonb) = self { return try jsonb.decode(for: keyPath) }
            return nil
        }

        func decode(for keyPath: CodingKeyPath) throws -> Float? {
            if case let .raw(jsonb) = self { return try jsonb.decode(for: keyPath) }
            return nil
        }

        func decode(for keyPath: CodingKeyPath) throws -> Double? {
            if case let .raw(jsonb) = self { return try jsonb.decode(for: keyPath) }
            return nil
        }

        func decode(for keyPath: CodingKeyPath) throws -> String? {
            if case let .raw(jsonb) = self { return try jsonb.decode(for: keyPath) }
            return nil
        }

        func decode<T>(for keyPath: CodingKeyPath) throws -> T?
            where T: BinaryInteger & Decodable & LosslessStringConvertible
        {
            if case let .raw(jsonb) = self { return try jsonb.decode(for: keyPath) }
            return nil
        }

        var keyed: KeyedDecodeElement? {
            get throws {
                switch self {
                    case let .keyed(object): object
                    case let .raw(value): try KeyedDecodeElement(from: value)
                    default: nil
                }
            }
        }

        var unkeyed: UnkeyedDecodeElement? {
            get throws {
                switch self {
                    case let .unkeyed(array): array
                    case let .raw(value): try UnkeyedDecodeElement(from: value)
                    default: nil
                }
            }
        }
    }
}

// MARK: - Keyed

extension JSONB {
    /// Cache for `KeyedDecodingContainer` values
    ///
    /// Use of a reference type minimizes allocations
    class KeyedDecodeElement {
        #if DEBUG
        // ordered dictionary when debugging for consistent test expectations
        typealias DecodeValues = OrderedDictionary<String, DecodeElement?>
        #else
        typealias DecodeValues = [String: DecodeElement?]
        #endif
        private enum Storage {
            case linear([(String, DecodeElement?)])
            case dictionary(DecodeValues)
        }
        private var storage: Storage

        var keys: any Sequence<String> {
            switch storage {
                case let .linear(values): values.map(\.0)
                case let .dictionary(values): values.keys
            }
        }
        var count: Int {
            switch storage {
                case let .linear(values): values.count
                case let .dictionary(values): values.count
            }
        }

        subscript(key: String) -> DecodeElement? {
            get {
                switch storage {
                    case let .linear(values):
                        return values.first { $0.0 == key }?.1
                    case let .dictionary(values):
                        return values[key].flatMap(\.self)
                }
            }
            set {
                switch storage {
                    case .linear:
                        var values = materializeDictionary()
                        values[key] = newValue
                        storage = .dictionary(values)
                    case var .dictionary(values):
                        values[key] = newValue
                        storage = .dictionary(values)
                }
            }
        }

        subscript(key: some CodingKey) -> DecodeElement? {
            get {
                self[key.stringValue]
            }
            set {
                self[key.stringValue] = newValue
            }
        }

        init(values: DecodeValues = [:]) {
            self.storage = .dictionary(values)
        }

        init?(from jsonb: JSONBValue) throws {
            if jsonb.type == .object {
                if SQLiteJSONBConfig.useSmallObjectLinearSearch {
                    let threshold = max(1, SQLiteJSONBConfig.smallObjectLinearSearchThreshold)
                    var pairs: [(String, DecodeElement?)] = []
                    var index = jsonb.startIndex
                    while index < jsonb.endIndex - 1 {
                        let key = try JSONBValue(from: jsonb.payload[index...])
                        let value = try JSONBValue(from: jsonb.payload[key.endIndex...])

                        index = value.endIndex
                        let keyString = try key.decode()
                        pairs.append((keyString, DecodeElement(from: value)))
                    }
                    if pairs.count <= threshold {
                        storage = .linear(pairs)
                    } else {
                        var values: DecodeValues = [:]
                        values.reserveCapacity(pairs.count)
                        for (key, value) in pairs {
                            values[key] = value
                        }
                        storage = .dictionary(values)
                    }
                } else {
                    let values = try jsonb.object.mapValues { DecodeElement(from: $0) }
                    storage = .dictionary(values)
                }
            } else {
                return nil
            }
        }

        func contains(_ key: String) -> Bool {
            switch storage {
                case let .linear(values): return values.contains { $0.0 == key }
                case let .dictionary(values): return values.index(forKey: key) != nil
            }
        }
        func contains(_ key: some CodingKey) -> Bool { contains(key.stringValue) }

        func type(for key: String) -> JSONBType? { (try? value(for: key))?.type }
        func type(for key: some CodingKey) -> JSONBType? { type(for: key.stringValue) }

        func decodeNil(_ key: some CodingKey) -> Bool? { (try? value(for: key.stringValue))?.decodeNil() }

        func decode(_ key: some CodingKey, for keyPath: CodingKeyPath) throws -> Bool? {
            try value(for: key.stringValue)?.decode(for: keyPath)
        }

        func decode(_ key: some CodingKey, for keyPath: CodingKeyPath) throws -> Data? {
            try value(for: key.stringValue)?.decode(for: keyPath)
        }

        func decode(_ key: some CodingKey, for keyPath: CodingKeyPath) throws -> Date? {
            try value(for: key.stringValue)?.decode(for: keyPath)
        }

//        func decode(_ key: some CodingKey, for keyPath: CodingKeyPath) throws -> UUID? {
//            try self[key]?.decode(for: keyPath)
//        }

        func decode(_ key: some CodingKey, for keyPath: CodingKeyPath) throws -> Float? {
            try value(for: key.stringValue)?.decode(for: keyPath)
        }

        func decode(_ key: some CodingKey, for keyPath: CodingKeyPath) throws -> Double? {
            try value(for: key.stringValue)?.decode(for: keyPath)
        }

        func decode(_ key: some CodingKey, for keyPath: CodingKeyPath) throws -> String? {
            try value(for: key.stringValue)?.decode(for: keyPath)
        }

        func decode<T>(_ key: some CodingKey, for keyPath: CodingKeyPath) throws -> T?
            where T: BinaryInteger & Decodable & LosslessStringConvertible
        {
            try value(for: key.stringValue)?.decode(for: keyPath)
        }

        func keyed(_ key: some CodingKey) throws -> KeyedDecodeElement? {
            if let value = try value(for: key.stringValue) { try value.keyed } else { nil }
        }

        func unkeyed(_ key: some CodingKey) throws -> UnkeyedDecodeElement? {
            if let value = try value(for: key.stringValue) { try value.unkeyed } else { nil }
        }

        private func value(for key: String) throws -> DecodeElement? {
            switch storage {
                case let .linear(values):
                    return values.first { $0.0 == key }?.1
                case let .dictionary(values):
                    return values[key].flatMap(\.self)
            }
        }

        private func materializeDictionary() -> DecodeValues {
            switch storage {
                case let .dictionary(values): return values
                case let .linear(values):
                    var dict: DecodeValues = [:]
                    dict.reserveCapacity(values.count)
                    for (key, value) in values {
                        dict[key] = value
                    }
                    return dict
            }
        }
    }
}

// MARK: - Unkeyed

extension JSONB {
    /// Cache for `UnkeyedDecodingContainer` values
    ///
    /// Use of a reference type minimizes allocations
    class UnkeyedDecodeElement {
        private var values: [DecodeElement]

        subscript(index: Int) -> DecodeElement {
            get { values[index] }
            set { values[index] = newValue }
        }

        subscript(safe index: Int) -> DecodeElement? {
            values[safe: index]
        }

        var count: Int { values.count }

        init() {
            values = []
            values.reserveCapacity(10)
        }

        init?(from jsonb: JSONBValue) throws {
            if jsonb.type == .array {
                values = try jsonb.array.map { DecodeElement(from: $0) }
                return
            }
            return nil
        }

        func type(for index: Int) -> JSONBType? { (try? element(at: index))?.type }

        func decodeNil(at index: Int) throws -> Bool? { try element(at: index)?.decodeNil() }

        func decode(at index: Int, for keyPath: CodingKeyPath) throws -> Bool? {
            try element(at: index)?.decode(for: keyPath)
        }

        func decode(at index: Int, for keyPath: CodingKeyPath) throws -> Data? {
            try element(at: index)?.decode(for: keyPath)
        }

        func decode(at index: Int, for keyPath: CodingKeyPath) throws -> Date? {
            try element(at: index)?.decode(for: keyPath)
        }

        func decode(at index: Int, for keyPath: CodingKeyPath) throws -> Float? {
            try element(at: index)?.decode(for: keyPath)
        }

        func decode(at index: Int, for keyPath: CodingKeyPath) throws -> Double? {
            try element(at: index)?.decode(for: keyPath)
        }

        func decode(at index: Int, for keyPath: CodingKeyPath) throws -> String? {
            try element(at: index)?.decode(for: keyPath)
        }

        @available(*, unavailable)
        func decode<T>(at _: Int, for _: CodingKeyPath) throws -> T?
            where T: BinaryInteger & Decodable & LosslessStringConvertible
        {
            // if case let .raw(jsonb) = self { return try jsonb.decode(for: keyPath) }
            preconditionFailure("not implemented")
            // return nil
        }

        func keyed(at index: Int) throws -> KeyedDecodeElement? {
            if let value = try element(at: index) { try value.keyed } else { nil }
        }

        func unkeyed(at index: Int) throws -> UnkeyedDecodeElement? {
            if let value = try element(at: index) { try value.unkeyed } else { nil }
        }

        func element(at index: Int) throws -> DecodeElement? {
            values[safe: index]
        }
    }
}

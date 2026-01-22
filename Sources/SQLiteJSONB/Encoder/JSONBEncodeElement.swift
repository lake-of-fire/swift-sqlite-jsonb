import Foundation

private func copyBytes(_ bytes: Bytes, into base: UnsafeMutablePointer<UInt8>, offset: inout Int) {
    let count = bytes.count
    guard count > 0 else { return }
    bytes.withUnsafeBytes { srcRaw in
        guard let srcBase = srcRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
        base.advanced(by: offset).update(from: srcBase, count: count)
    }
    offset += count
}

private func copyStringUTF8(_ value: String, into base: UnsafeMutablePointer<UInt8>, offset: inout Int) {
    if !SQLiteJSONBConfig.useUnsafeUTF8 {
        let bytes = Array(value.utf8)
        copyBytes(bytes, into: base, offset: &offset)
        return
    }

    let count = value.utf8.count
    guard count > 0 else { return }
    var copied = false
    value.utf8.withContiguousStorageIfAvailable { buffer in
        if let srcBase = buffer.baseAddress {
            base.advanced(by: offset).update(from: srcBase, count: buffer.count)
            copied = true
        }
    }
    if copied {
        offset += count
        return
    }
    var index = 0
    for byte in value.utf8 {
        base[offset + index] = byte
        index += 1
    }
    offset += count
}

private func writeHeader(type: JSONBType, payloadSize: Int, into base: UnsafeMutablePointer<UInt8>) -> Int {
    JSONBHeader.write(type: type, payloadSize: payloadSize, into: base)
}

enum JSONB {
    /// Element bytes ready for JSONB encoding (addition of JSONB header)
    enum EncodeElement: ByteExpressible {
        /// `SingleValueEncodingContainer` cache
        case value(Bytes)
        /// `KeyedEncodingContainer` cache
        case keyed(KeyedEncodeElement)
        /// `UnkeyedEncodingContainer` cache
        case unkeyed(UnkeyedEncodeElement)

        var bytes: Bytes {
            switch self {
                case let .value(value): value
                case let .unkeyed(value): value.bytes
                case let .keyed(value): value.bytes
            }
        }

        var byteCount: Int {
            switch self {
                case let .value(value): value.count
                case let .unkeyed(value): value.byteCount
                case let .keyed(value): value.byteCount
            }
        }

        /// Empty keyed element
        ///
        /// This is used as a safe fallback when a nested decoder has no result
        static func emptyKeyedElement() -> Self { .keyed(KeyedEncodeElement()) }

        func copy() -> Self {
            switch self {
                case let .value(bytes): return .value(bytes)
                case let .keyed(keyed): return .keyed(keyed)
                case let .unkeyed(unkeyed): return .unkeyed(unkeyed)
            }
        }
    }
}

// MARK: - Keyed

extension JSONB {
    /// Cache for `KeyedEncodingContainer` values
    ///
    /// Use of a reference type minimizes allocations
    class KeyedEncodeElement: ByteExpressible {
        private var values: [String: EncodeElement] = [:]

        init() {
            values.reserveCapacity(8)
        }

        subscript(key: String) -> EncodeElement? {
            get { values[key] }
            set { values[key] = newValue }
        }

        subscript(key: some CodingKey) -> EncodeElement? {
            get { values[key.stringValue] }
            set { values[key.stringValue] = newValue }
        }

        func append(_ value: Bytes, for key: some CodingKey) { self[key] = .value(value) }

        func appendNil(for key: some CodingKey) {
            append(JSONBValue.encodeNil(), for: key)
        }

        func append(_ value: Bool, for key: some CodingKey) {
            append(JSONBValue.encode(value), for: key)
        }

        func append(_ value: Data, for key: some CodingKey) {
            append(JSONBValue.encode(value), for: key)
        }

        func append(_ value: Date, for key: some CodingKey) {
            append(JSONBValue.encode(value), for: key)
        }

        func append(_ value: Float, for key: some CodingKey) {
            append(JSONBValue.encode(value), for: key)
        }

        func append(_ value: Double, for key: some CodingKey) {
            append(JSONBValue.encode(value), for: key)
        }

        func append(_ value: String, for key: some CodingKey) {
            append(JSONBValue.encode(value), for: key)
        }

        func append(_ value: some (BinaryInteger & Encodable), for key: some CodingKey) {
            append(JSONBValue.encode(value), for: key)
        }

        /// Retrieve keyed element at given key or create a new keyed element at the key
        ///
        /// Execution halts if there is already an *unkeyed* element at the key. An error is not
        /// thrown since this is used by encoding container methods that are not throwing.
        func keyed(for key: String) -> KeyedEncodeElement {
            switch values[key] {
                case let .keyed(value):
                    return value
                case .unkeyed:
                    preconditionFailure("Unkeyed container already created for \"\(key)\"")
                case .none, .value:
                    let value = KeyedEncodeElement()
                    values[key] = .keyed(value)
                    return value
            }
        }

        func keyed(for key: some CodingKey) -> KeyedEncodeElement {
            keyed(for: key.stringValue)
        }

        /// Retrieve unkeyed element at given key or create a new unkeyed element at the key
        ///
        /// Execution halts if there is already a *keyed* element at the key. An error is not thrown
        /// since this is used by encoding container methods that are not throwing.
        func unkeyed(for key: String) -> UnkeyedEncodeElement {
            switch values[key] {
                case let .unkeyed(value):
                    return value
                case .keyed:
                    preconditionFailure("Keyed container already created for \"\(key)\"")
                case .none, .value:
                    let value = UnkeyedEncodeElement()
                    values[key] = .unkeyed(value)
                    return value
            }
        }

        func unkeyed(for key: some CodingKey) -> UnkeyedEncodeElement {
            unkeyed(for: key.stringValue)
        }

        /// Encode values as a JSONB ``JSONBType/object``
        ///
        /// The values themselves must already be encoded (have a [JSONB header][1])
        ///
        /// [1]: https://sqlite.org/jsonb.html#payload_size
        var bytes: Bytes {
            if !SQLiteJSONBConfig.useDirectBuilder {
                var result = Bytes()
                #if DEBUG
                for key in values.keys.sorted() {
                    result.append(contentsOf: JSONBValue.encode(.text, with: key.bytes))
                    if let value = values[key] {
                        result.append(contentsOf: value.bytes)
                    }
                }
                #else
                for (key, element) in values {
                    result.append(contentsOf: JSONBValue.encode(.text, with: key.bytes))
                    result.append(contentsOf: element.bytes)
                }
                #endif
                return JSONBValue.encode(.object, with: result)
            }

            var payloadSize = 0
            #if DEBUG
            for key in values.keys {
                let keySize = key.utf8.count
                payloadSize += JSONBValue.headerSize(for: keySize) + keySize
                payloadSize += values[key]?.byteCount ?? 0
            }
            #else
            for (key, element) in values {
                let keySize = key.utf8.count
                payloadSize += JSONBValue.headerSize(for: keySize) + keySize
                payloadSize += element.byteCount
            }
            #endif

            let headerSize = JSONBValue.headerSize(for: payloadSize)
            var result = Bytes(repeating: 0, count: headerSize + payloadSize)

            result.withUnsafeMutableBytes { destRaw in
                guard let base = destRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return
                }
                var offset = writeHeader(type: .object, payloadSize: payloadSize, into: base)

                #if DEBUG
                // sort keys when debugging for consistent test expectations
                for key in values.keys.sorted() {
                    let keySize = key.utf8.count
                    let keyHeader = writeHeader(type: .text, payloadSize: keySize, into: base.advanced(by: offset))
                    offset += keyHeader
                    copyStringUTF8(key, into: base, offset: &offset)
                    if let value = values[key] {
                        let valueBytes = value.bytes
                        copyBytes(valueBytes, into: base, offset: &offset)
                    }
                }
                #else
                for (key, element) in values {
                    let keySize = key.utf8.count
                    let keyHeader = writeHeader(type: .text, payloadSize: keySize, into: base.advanced(by: offset))
                    offset += keyHeader
                    copyStringUTF8(key, into: base, offset: &offset)
                    let valueBytes = element.bytes
                    copyBytes(valueBytes, into: base, offset: &offset)
                }
                #endif
            }

            return result
        }

        var byteCount: Int {
            var payloadSize = 0
            for (key, element) in values {
                payloadSize += JSONBValue.headerSize(for: key.utf8.count) + key.utf8.count
                payloadSize += element.byteCount
            }
            return JSONBValue.headerSize(for: payloadSize) + payloadSize
        }
    }
}

// MARK: - Unkeyed

extension JSONB {
    /// Cache for `UnkeyedEncodingContainer` values
    ///
    /// Use of a reference type minimizes allocations
    class UnkeyedEncodeElement: ByteExpressible {
        private var values: [EncodeElement] = []

        subscript(index: Int) -> EncodeElement {
            get { values[index] }
            set { values[index] = newValue }
        }

        var count: Int { values.count }

        init() {
            values.reserveCapacity(10)
        }

        /// Append single value bytes to the array
        func append(_ value: Bytes) { values.append(.value(value)) }

        func appendNil() { append(JSONBValue.encodeNil()) }

        func append(_ value: Bool) { append(JSONBValue.encode(value)) }
        func append(_ value: Data) { append(JSONBValue.encode(value)) }
        func append(_ value: Date) { append(JSONBValue.encode(value)) }
        func append(_ value: Float) { append(JSONBValue.encode(value)) }
        func append(_ value: Double) { append(JSONBValue.encode(value)) }
        func append(_ value: String) { append(JSONBValue.encode(value)) }
        func append(_ value: some (BinaryInteger & Encodable)) { append(JSONBValue.encode(value)) }

        /// Create a nested array cache appended to the array
        var appendedUnkeyed: UnkeyedEncodeElement {
            let value = UnkeyedEncodeElement()
            values.append(.unkeyed(value))
            return value
        }

        /// Create an object cache appended to the array
        var appendedKeyed: KeyedEncodeElement {
            let value = KeyedEncodeElement()
            values.append(.keyed(value))
            return value
        }

        func insert(_ value: EncodeElement, at index: Int) { values.insert(value, at: index)
        }

        /// Encode values as a JSONB ``JSONBType/array``
        ///
        /// The values themselves must already be encoded (have a [JSONB header][1])
        ///
        /// [1]: https://sqlite.org/jsonb.html#payload_size
        var bytes: Bytes {
            if !SQLiteJSONBConfig.useDirectBuilder {
                return JSONBValue.encode(.array, with: values.reduce(into: []) { bytes, element in
                    bytes += element.bytes
                })
            }

            var payloadSize = 0
            for element in values {
                payloadSize += element.byteCount
            }

            let headerSize = JSONBValue.headerSize(for: payloadSize)
            var result = Bytes(repeating: 0, count: headerSize + payloadSize)

            result.withUnsafeMutableBytes { destRaw in
                guard let base = destRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return
                }
                var offset = writeHeader(type: .array, payloadSize: payloadSize, into: base)
                for element in values {
                    let elementBytes = element.bytes
                    copyBytes(elementBytes, into: base, offset: &offset)
                }
            }

            return result
        }

        var byteCount: Int {
            var payloadSize = 0
            for element in values {
                payloadSize += element.byteCount
            }
            return JSONBValue.headerSize(for: payloadSize) + payloadSize
        }
    }
}

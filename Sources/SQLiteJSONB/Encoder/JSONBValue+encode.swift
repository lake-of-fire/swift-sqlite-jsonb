import Foundation

extension JSONBValue {
    /// Size in bytes of the JSONB header for the given payload size.
    static func headerSize(for payloadSize: Int) -> Int {
        JSONBHeader.size(for: payloadSize)
    }

    /// Add standard SQLite [JSONB header][1] to the payload
    ///
    /// ![Bytes](JSONB+Format.pdf)
    ///
    /// [1]: https://sqlite.org/jsonb.html#payload_size
    static func encode(_ type: JSONBType, with payload: Bytes) -> Bytes {
        let payloadSize = payload.count
        let headerSize = headerSize(for: payloadSize)
        var result = Bytes(repeating: 0, count: headerSize + payloadSize)

        result.withUnsafeMutableBytes { destRaw in
            guard let baseAddress = destRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }

            let written = JSONBHeader.write(type: type, payloadSize: payloadSize, into: baseAddress)
            if payloadSize > 0 {
                payload.withUnsafeBytes { srcRaw in
                    guard let srcBase = srcRaw.baseAddress else { return }
                    let dest = baseAddress.advanced(by: written)
                    let src = srcBase.assumingMemoryBound(to: UInt8.self)
                    dest.update(from: src, count: payloadSize)
                }
            }
        }

        return result
    }

    /// Add standard SQLite JSONB header to the payload
    private static func encode(_ type: JSONBType, with payload: some ByteExpressible) -> Bytes {
        encode(type, with: payload.bytes)
    }

    /// Encode integer bytes
    ///
    /// The JSONB specification stores the *display* value of numbers rather than raw bytes
    /// constituting the number.
    ///
    /// For example, the number `1` is stored as `0x31` (the ASCII value for the character `1`)
    /// rather than `0x01` (the raw byte value for the number `1`).
    static func encode(_ value: some BinaryInteger) -> Bytes {
        encode(.integer, with: String(value))
    }

    /// Encode floating point number
    ///
    /// If the number is actually an integer (has no decimals) then encode it as such. This is not
    /// explicitly [documented][1] except, perhaps, in the statement that the "shortest encoding
    /// is preferred." Tests, however, show this is the SQLite behavior.
    ///
    /// [1]: https://sqlite.org/jsonb.html#payload_size
    static func encode(_ value: Float) -> Bytes {
        if let number = Int(exactly: value) {
            encode(number)
        } else {
            encode(.float, with: String(value))
        }
    }

    /// Encode double value as floating point number
    ///
    /// If the number is actually an integer (has no decimals) then encode it as such. This is not
    /// explicitly [documented][1] except, perhaps, in the statement that the "shortest encoding
    /// is preferred." Tests, however, show this is the SQLite behavior.
    ///
    /// [1]: https://sqlite.org/jsonb.html#payload_size
    static func encode(_ value: Double) -> Bytes {
        if let number = Int(exactly: value) {
            encode(number)
        } else {
            encode(.float, with: String(value))
        }
    }

    static func encode(_ value: String) -> Bytes {
        if !SQLiteJSONBConfig.useUnsafeUTF8 {
            return encode(.text, with: value)
        }

        let payloadSize = value.utf8.count
        let headerLen = headerSize(for: payloadSize)
        var result = Bytes(repeating: 0, count: headerLen + payloadSize)

        result.withUnsafeMutableBytes { destRaw in
            guard let baseAddress = destRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }

            let written = JSONBHeader.write(type: .text, payloadSize: payloadSize, into: baseAddress)
            if payloadSize == 0 { return }

            var index = 0
            for byte in value.utf8 {
                baseAddress[written + index] = byte
                index += 1
            }
        }

        return result
    }

    /// Encode date as an [ISO 8601][1] string
    ///
    /// Dates are encoded as strings rather than timestamps to ensure accuracy and improve
    /// readability
    ///
    /// ## References
    /// - [GRDB discussion][2]
    ///
    /// [1]: https://www.iso.org/iso-8601-date-and-time-format.html
    /// [2]: https://github.com/groue/GRDB.swift/issues/492
    static func encode(_ value: Date) -> Bytes { encode(value.ISO8601Format()) }

    static func encode(_ value: Data) -> Bytes { encode(value.base64EncodedString()) }

    static func encode(_ value: Bool) -> Bytes {
        value ? [JSONBType.true.rawValue] : [JSONBType.false.rawValue]
    }

    /// Encode UUID
    ///
    /// SQLite database triggers use [JSON][1] functions to retrieve these values and the [hex][2]
    /// function to parse them as `BLOB`s that may be matched to primary keys. Encoding this way
    /// is required for that usage.
    ///
    /// [1]: https://www.sqlite.org/json1.html
    /// [2]: https://www.sqlite.org/lang_corefunc.html#hex
//    static func encode(_ value: UUID) -> Bytes { encode(value.hexString) }

    static func encode<T: RawRepresentable>(_ value: T) -> Bytes where T.RawValue == String {
        encode(value.rawValue)
    }

    static func encode<T: RawRepresentable>(_ value: T) -> Bytes where T.RawValue: BinaryInteger {
        encode(value.rawValue)
    }

    static func encode(_ value: some CodingKey) -> Bytes { encode(value.stringValue) }

    static func encodeNil() -> Bytes { [JSONBType.null.rawValue] }
}

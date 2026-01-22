import Foundation

enum JSONBHeader {
    static func size(for payloadSize: Int) -> Int {
        if payloadSize <= 11 { return 1 }
        if payloadSize <= 0xFF { return 2 }
        if payloadSize <= 0xFFFF { return 3 }
        if payloadSize <= 0xFFFF_FFFF { return 5 }
        return 9
    }

    static func write(
        type: JSONBType,
        payloadSize: Int,
        into base: UnsafeMutablePointer<UInt8>
    ) -> Int {
        if SQLiteJSONBConfig.useFastHeader {
            return writeFast(type: type, payloadSize: payloadSize, into: base)
        }
        return writeSlow(type: type, payloadSize: payloadSize, into: base)
    }

    @inline(__always)
    private static func writeFast(
        type: JSONBType,
        payloadSize: Int,
        into base: UnsafeMutablePointer<UInt8>
    ) -> Int {
        if payloadSize <= 11 {
            base[0] = type.rawValue | (UInt8(payloadSize) << 4)
            return 1
        }
        if payloadSize <= 0xFF {
            base[0] = type.rawValue | 0xC0
            base[1] = UInt8(payloadSize & 0xFF)
            return 2
        }
        if payloadSize <= 0xFFFF {
            base[0] = type.rawValue | 0xD0
            base[1] = UInt8((payloadSize >> 8) & 0xFF)
            base[2] = UInt8(payloadSize & 0xFF)
            return 3
        }
        if payloadSize <= 0xFFFF_FFFF {
            base[0] = type.rawValue | 0xE0
            base[1] = UInt8((payloadSize >> 24) & 0xFF)
            base[2] = UInt8((payloadSize >> 16) & 0xFF)
            base[3] = UInt8((payloadSize >> 8) & 0xFF)
            base[4] = UInt8(payloadSize & 0xFF)
            return 5
        }

        let size64 = UInt64(payloadSize)
        base[0] = type.rawValue | 0xF0
        base[1] = UInt8((size64 >> 56) & 0xFF)
        base[2] = UInt8((size64 >> 48) & 0xFF)
        base[3] = UInt8((size64 >> 40) & 0xFF)
        base[4] = UInt8((size64 >> 32) & 0xFF)
        base[5] = UInt8((size64 >> 24) & 0xFF)
        base[6] = UInt8((size64 >> 16) & 0xFF)
        base[7] = UInt8((size64 >> 8) & 0xFF)
        base[8] = UInt8(size64 & 0xFF)
        return 9
    }

    private static func writeSlow(
        type: JSONBType,
        payloadSize: Int,
        into base: UnsafeMutablePointer<UInt8>
    ) -> Int {
        var firstByte = type.rawValue
        let sizeBytes: Bytes

        if payloadSize <= 11 {
            firstByte |= (UInt8(payloadSize) << 4)
            sizeBytes = []
        } else if payloadSize <= 0xFF {
            firstByte |= 0xC0
            sizeBytes = UInt8(payloadSize).bigEndian.bytes
        } else if payloadSize <= 0xFFFF {
            firstByte |= 0xD0
            sizeBytes = UInt16(payloadSize).bigEndian.bytes
        } else if payloadSize <= 0xFFFF_FFFF {
            firstByte |= 0xE0
            sizeBytes = UInt32(payloadSize).bigEndian.bytes
        } else {
            firstByte |= 0xF0
            sizeBytes = payloadSize.bigEndian.bytes
        }

        base[0] = firstByte
        if !sizeBytes.isEmpty {
            sizeBytes.withUnsafeBytes { raw in
                if let srcBase = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) {
                    base.advanced(by: 1).update(from: srcBase, count: sizeBytes.count)
                }
            }
        }
        return 1 + sizeBytes.count
    }
}

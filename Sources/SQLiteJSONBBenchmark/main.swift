import Foundation
import SQLiteJSONB

private struct Item: Codable, Equatable {
    let id: Int
    let name: String
    let tags: [String]
    let scores: [Double]
    let metadata: [String: String]
    let active: Bool
}

private struct Payload: Codable, Equatable {
    let items: [Item]
    let createdAt: Date
    let title: String
}

private enum ArgKey: String {
    case iterations
    case rows
    case warmup
}

private func parseArgs() -> [ArgKey: Int] {
    var result: [ArgKey: Int] = [:]
    var index = 1
    while index < CommandLine.arguments.count {
        let arg = CommandLine.arguments[index]
        if arg.hasPrefix("--"), let key = ArgKey(rawValue: String(arg.dropFirst(2))) {
            let valueIndex = index + 1
            if valueIndex < CommandLine.arguments.count,
               let value = Int(CommandLine.arguments[valueIndex]) {
                result[key] = value
                index += 2
                continue
            }
        }
        index += 1
    }
    return result
}

private func makePayload(rows: Int) -> Payload {
    let tags = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf"]
    let metadata = [
        "source": "benchmark",
        "owner": "swift-sqlite-jsonb",
        "region": "us-west",
        "tier": "gold",
    ]

    var items: [Item] = []
    items.reserveCapacity(rows)
    for index in 0..<rows {
        let item = Item(
            id: index,
            name: "Item-\(index)",
            tags: [tags[index % tags.count], tags[(index + 2) % tags.count]],
            scores: [Double(index) * 0.25, Double(index % 7) * 1.75, Double(index % 3)],
            metadata: metadata,
            active: index % 2 == 0
        )
        items.append(item)
    }

    return Payload(
        items: items,
        createdAt: Date(timeIntervalSince1970: 1_694_630_400),
        title: "Swift SQLite JSONB Benchmark"
    )
}

@inline(never)
private func blackhole(_ value: Int) {
    _ = value ^ 0x9E3779B9
}

@inline(never)
private func blackhole(_ value: Data) {
    blackhole(value.count)
}

@inline(never)
private func blackhole<T>(_ value: T) {
    withUnsafeBytes(of: value) { buffer in
        if let byte = buffer.first {
            blackhole(Int(byte))
        }
    }
}

private func measure(name: String, iterations: Int, warmup: Int, _ block: () throws -> Void) rethrows {
    for _ in 0..<warmup { try block() }

    let clock = ContinuousClock()
    let start = clock.now
    for _ in 0..<iterations { try block() }
    let duration = start.duration(to: clock.now)

    let totalSeconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
    let perOp = (totalSeconds / Double(iterations)) * 1_000_000

    print(String(format: "%@ - total: %.3fs | avg: %.2fµs", name, totalSeconds, perOp))
}

private func envBool(_ key: String, default defaultValue: Bool) -> Bool {
    guard let raw = ProcessInfo.processInfo.environment[key]?.lowercased() else {
        return defaultValue
    }
    switch raw {
        case "1", "true", "yes", "y", "on": return true
        case "0", "false", "no", "n", "off": return false
        default: return defaultValue
    }
}

@main
struct SQLiteJSONBBenchmark {
    static func main() throws {
        let args = parseArgs()
        let iterations = args[.iterations] ?? 200
        let rows = args[.rows] ?? 1_000
        let warmup = args[.warmup] ?? 20

        let direct = envBool("SQLITEJSONB_DIRECT_BUILDER", default: true)
        let unsafeUTF8 = envBool("SQLITEJSONB_UNSAFE_UTF8", default: true)
        let fastHeader = envBool("SQLITEJSONB_FAST_HEADER", default: true)
        let fastIntDecode = envBool("SQLITEJSONB_FAST_INT_DECODE", default: true)
        let fastFloatDecode = envBool("SQLITEJSONB_FAST_FLOAT_DECODE", default: false)

        let payload = makePayload(rows: rows)
        let encoded = try JSONBEncoder.encode(payload)

        print("SQLiteJSONB benchmark")
        print("rows=\(rows) iterations=\(iterations) warmup=\(warmup) payload=\(encoded.count) bytes")
        print("flags: direct=\(direct) unsafeUtf8=\(unsafeUTF8) fastHeader=\(fastHeader) fastIntDecode=\(fastIntDecode) fastFloatDecode=\(fastFloatDecode)")

        try measure(name: "encode", iterations: iterations, warmup: warmup) {
            let data = try JSONBEncoder.encode(payload)
            blackhole(data)
        }

        try measure(name: "decode", iterations: iterations, warmup: warmup) {
            let decoded: Payload = try JSONBDecoder.decode(encoded)
            blackhole(decoded.items.count)
        }

        // JSONBValue initializer is internal; decode benchmark already includes parsing.
    }
}

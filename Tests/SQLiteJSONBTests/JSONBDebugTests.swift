import Foundation
@testable import SQLiteJSONB
import Testing

struct JSONBDebugTests {
    @Test func debugPayloadKeys() throws {
        struct Item: Codable, Equatable {
            let id: Int
            let name: String
            let tags: [String]
            let scores: [Double]
            let metadata: [String: String]
            let active: Bool
        }

        struct Payload: Codable, Equatable {
            let items: [Item]
            let createdAt: Date
            let title: String
        }

        let tags = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf"]
        let metadata = [
            "source": "benchmark",
            "owner": "swift-sqlite-jsonb",
            "region": "us-west",
            "tier": "gold",
        ]

        let rowCount = 1000
        var items: [Item] = []
        items.reserveCapacity(rowCount)
        for index in 0..<rowCount {
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

        let payload = Payload(
            items: items,
            createdAt: Date(timeIntervalSince1970: 1_694_630_400),
            title: "Swift SQLite JSONB Benchmark"
        )

        let data = try JSONBEncoder.encode(payload)
        let jsonb = try JSONBValue(from: data)
        let object = try jsonb.object
        #expect(object["items"] != nil)
        #expect(object["createdAt"] != nil)
        #expect(object["title"] != nil)
    }
}

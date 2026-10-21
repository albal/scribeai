import Foundation
import Testing
@testable import ScribeCore

struct OllamaClientTests {
    @Test func validContentBecomesReadings() throws {
        let readings = try OllamaClient.readings(
            fromContent: #"{"alignment_score": 81, "concision": 70, "intensity": 30, "tone": "formal"}"#
        )
        #expect(readings == (try Readings(alignmentScore: 81, concision: 70, intensity: 30, tone: .formal)))
    }

    @Test(arguments: [
        "not json",
        #"{"alignment_score": 81, "concision": 70, "intensity": 30, "tone": "wistful"}"#,
        #"{"alignment_score": 181, "concision": 70, "intensity": 30, "tone": "formal"}"#,
        #"{"alignment_score": 81, "tone": "formal"}"#,
    ])
    func invalidContentIsRejected(content: String) {
        #expect(throws: OllamaError.invalidOutput) {
            try OllamaClient.readings(fromContent: content)
        }
    }

    @Test func schemaConstrainsToneToTheFixedSet() throws {
        let properties = try #require(OllamaClient.readingsSchema["properties"] as? [String: Any])
        let tone = try #require(properties["tone"] as? [String: Any])
        #expect(tone["enum"] as? [String] == Tone.allCases.map(\.rawValue))
    }
}

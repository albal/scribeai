import Testing
@testable import PromptHarness
@testable import ScribeCore

struct PromptHarnessTests {
    @Test(arguments: [
        "Consider replacing 'really bad' with 'substandard'.",
        "Use 'dreadful' instead of 'really bad'.",
        "Try rephrasing the opening so it lands harder.",
        "This sentence could be rewritten to remove the hedge.",
        "Change 'kind of' to “somewhat”.",
        "'really bad' → 'dire'",
    ])
    func rewordingSuggestionsAreFlagged(critique: String) {
        #expect(RewriteDetector.suggestsRewording(critique))
    }

    @Test(arguments: [
        "The register is too colloquial for this Style Brief: 'really bad' and 'kind of a mess' read as speech.",
        "The jump between the second and third sentences breaks the argument's rhythm.",
        "Redundancy: 'each and every' says the same thing twice.",
    ])
    func diagnosisAloneIsNotFlagged(critique: String) {
        #expect(!RewriteDetector.suggestsRewording(critique))
    }

    @Test func spreadIsTheMeanStandardDeviationAcrossRepeatedRuns() throws {
        var report = ModelReport(model: "m")
        report.readings = [
            "a": [try Readings(alignmentScore: 70, concision: 50, intensity: 50, tone: .formal),
                  try Readings(alignmentScore: 80, concision: 50, intensity: 50, tone: .formal)],
            "b": [try Readings(alignmentScore: 40, concision: 50, intensity: 50, tone: .casual),
                  try Readings(alignmentScore: 40, concision: 50, intensity: 50, tone: .urgent)],
        ]
        #expect(report.spread(\.alignmentScore) == 2.5)
        #expect(report.spread(\.concision) == 0)
        #expect(report.toneAgreement == 0.75)
    }

    @Test func optionsParse() throws {
        let options = try PromptHarness.parse(["--models", "a,b", "--runs", "5", "--targets", "publication.nature", "--no-critiques"])
        #expect(options.models == ["a", "b"])
        #expect(options.runs == 5)
        #expect(options.targets == [BuiltInTargets.nature])
        #expect(!options.critiques)
        #expect(throws: PromptHarness.UsageError.self) { try PromptHarness.parse(["--targets", "nope"]) }
    }
}

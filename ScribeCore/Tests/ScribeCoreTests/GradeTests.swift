import Testing
@testable import ScribeCore

struct GradeTests {
    @Test(arguments: [
        (100, "A+"), (97, "A+"), (96, "A"), (93, "A"), (92, "A−"), (90, "A−"),
        (89, "B+"), (87, "B+"), (86, "B"), (83, "B"), (82, "B−"), (80, "B−"),
        (79, "C+"), (77, "C+"), (76, "C"), (73, "C"), (72, "C−"), (70, "C−"),
        (69, "D+"), (67, "D+"), (66, "D"), (63, "D"), (62, "D−"), (60, "D−"),
        (59, "F"), (0, "F"),
    ])
    func bandBoundaries(score: Int, letter: String) {
        #expect(Grade(score: score).letter == letter)
    }

    @Test func readingsDeriveTheirGradeFromTheAlignmentScore() throws {
        let readings = try Readings(alignmentScore: 78, concision: 50, intensity: 50, tone: .neutral)
        #expect(readings.grade.letter == "C+")
    }

    @Test(arguments: [-1, 101])
    func outOfRangeReadingsAreRejected(value: Int) {
        #expect(throws: ReadingsError.outOfRange(value)) {
            try Readings(alignmentScore: value, concision: 50, intensity: 50, tone: .neutral)
        }
    }
}

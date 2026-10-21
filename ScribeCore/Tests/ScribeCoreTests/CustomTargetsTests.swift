import Foundation
import Synchronization
import Testing
@testable import ScribeCore

final class MemoryTargetStorage: CustomTargetStorage {
    private let stored: Mutex<[Target]>

    init(_ targets: [Target] = []) {
        stored = Mutex(targets)
    }

    func load() -> [Target] { stored.withLock { $0 } }
    func save(_ targets: [Target]) { stored.withLock { $0 = targets } }
}

@MainActor
struct CustomTargetsTests {
    let storage = MemoryTargetStorage()

    @Test func createdTargetsPersistAcrossLaunches() {
        let targets = CustomTargets(storage: storage)
        let hemingway = targets.create(name: "Hemingway", styleBrief: "Short declarative sentences.")
        #expect(hemingway.kind == .custom)
        #expect(hemingway.id.hasPrefix("custom."))

        let relaunched = CustomTargets(storage: storage)
        #expect(relaunched.targets == [hemingway])
    }

    @Test func renameAndEditPersist() throws {
        let targets = CustomTargets(storage: storage)
        let target = targets.create(name: "Draft", styleBrief: "Old brief.")
        targets.rename(target.id, to: "Hemingway")
        targets.editStyleBrief(target.id, to: "New brief.")

        let reloaded = try #require(CustomTargets(storage: storage).targets.first)
        #expect(reloaded.id == target.id)
        #expect(reloaded.name == "Hemingway")
        #expect(reloaded.styleBrief == "New brief.")
    }

    @Test func deletePersists() {
        let targets = CustomTargets(storage: storage)
        let keep = targets.create(name: "Keep", styleBrief: "A.")
        let drop = targets.create(name: "Drop", styleBrief: "B.")
        targets.delete(drop.id)
        #expect(CustomTargets(storage: storage).targets == [keep])
    }

    @Test func duplicatingABuiltInCopiesItsStyleBriefAndLeavesTheOriginalAlone() {
        let targets = CustomTargets(storage: storage)
        let copy = targets.duplicate(BuiltInTargets.economist)
        #expect(copy.kind == .custom)
        #expect(copy.name == "The Economist (Custom)")
        #expect(copy.styleBrief == BuiltInTargets.economist.styleBrief)
        #expect(copy.id != BuiltInTargets.economist.id)

        targets.editStyleBrief(copy.id, to: "Changed.")
        #expect(BuiltInTargets.economist.styleBrief != "Changed.")
        #expect(targets.catalog.target(id: BuiltInTargets.economist.id) == BuiltInTargets.economist)
    }

    @Test func customTargetsAppearInTheCatalogAfterTheBuiltIns() {
        let targets = CustomTargets(storage: storage)
        let custom = targets.create(name: "Mine", styleBrief: "My brief.")
        #expect(targets.catalog.all == BuiltInTargets.all + [custom])
    }

    @Test func aDocumentUsingADeletedTargetFallsBackToTheDefault() {
        let targets = CustomTargets(storage: storage)
        let custom = targets.create(name: "Mine", styleBrief: "My brief.")
        targets.delete(custom.id)
        let resolution = targets.catalog.resolve(storedID: custom.id, defaultID: BuiltInTargets.academic.id)
        #expect(resolution.target == BuiltInTargets.academic)
        #expect(resolution.unknownID == custom.id)
    }

    @Test func userDefaultsStorageRoundTrips() {
        let suite = "scribeai.tests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let storage = UserDefaultsCustomTargetStorage(suiteName: suite)
        let target = Target(id: "custom.x", name: "X", kind: .custom, styleBrief: "Brief.")
        storage.save([target])
        #expect(UserDefaultsCustomTargetStorage(suiteName: suite).load() == [target])
    }
}

@MainActor
struct StyleBriefEditTests {
    @Test func editingTheStyleBriefOfTheTargetInUseReEvaluates() async throws {
        let clock = ManualClock()
        let model = FakeModelClient()
        let targets = CustomTargets(storage: MemoryTargetStorage())
        let target = targets.create(name: "Mine", styleBrief: "First brief.")
        let session = EditorSession(target: target, model: model, clock: clock)
        session.textDidChange(long("A paragraph of prose."), cursor: 0)
        await clock.advance(by: EditorSession.pauseInterval)
        #expect(await waitUntil { session.readings != nil })

        targets.editStyleBrief(target.id, to: "Second brief.")
        session.target = try #require(targets.catalog.target(id: target.id))
        #expect(session.status == .pending)
        await clock.advance(by: EditorSession.pauseInterval)
        #expect(await waitUntil { model.prompts.count == 2 })
        #expect(try #require(model.prompts.last).user.contains("Second brief."))
    }
}

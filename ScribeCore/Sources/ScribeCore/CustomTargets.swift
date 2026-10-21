import Foundation
import Observation

/// Where Custom Targets are kept between launches.
public protocol CustomTargetStorage: Sendable {
    func load() -> [Target]
    func save(_ targets: [Target])
}

/// Stores Custom Targets as JSON in user defaults.
public struct UserDefaultsCustomTargetStorage: CustomTargetStorage {
    static let key = "customTargets"
    let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults { suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard }

    public func load() -> [Target] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return (try? JSONDecoder().decode([Target].self, from: data)) ?? []
    }

    public func save(_ targets: [Target]) {
        defaults.set(try? JSONEncoder().encode(targets), forKey: Self.key)
    }
}

/// The writer's Custom Targets: user-written Style Briefs available in every Document.
@MainActor @Observable
public final class CustomTargets {
    public private(set) var targets: [Target]

    @ObservationIgnored private let storage: any CustomTargetStorage

    public init(storage: any CustomTargetStorage) {
        self.storage = storage
        targets = storage.load()
    }

    public var catalog: TargetCatalog { TargetCatalog(custom: targets) }

    @discardableResult
    public func create(name: String, styleBrief: String) -> Target {
        let target = Target(id: "custom.\(UUID().uuidString.lowercased())", name: name, kind: .custom, styleBrief: styleBrief)
        targets.append(target)
        save()
        return target
    }

    /// Copies a Built-in Target's Style Brief into a new, editable Custom Target. The original is unchanged.
    @discardableResult
    public func duplicate(_ target: Target) -> Target {
        create(name: "\(target.name) (Custom)", styleBrief: target.styleBrief)
    }

    public func rename(_ id: Target.ID, to name: String) {
        update(id) { $0.name = name }
    }

    public func editStyleBrief(_ id: Target.ID, to styleBrief: String) {
        update(id) { $0.styleBrief = styleBrief }
    }

    public func delete(_ id: Target.ID) {
        targets.removeAll { $0.id == id }
        save()
    }

    private func update(_ id: Target.ID, _ change: (inout Target) -> Void) {
        guard let index = targets.firstIndex(where: { $0.id == id }) else { return }
        change(&targets[index])
        save()
    }

    private func save() {
        storage.save(targets)
    }
}

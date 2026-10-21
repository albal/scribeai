import ScribeCore
import SwiftUI

enum SettingsKey {
    static let modelName = "modelName"
    static let defaultTargetID = "defaultTargetID"
}

@main
struct ScribeAIApp: App {
    @AppStorage(SettingsKey.modelName) private var modelName = OllamaClient.defaultModel
    @State private var environment = ModelEnvironment(
        client: OllamaClient(model: UserDefaults.standard.string(forKey: SettingsKey.modelName) ?? OllamaClient.defaultModel)
    )
    @State private var customTargets = CustomTargets(storage: UserDefaultsCustomTargetStorage())

    var body: some Scene {
        DocumentGroup(newDocument: ScribeDocument()) { file in
            DocumentView(document: file.$document)
                .environment(environment)
                .environment(customTargets)
                .task { if environment.state == .checking { environment.check() } }
        }
        .onChange(of: modelName) { _, name in
            environment.use(OllamaClient(model: name))
        }

        Window("Custom Targets", id: CustomTargetsWindow.id) {
            CustomTargetsWindow()
                .environment(customTargets)
        }

        Settings {
            SettingsView()
                .environment(customTargets)
        }
    }
}

struct SettingsView: View {
    @AppStorage(SettingsKey.modelName) private var modelName = OllamaClient.defaultModel
    @AppStorage(SettingsKey.defaultTargetID) private var defaultTargetID = BuiltInTargets.default.id
    @Environment(CustomTargets.self) private var customTargets
    @State private var draft = ""

    var body: some View {
        Form {
            Picker("Default Target", selection: $defaultTargetID) {
                Section("Levels") {
                    ForEach(BuiltInTargets.levels) { Text($0.name).tag($0.id) }
                }
                Section("Publications") {
                    ForEach(BuiltInTargets.publications) { Text($0.name).tag($0.id) }
                }
                if !customTargets.targets.isEmpty {
                    Section("Custom") {
                        ForEach(customTargets.targets) { Text($0.name).tag($0.id) }
                    }
                }
            }
            Text("Used for new Documents and for files that don't name a Target.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Ollama model", text: $draft, prompt: Text(OllamaClient.defaultModel))
                .onSubmit(commit)
            Text("Any model name from ollama.com/library, e.g. gemma3:12b. Press Return to apply.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 420)
        .onAppear { draft = modelName }
        .onDisappear(perform: commit)
    }

    private func commit() {
        let name = draft.trimmingCharacters(in: .whitespaces)
        modelName = name.isEmpty ? OllamaClient.defaultModel : name
    }
}

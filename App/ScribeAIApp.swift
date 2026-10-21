import ScribeCore
import SwiftUI

enum SettingsKey {
    static let modelName = "modelName"
}

@main
struct ScribeAIApp: App {
    @AppStorage(SettingsKey.modelName) private var modelName = OllamaClient.defaultModel
    @State private var environment = ModelEnvironment(
        client: OllamaClient(model: UserDefaults.standard.string(forKey: SettingsKey.modelName) ?? OllamaClient.defaultModel)
    )

    var body: some Scene {
        DocumentGroup(newDocument: ScribeDocument()) { file in
            DocumentView(document: file.$document)
                .environment(environment)
                .task { if environment.state == .checking { environment.check() } }
        }
        .onChange(of: modelName) { _, name in
            environment.use(OllamaClient(model: name))
        }

        Settings {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    @AppStorage(SettingsKey.modelName) private var modelName = OllamaClient.defaultModel
    @State private var draft = ""

    var body: some View {
        Form {
            TextField("Ollama model", text: $draft, prompt: Text(OllamaClient.defaultModel))
                .onSubmit(commit)
            Text("Any model name from ollama.com/library, e.g. llama3.1:8b. Press Return to apply.")
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

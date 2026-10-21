import ScribeCore
import SwiftUI

/// Create, rename, edit and delete Custom Targets.
struct CustomTargetsWindow: View {
    static let id = "custom-targets"

    @Environment(CustomTargets.self) private var customTargets
    @State private var selection: Target.ID?

    var body: some View {
        NavigationSplitView {
            List(customTargets.targets, selection: $selection) { target in
                Text(target.name).tag(target.id)
            }
            .overlay {
                if customTargets.targets.isEmpty {
                    ContentUnavailableView("No Custom Targets", systemImage: "target", description: Text("Write your own Style Brief, or duplicate a Built-in Target."))
                }
            }
            .toolbar {
                ToolbarItem {
                    Menu {
                        Button("Blank Style Brief") {
                            selection = customTargets.create(name: "New Target", styleBrief: "").id
                        }
                        Section("Duplicate a Built-in") {
                            ForEach(BuiltInTargets.all) { target in
                                Button(target.name) { selection = customTargets.duplicate(target).id }
                            }
                        }
                    } label: {
                        Label("New Custom Target", systemImage: "plus")
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            if let target = customTargets.targets.first(where: { $0.id == selection }) {
                CustomTargetEditor(target: target)
                    .id(target.id)
            } else {
                Text("Select a Custom Target").foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 620, minHeight: 380)
    }
}

private struct CustomTargetEditor: View {
    let target: Target
    @Environment(CustomTargets.self) private var customTargets
    @State private var name = ""
    @State private var styleBrief = ""

    var body: some View {
        Form {
            TextField("Name", text: $name)
                .onChange(of: name) { _, name in customTargets.rename(target.id, to: name) }
            Section {
                TextEditor(text: $styleBrief)
                    .font(.body)
                    .frame(minHeight: 200)
                    .onChange(of: styleBrief) { _, brief in customTargets.editStyleBrief(target.id, to: brief) }
            } header: {
                Text("Style Brief")
            } footer: {
                Text("Describe the standard: sentence length, vocabulary, register, and what to avoid. Documents using this Target are evaluated again when it changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Delete Target", role: .destructive) {
                customTargets.delete(target.id)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            name = target.name
            styleBrief = target.styleBrief
        }
    }
}

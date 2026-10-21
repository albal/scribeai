import ScribeCore
import SwiftUI

/// The toolbar menu choosing the Document's Target.
struct TargetMenu: View {
    let catalog: TargetCatalog
    let selection: Target
    let choose: (Target) -> Void
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Menu {
            section("Levels", BuiltInTargets.levels)
            section("Publications", BuiltInTargets.publications)
            if !catalog.custom.isEmpty {
                section("Custom", catalog.custom)
            }
            Divider()
            Button("Manage Custom Targets…") { openWindow(id: CustomTargetsWindow.id) }
        } label: {
            Label(selection.name, systemImage: "target")
                .labelStyle(.titleAndIcon)
        }
        .help("The writing standard this Document is judged against")
    }

    private func section(_ title: String, _ targets: [Target]) -> some View {
        Section(title) {
            ForEach(targets) { target in
                Toggle(target.name, isOn: Binding(
                    get: { target.id == selection.id },
                    set: { if $0 { choose(target) } }
                ))
            }
        }
    }
}

/// Shows the Style Brief a Target judges against.
struct StyleBriefView: View {
    let target: Target
    /// Copies a Built-in Target into a Custom Target and switches to it.
    let duplicate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(target.name).font(.headline)
                Spacer()
                Text(target.isBuiltIn ? "Built-in · read-only" : "Custom")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Style Brief").font(.subheadline.weight(.semibold))
            Text(target.styleBrief.isEmpty ? "No Style Brief yet." : target.styleBrief)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if target.isBuiltIn {
                Button("Duplicate as Custom", action: duplicate)
                    .help("Copy this Style Brief into a Custom Target you can edit")
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}

import ScribeCore
import SwiftUI

struct DocumentView: View {
    @Binding var document: ScribeDocument
    @Environment(ModelEnvironment.self) private var environment
    @Environment(CustomTargets.self) private var customTargets
    @Environment(\.openWindow) private var openWindow
    @State private var session: EditorSession
    @State private var unknownTargetID: String?
    @State private var showsStyleBrief = false

    init(document: Binding<ScribeDocument>) {
        _document = document
        _session = State(initialValue: EditorSession(text: document.wrappedValue.file.body, model: OllamaClient()))
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                if let unknownTargetID {
                    notice(for: unknownTargetID)
                }
                MarkdownEditor(
                    text: document.file.body,
                    onTextChange: { text, selection in
                        document.file.body = text
                        session.textDidChange(text, selection: selection)
                    },
                    onSelectionChange: { session.selectionDidChange($0) }
                )
                Divider()
                HStack {
                    Spacer()
                    Text("\(session.wordCount) words")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .frame(minWidth: 420)

            Group {
                if environment.state == .ready {
                    GaugePane(session: session)
                } else {
                    EnvironmentStatusView(environment: environment)
                }
            }
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Scope", selection: $session.scope) {
                    ForEach(Scope.allCases) { scope in
                        Text(scope.name).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .help("How much text is evaluated. Selecting two or more words evaluates just the Selection.")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                TargetMenu(catalog: customTargets.catalog, selection: session.target, choose: choose)
                Button {
                    showsStyleBrief.toggle()
                } label: {
                    Label("Style Brief", systemImage: "text.book.closed")
                }
                .help("Show the Style Brief for \(session.target.name)")
                .popover(isPresented: $showsStyleBrief) {
                    StyleBriefView(target: session.target) {
                        showsStyleBrief = false
                        choose(customTargets.duplicate(session.target))
                        openWindow(id: CustomTargetsWindow.id)
                    }
                }
            }
        }
        .onAppear(perform: resolveTarget)
        .onChange(of: customTargets.targets) { _, _ in followCustomTargetChanges() }
        .onChange(of: environment.state, initial: true) { _, state in
            guard state == .ready else { return }
            session.model = environment.client
            session.scheduleEvaluation()
        }
        .onChange(of: session.status) { _, status in
            if case .failed(let failure) = status {
                environment.evaluationFailed(failure)
            }
        }
    }

    private var defaultTargetID: String? {
        UserDefaults.standard.string(forKey: SettingsKey.defaultTargetID)
    }

    private func resolveTarget() {
        let resolution = customTargets.catalog.resolve(storedID: document.file.targetID, defaultID: defaultTargetID)
        session.target = resolution.target
        unknownTargetID = resolution.unknownID
    }

    /// Keeps the session's copy of a Custom Target current, and falls back if it was deleted.
    private func followCustomTargetChanges() {
        guard !session.target.isBuiltIn else { return }
        if let updated = customTargets.catalog.target(id: session.target.id) {
            session.target = updated
        } else {
            resolveTarget()
        }
    }

    private func choose(_ target: Target) {
        session.target = target
        document.file.targetID = target.id
        unknownTargetID = nil
    }

    private func notice(for id: String) -> some View {
        HStack {
            Image(systemName: "info.circle")
            Text("This Document's Target “\(id)” no longer exists, so it's using \(session.target.name). Choose a Target to replace it.")
                .font(.callout)
            Spacer()
            Button("Dismiss") { unknownTargetID = nil }
        }
        .padding(10)
        .background(.yellow.opacity(0.15))
    }
}

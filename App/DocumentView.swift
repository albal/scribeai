import ScribeCore
import SwiftUI

struct DocumentView: View {
    @Binding var document: ScribeDocument
    @Environment(ModelEnvironment.self) private var environment
    @State private var session: EditorSession

    init(document: Binding<ScribeDocument>) {
        _document = document
        _session = State(initialValue: EditorSession(text: document.wrappedValue.text, model: OllamaClient()))
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                MarkdownEditor(
                    text: document.text,
                    onTextChange: { text, cursor in
                        document.text = text
                        session.textDidChange(text, cursor: cursor)
                    },
                    onCursorMove: { session.cursorDidMove(to: $0) }
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
}

import SwiftUI

@main
struct ScribeAIApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: ScribeDocument()) { file in
            DocumentView(document: file.$document)
        }
    }
}

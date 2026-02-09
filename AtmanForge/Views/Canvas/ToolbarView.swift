import SwiftUI

struct CanvasToolbar: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        HStack(spacing: 4) {
            Button {
                appState.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            .disabled(!appState.canUndo)
            .help("Undo (⌘Z)")

            Button {
                appState.redo()
            } label: {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .buttonStyle(.bordered)
            .disabled(!appState.canRedo)
            .help("Redo (⇧⌘Z)")

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}

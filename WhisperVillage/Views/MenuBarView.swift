import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var whisperState: WhisperState
    @EnvironmentObject var hotkeyManager: HotkeyManager
    @EnvironmentObject var menuBarManager: MenuBarManager

    var body: some View {
        VStack {
            // Current model display
            Menu {
                ForEach(whisperState.allAvailableModels, id: \.id) { model in
                    Button {
                        Task {
                            await whisperState.setDefaultTranscriptionModel(model)
                        }
                    } label: {
                        HStack {
                            Text(model.displayName)
                            if whisperState.currentTranscriptionModel?.id == model.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text("Model: \(whisperState.currentTranscriptionModel?.displayName ?? "None")")
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10))
                }
            }

            Divider()

            Button("Paste Last Transcription") {
                LastTranscriptionService.shared.pasteLastTranscription()
            }

            Divider()

            Button("Quit Whisper Village") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}

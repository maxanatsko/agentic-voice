import SwiftUI
import TTSBridgeCore
import UniformTypeIdentifiers

/// Records or picks a voice sample and clones it. `onDone` gets the new voice's id, or nil on Cancel.
struct CloneVoiceView: View {
    @ObservedObject var model: SettingsModel
    let onDone: (String?) -> Void
    @StateObject private var recorder = VoiceRecorder()
    @State private var chosenFile: URL?
    @State private var name = ""
    @State private var consent = false
    @State private var importing = false
    @State private var error: String?

    private static let script = """
        Build finished, and two tests need your attention. I'm setting up my own voice for \
        Agentic Voice, so it should sound just like me: clear, relaxed and natural.
        """

    private var sample: URL? { chosenFile ?? recorder.recording }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Text(Self.script).font(.title3).textSelection(.enabled)
                } header: {
                    Text("Read This Aloud")
                } footer: {
                    Text("Speak naturally in a quiet room. Recording stops after \(Int(ClonedVoiceStore.usedSeconds)) seconds, all a clone uses.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Sample") {
                    LabeledContent {
                        if recorder.isRecording {
                            Button("Stop", systemImage: "stop.fill") { recorder.stop() }
                        } else {
                            Button(recorder.recording == nil ? "Record" : "Record Again", systemImage: "mic.fill") {
                                chosenFile = nil
                                Task {
                                    do { try await recorder.start() } catch { self.error = error.localizedDescription }
                                }
                            }
                        }
                    } label: {
                        Text("Record with the microphone")
                        if recorder.isRecording || recorder.recording != nil {
                            Text(String(format: "%.1f s", recorder.elapsed)).monospacedDigit()
                        }
                    }
                    LabeledContent {
                        Button("Choose File…") { importing = true }
                    } label: {
                        Text("Or use a recording you have")
                        if let chosenFile { Text(chosenFile.lastPathComponent) }
                    }
                }
                Section {
                    TextField("Name", text: $name, prompt: Text("Max"))
                    Toggle("This is my voice, or I have permission to clone it", isOn: $consent)
                } footer: {
                    Text("The sample and the cloned voice stay on this Mac. The first clone downloads the voice-cloning model (about 300 MB).")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red).textSelection(.enabled) }
                }
            }
            .formStyle(.grouped)
            HStack {
                if model.cloning {
                    ProgressView().controlSize(.small)
                    Text("Cloning…").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { finish(nil) }
                    .keyboardShortcut(.cancelAction)
                Button("Clone Voice") { Task { await clone() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(sample == nil || recorder.isRecording || name.trimmingCharacters(in: .whitespaces).isEmpty || !consent)
            }
            .padding()
        }
        // Changing the sample mid-clone would delete the file the clone is still reading.
        .disabled(model.cloning)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.audio]) { result in
            switch result {
            case .success(let url):
                recorder.discard()
                chosenFile = url
            case .failure(let failure):
                error = failure.localizedDescription
            }
        }
    }

    private func clone() async {
        guard let sample else { return }
        error = nil
        do {
            finish(try await model.cloneVoice(name: name, from: sample))
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func finish(_ id: String?) {
        recorder.discard()
        onDone(id)
    }
}

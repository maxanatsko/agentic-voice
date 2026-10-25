import AgenticVoiceKit
import Foundation
import MCP

private let instructions = """
    The user listens for spoken updates. Call speak at these moments, in addition to your normal text reply:
    - When you finish a turn of work: one or two sentences summarizing the outcome.
    - When you need input or a decision: speak the question, then also show it as text or through your question tool.
    - When you hit a blocker that needs attention.
    Write for listening: no code, paths, logs, or long technical output. Do not speak for routine progress.
    If speak reports that another session is speaking, do not retry right away; usually skip it, since your text reply already carries the message.
    """

private let speakTool = Tool(
    name: "speak",
    title: "Speak a short message",
    description: "Speak a concise question, blocker, alert, or completion summary through local TTS. Do not send code, logs, paths, or long output.",
    inputSchema: .object([
        "type": .string("object"),
        "properties": .object([
            "text": .object([
                "type": .string("string"),
                "description": .string("One or two short sentences written for listening, not a copy of detailed text output."),
            ]),
            "kind": .object([
                "type": .string("string"),
                "enum": .array(SpeechKind.allCases.map { .string($0.rawValue) }),
                "description": .string("Optional reason for speaking. The Agentic Voice app's speaking overlay picks its animation from it."),
            ]),
        ]),
        "required": .array([.string("text")]),
    ])
)

/// Keeps signal sources alive for the life of the process.
nonisolated(unsafe) private var signalSources: [DispatchSourceSignal] = []

/// Serves the speak tool over stdio until stdin closes or a SIGINT/SIGTERM arrives, starting the
/// bundled bridge if the endpoint is the bundled one, and stopping only a bridge it started.
func runMCPServer(environment: [String: String], bridgeExecutable: URL) async throws {
    var config = try Config.load(environment: environment)
    let local = Config.isBundledTTSURL(config.ttsURL)
    // The bundled bridge binds IPv4 only; localhost may resolve to IPv6 first.
    if local { config.ttsURL = Config.bundledTTSURL }
    let ttsURL = config.ttsURL
    let bridge = local ? BridgeProcess(url: ttsURL, options: .init(executable: bridgeExecutable)) : nil

    // Stay connected after a bridge failure: speak reports the error to the client, which
    // otherwise sees only a dropped connection after a successful handshake.
    let ready = Task {
        do {
            try await bridge?.start()
        } catch is CancellationError {
            throw CancellationError()  // Shutting down; nothing failed.
        } catch {
            printError("agentic-voice: bridge startup failed: \(error.localizedDescription)")
            await bridge?.stop()
            throw error
        }
    }

    let server = Server(
        name: "agentic-voice", version: "0.8.0", instructions: instructions,
        capabilities: .init(tools: .init(listChanged: false))
    )
    await server.withMethodHandler(ListTools.self) { _ in .init(tools: [speakTool]) }
    await server.withMethodHandler(CallTool.self) { params in
        guard params.name == speakTool.name else { throw MCPError.invalidParams("Unknown tool: \(params.name)") }
        guard let text = params.arguments?["text"]?.stringValue else {
            return .init(content: [reply("speak needs a \"text\" string.")], isError: true)
        }
        var kind: SpeechKind?
        if let value = params.arguments?["kind"] {
            guard let parsed = value.stringValue.flatMap({ SpeechKind(rawValue: $0) }) else {
                return .init(content: [reply("speak \"kind\" must be one of: \(speechKinds).")], isError: true)
            }
            kind = parsed
        }
        do {
            try await ready.value
            // Re-read voice and speed on every call so settings changes apply without a restart.
            // The endpoint stays fixed: the bridge was resolved and started for it.
            var current = try Config.load(environment: environment)
            current.ttsURL = ttsURL
            let outcome = try await VoiceService(config: current).speak(text, kind: kind)
            return .init(content: [reply(outcome == .spoken
                ? "Spoken successfully."
                : "Not spoken: another agentic-voice session is speaking. Your text reply is unaffected; skip, or call speak again later only if it still matters.")])
        } catch {
            return .init(content: [reply(error.localizedDescription)], isError: true)
        }
    }

    let shutdown: @Sendable () async -> Void = {
        ready.cancel()
        await bridge?.stop()
    }
    for signalNumber in [SIGINT, SIGTERM] {
        signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: signalNumber)
        source.setEventHandler {
            Task {
                await shutdown()
                exit(0)
            }
        }
        source.resume()
        signalSources.append(source)
    }

    try await server.start(transport: StdioTransport())
    printError("agentic-voice MCP server running on stdio")
    await server.waitUntilCompleted()
    await shutdown()
}

private func reply(_ text: String) -> Tool.Content {
    .text(text: text, annotations: nil, _meta: nil)
}

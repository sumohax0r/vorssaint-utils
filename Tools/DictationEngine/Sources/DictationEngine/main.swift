// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation
import Darwin
import FluidAudio

// A local-only, line-delimited JSON worker. It never downloads models or captures audio.
struct Request: Decodable { let id: String; let path: String }
struct Reply: Encodable { let id: String; let text: String?; let error: String? }
func emit(_ reply: Reply) {
    if let data = try? JSONEncoder().encode(reply) {
        FileHandle.standardOutput.write(Data("VORSSAINT_DICTATION ".utf8) + data + Data([10]))
    }
}
@main struct Engine {
    static func main() async {
        do {
            guard CommandLine.arguments.count == 2 else { throw CocoaError(.fileReadInvalidFileName) }
            // One model owner per macOS user, including across app builds. Keep
            // the descriptor open until process exit; never unlink the lock file.
            let lockURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("VorssaintDictationEngine.lock")
            let lockFD = open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
            guard lockFD >= 0 else { throw CocoaError(.fileWriteNoPermission) }
            defer { close(lockFD) }
            // The retiring worker may still be exiting after SIGTERM. Wait for
            // its lock before allocating any model, rather than loading twice.
            guard flock(lockFD, LOCK_EX) == 0 else { throw CocoaError(.fileLocking) }
            let owner = getppid()
            let watchdog = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
            watchdog.schedule(deadline: .now() + 1, repeating: 1)
            watchdog.setEventHandler { @Sendable in if getppid() != owner || owner == 1 { _exit(0) } }
            watchdog.resume()
            defer { watchdog.cancel() }
            let models = try AsrModels.loadLocal(from: URL(fileURLWithPath: CommandLine.arguments[1]), version: .v3)
            let manager = AsrManager()
            try await manager.loadModels(models)
            emit(Reply(id: "ready", text: "", error: nil))
            while let line = readLine() {
                guard let data = line.data(using: .utf8), let request = try? JSONDecoder().decode(Request.self, from: data) else { continue }
                do {
                    var state = try TdtDecoderState()
                    let result = try await manager.transcribe(URL(fileURLWithPath: request.path), decoderState: &state)
                    emit(Reply(id: request.id, text: result.text, error: nil))
                } catch { emit(Reply(id: request.id, text: nil, error: error.localizedDescription)) }
            }
        } catch { emit(Reply(id: "ready", text: nil, error: error.localizedDescription)) }
    }
}

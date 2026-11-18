// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

/// All public methods and callbacks run on main. Only stdout parsing uses the reader queue.
final class DictationWorker {
    struct Reply: Decodable { let id: String; let text: String?; let error: String? }
    static var executable: URL? { Bundle.main.url(forAuxiliaryExecutable: "DictationEngine") }
    private var process: Process?
    private var input: FileHandle?
    private var generation = UUID()
    var processID: pid_t? { process?.isRunning == true ? process?.processIdentifier : nil }
    var onReply: ((Reply) -> Void)?
    func launch(model: DictationModel) throws {
        stop()
        guard let executable = Self.executable else { throw CocoaError(.fileNoSuchFile) }
        let process = Process(), stdin = Pipe(), stdout = Pipe()
        process.executableURL = executable
        process.arguments = [model.directory.path]
        if model.id == "bark-clean" || model.id == "phonon-english" {
            guard let pathFile = Bundle.main.url(forResource: "BarkPythonPath", withExtension: "txt"),
                  let python = try? String(contentsOf: pathFile, encoding: .utf8),
                  FileManager.default.isExecutableFile(atPath: python),
                  let script = Bundle.main.url(forResource: model.id == "phonon-english" ? "phonon_worker" : "worker", withExtension: "py", subdirectory: "BarkEngine") else {
                throw CocoaError(.executableNotLoadable)
            }
            process.executableURL = URL(fileURLWithPath: python)
            process.arguments = ["-I", "-u", script.path, model.directory.path]
        }
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        let token = generation
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.generation == token else { return }
                self.onReply?(Reply(id: "exit", text: nil, error: DictationStrings.text("failed")))
            }
        }
        try process.run()
        self.process = process
        input = stdin.fileHandleForWriting
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var pending = Data()
            // Pipe replies are small and the helper stays alive between requests.
            // Read whatever is available; a counted Foundation read can wait for
            // more bytes while the helper waits for our next request.
            while true {
                let data = stdout.fileHandleForReading.availableData
                guard !data.isEmpty else { break }
                pending.append(data)
                while let newline = pending.firstIndex(of: 10) {
                    let line = pending[..<newline]
                    pending.removeSubrange(...newline)
                    let prefix = Data("VORSSAINT_DICTATION ".utf8)
                    guard line.starts(with: prefix), let reply = try? JSONDecoder().decode(Reply.self, from: Data(line.dropFirst(prefix.count))) else { continue }
                    DispatchQueue.main.async {
                        guard let self, self.generation == token else { return }
                        self.onReply?(reply)
                    }
                }
                if pending.count > 1_048_576 { pending.removeAll() }
            }
        }
    }
    func transcribe(_ url: URL, id: String) throws {
        guard process?.isRunning == true, let input else { throw CocoaError(.executableNotLoadable) }
        let data = try JSONSerialization.data(withJSONObject: ["id": id, "path": url.path])
        try input.write(contentsOf: data + Data([10]))
    }
    func stop() {
        generation = UUID()
        try? input?.close(); input = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil
    }
    deinit { stop() }
}

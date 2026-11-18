// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation
import CryptoKit

struct DictationModel: Decodable, Identifiable {
    struct Artifact: Decodable {
        let path: String
        let destination: String
        let size: Int64
        let sha256: String?
    }
    let id: String
    let repo: String
    let revision: String
    let files: [Artifact]
    var title: String {
        switch id {
        case "fluid": return "Fluid Speech Mini"
        case "phonon-english": return "Phonon 2.5 English"
        case "bark-clean": return "Bark 3.0 Clean"
        default: return "Parakeet v3"
        }
    }
    var bytes: Int64 { files.reduce(0) { $0 + $1.size } }
    var directory: URL { Self.root.appendingPathComponent(id + "-" + revision) }
    var installed: Bool { FileManager.default.fileExists(atPath: directory.appendingPathComponent(".complete").path) }
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.vorssaint.utils")
            .appendingPathComponent("DictationModels", isDirectory: true)
    }
    static let catalog: [Self] = {
        guard let url = Bundle.main.url(forResource: "DictationModels", withExtension: "json"),
              let data = try? Data(contentsOf: url), let models = try? JSONDecoder().decode([Self].self, from: data) else { return [] }
        return models
    }()
    struct DownloadProgress: Sendable {
        let received: Int64
        let total: Int64
        let verifying: Bool
    }
    func download(progress: @escaping (DownloadProgress) -> Void) async throws {
        let fm = FileManager.default
        let staging = Self.root.appendingPathComponent(UUID().uuidString + ".partial")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        // Model transfers have their own lifetime. Do not retain their network
        // caches in the app-wide shared session after completion or cancellation.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        var completed: Int64 = 0
        for file in files {
            try Task.checkCancellation()
            guard !file.path.contains(".."), !file.destination.contains(".."), !file.destination.hasPrefix("/") else { throw CocoaError(.fileReadCorruptFile) }
            let url = URL(string: "https://huggingface.co/\(repo)/resolve/\(revision)/\(file.path)")!
            let previous = completed
            let delegate = DictationDownloadProgress { received in
                progress(DownloadProgress(received: previous + min(received, file.size), total: bytes, verifying: false))
            }
            progress(DownloadProgress(received: completed, total: bytes, verifying: false))
            let (temporary, response) = try await delegate.download(from: url, configuration: configuration)
            defer { try? fm.removeItem(at: temporary) }
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  (try fm.attributesOfItem(atPath: temporary.path)[.size] as? NSNumber)?.int64Value == file.size else { throw CocoaError(.fileReadCorruptFile) }
            let destination = staging.appendingPathComponent(file.destination)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: temporary, to: destination)
            completed += file.size
            progress(DownloadProgress(received: completed, total: bytes, verifying: false))
        }
        // Keep transfer speed/ETA visible throughout all network requests.
        // Verification is a distinct final phase, including for small artifacts.
        progress(DownloadProgress(received: completed, total: bytes, verifying: true))
        for file in files {
            try Task.checkCancellation()
            if let expected = file.sha256 {
                let handle = try FileHandle(forReadingFrom: staging.appendingPathComponent(file.destination))
                defer { try? handle.close() }
                var hash = SHA256()
                while true {
                    try Task.checkCancellation()
                    // Release Foundation's temporary read buffers every chunk,
                    // rather than retaining a model-sized autorelease backlog.
                    let hasData = try autoreleasepool {
                        guard let block = try handle.read(upToCount: 1_048_576), !block.isEmpty else { return false }
                        hash.update(data: block)
                        return true
                    }
                    if !hasData { break }
                }
                guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == expected else { throw CocoaError(.fileReadCorruptFile) }
            }
        }
        try Task.checkCancellation()
        try Data(revision.utf8).write(to: staging.appendingPathComponent(".complete"), options: .atomic)
        if fm.fileExists(atPath: directory.path) { try fm.removeItem(at: directory) }
        try fm.moveItem(at: staging, to: directory)
    }
}

/// URLSession serializes progress callbacks; the owner forwards them to main.
private final class DictationDownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let report: (Int64) -> Void
    private var lastReport = -Double.infinity
    init(report: @escaping (Int64) -> Void) { self.report = report }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        let now = ProcessInfo.processInfo.systemUptime
        // Byte counts stay useful even when the server omits Content-Length.
        guard now - lastReport >= 0.25 || totalBytesWritten == totalBytesExpectedToWrite else { return }
        lastReport = now
        report(totalBytesWritten)
    }
    private let lock = NSLock()
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var cancelled = false
    private var downloaded: URL?
    private var moveError: Error?

    func download(from url: URL, configuration: URLSessionConfiguration) async throws -> (URL, URLResponse) {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if cancelled {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                let task = session.downloadTask(with: url)
                self.task = task
                lock.unlock()
                task.resume()
            }
        } onCancel: {
            self.lock.lock()
            self.cancelled = true
            let task = self.task
            self.lock.unlock()
            task?.cancel()
        }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // URLSession deletes its temporary file when this callback returns.
        // Preserve it before resuming the caller on the completion callback.
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".dictation-download")
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            downloaded = destination
        } catch { moveError = error }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        self.task = nil
        let wasCancelled = cancelled
        lock.unlock()
        defer { session.finishTasksAndInvalidate() }
        if let failure = wasCancelled ? CancellationError() : (error ?? moveError) {
            if let downloaded { try? FileManager.default.removeItem(at: downloaded) }
            continuation?.resume(throwing: failure)
        } else if let downloaded, let response = task.response {
            continuation?.resume(returning: (downloaded, response))
        } else {
            if let downloaded { try? FileManager.default.removeItem(at: downloaded) }
            continuation?.resume(throwing: URLError(.badServerResponse))
        }
    }
}

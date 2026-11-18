// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AppKit
import AVFoundation
import SwiftUI
import OSLog

// Mutable state is confined to the main run loop. Worker/progress callbacks hop to main.
final class DictationService: ObservableObject, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.vorssaint.utils", category: "Dictation")
    static let shared = DictationService()
    enum State { case disabled, needsModel, downloading, loading, ready, recording, processing, permissionRequired, review, failed }
    @Published private(set) var triggerWarning = ""
    @Published private(set) var modelLoaded = false
    private var heldTrigger: String?
    @Published private(set) var state: State = .disabled
    @Published private(set) var message = ""
    @Published private(set) var transcript = ""
    @Published private(set) var lastTranscript = ""
    @Published private(set) var level: Float = 0
    @Published private(set) var downloadProgress = 0.0
    @Published private(set) var downloadStatus = ""
    private var downloadSampleTime = 0.0
    private var downloadSampleBytes: Int64 = 0
    private var downloadSpeed = 0.0
    @Published private(set) var devices: [DictationCapture.Device] = []
    private let worker = DictationWorker()
    private let capture = DictationCapture()
    private let hotkey = QuickToolHotkey(id: 94)
    private let paste = TransientPaste()
    private let mute = DictationOutputMute()
    private let sounds = DictationSounds()
    private var pendingStartCue: DispatchWorkItem?
    private var startCuePlayed = false
    private var downloadTask: Task<Void, Never>?
    private var timeout: DispatchWorkItem?
    private var reviewDismissal: DispatchWorkItem?
    private var timer: Timer?
    private var panel: NSPanel?
    private var mouseTap: CFMachPort?
    private var mouseSource: CFRunLoopSource?
    private var mouseButtons: Set<Int64> = []
    private var modifierKey: Int64?
    private var modifierDown = false
    private var modifierSolo = false
    private var ownedMouseButtons: Set<Int64> = []
    private var token = UUID()
    private var selectedID = ""
    private var microphoneID = ""
    private var requestID: String?
    private var requestFile: URL?
    private var requestWasFinal = false
    private var previewAt = Date.distantPast
    private var previewCompletedAt = Date.distantPast
    private var recordingStartedAt: TimeInterval?
    private var captureAttemptAt: TimeInterval = 0
    private var captureRestarted = false
    private var targetPID: pid_t?
    private var targetElement: AXUIElement?
    private var targetWindow: AXUIElement?
    private weak var localTextTarget: NSTextView?
    private var observers: [NSObjectProtocol] = []
    private var configurationObserver: NSObjectProtocol?
    private var recordingFolder: URL?
    var modelProcessID: pid_t? { worker.processID }
    var models: [DictationModel] { DictationModel.catalog }
    var selectedModel: DictationModel? { models.first { $0.id == UserDefaults.standard.string(forKey: DefaultsKey.dictationModel) } }
    var active: Bool { state == .recording || state == .processing }
    var enabled: Bool { AppFeature.dictation.isAvailable && UserDefaults.standard.bool(forKey: DefaultsKey.dictationEnabled) }
    private var keepReady: Bool { UserDefaults.standard.bool(forKey: DefaultsKey.dictationKeepReady) }
    var streaming: Bool { UserDefaults.standard.bool(forKey: DefaultsKey.dictationStreaming) }

    private init() {
        hotkey.onPress = { [weak self] in self?.triggerPressed("keyboard") }
        hotkey.onRelease = { [weak self] in self?.triggerReleased("keyboard") }
        worker.onReply = { [weak self] in self?.receive($0) }
        SessionActivity.shared.onChange { [weak self] _ in
            guard let self else { return }
            if !SessionActivity.shared.isActive { self.stop() } else { self.syncWithPreferences() }
        }
    }
    func refreshDevices() {
        DispatchQueue.global(qos: .utility).async {
            let found = DictationCapture.devices()
            DispatchQueue.main.async { self.devices = found }
        }
    }
    func syncWithPreferences() {
        guard enabled, SessionActivity.shared.isActive else { stop(); return }
        guard #available(macOS 15.0, *) else { fail("osRequired"); return }
        guard DictationWorker.executable != nil else { fail("helperMissing"); return }
        DictationShortcut.migrate()
        let preferences = UserDefaults.standard
        let rawShortcut = preferences.string(forKey: DefaultsKey.dictationShortcut) ?? ""
        let shortcut = GlobalShortcut(storageValue: rawShortcut, requiringModifier: false) ?? GlobalShortcut(keyCode: 2, modifiers: [.control, .option])
        if !hotkey.sync(enabled: DictationShortcut.modifier(rawShortcut) == nil, shortcut: shortcut, storageKey: DefaultsKey.dictationShortcut) { message = DictationStrings.text("shortcutFailed") }
        syncMouse()
        if observers.isEmpty {
            let center = NSWorkspace.shared.notificationCenter
            observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.suspend() })
            observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.syncWithPreferences() })
            configurationObserver = NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: capture.session, queue: .main) { [weak self] _ in
                guard let self, self.state == .recording else { return }
                self.cancel(); self.message = DictationStrings.text("failed")
            }
        }
        let nextMic = preferences.string(forKey: DefaultsKey.dictationMicrophone) ?? ""
        if nextMic != microphoneID { cancel(); capture.stop(); microphoneID = nextMic }
        guard let model = selectedModel else { suspend(); state = .needsModel; message = DictationStrings.text("chooseModel"); return }
        if model.id != selectedID { suspend(); selectedID = model.id }
        guard downloadTask == nil else { return }
        guard model.installed else { state = .needsModel; message = DictationStrings.text("modelNeeded"); return }
        if state == .disabled || state == .needsModel || state == .failed {
            state = .ready; message = DictationStrings.text(modelLoaded ? "ready" : "onDemand")
        }
        if state == .ready {
            sounds.prepare()
            if keepReady, modelLoaded, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
                do { try capture.start(deviceUID: microphoneID) } catch { fail("failed") }
            } else { capture.stop() }
        }
    }
    func selectModel() {
        let nextID = selectedModel?.id ?? ""
        guard nextID != selectedID else { return }
        suspend()
        selectedID = nextID
        syncWithPreferences()
        if enabled, let model = selectedModel, !model.installed { download() }
    }
    func modelStatus(_ model: DictationModel) -> String {
        if model.id == selectedID {
            if modelLoaded { return "In memory" }
            if state == .downloading { return "Downloading…" }
            if worker.processID != nil { return "Loading…" }
        }
        return model.installed ? "Downloaded" : "Not downloaded"
    }
    func offload() {
        suspend()
        transcript = ""
        state = selectedModel?.installed == true ? .ready : .needsModel
        message = DictationStrings.text("offloaded")
    }
    func download() {
        guard downloadTask == nil, let model = selectedModel, !active else { return }
        suspend(); state = .downloading; message = DictationStrings.text("downloading"); downloadProgress = 0
        downloadStatus = "Connecting…"
        downloadSampleTime = ProcessInfo.processInfo.systemUptime
        downloadSampleBytes = 0; downloadSpeed = 0
        let current = token
        downloadTask = Task { @MainActor in
            do {
                try await model.download { progress in
                    DispatchQueue.main.async { if self.token == current, self.state == .downloading { self.updateDownload(progress) } }
                }
                guard !Task.isCancelled, token == current else { return }
                downloadTask = nil; state = .needsModel; syncWithPreferences()
            } catch {
                guard token == current else { return }
                downloadTask = nil; fail("failed")
            }
        }
    }
    private func updateDownload(_ progress: DictationModel.DownloadProgress) {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - downloadSampleTime
        let added = max(0, progress.received - downloadSampleBytes)
        if elapsed >= 0.2, added > 0 {
            let measured = Double(added) / elapsed
            downloadSpeed = downloadSpeed == 0 ? measured : downloadSpeed * 0.65 + measured * 0.35
            downloadSampleTime = now; downloadSampleBytes = progress.received
        }
        downloadProgress = min(1, Double(progress.received) / Double(max(1, progress.total)))
        let received = ByteCountFormatter.string(fromByteCount: progress.received, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: progress.total, countStyle: .file)
        if progress.verifying {
            downloadStatus = "\(received) / \(total) · Verifying files…"
            // Exclude verification time from the next network speed sample.
            downloadSampleTime = now; downloadSampleBytes = progress.received
        } else if downloadSpeed > 0 {
            let rate = ByteCountFormatter.string(fromByteCount: Int64(downloadSpeed), countStyle: .file)
            let seconds = Int(ceil(Double(max(0, progress.total - progress.received)) / downloadSpeed))
            let estimate = seconds < 60 ? "\(max(1, seconds)) sec" : "\((seconds + 59) / 60) min"
            downloadStatus = "\(received) / \(total) · \(rate)/s · ~\(estimate) remaining"
        } else { downloadStatus = "\(received) / \(total) · Estimating speed…" }
    }
    func cancelDownload() { downloadTask?.cancel(); downloadTask = nil; suspend(); syncWithPreferences() }
    func removeModel() {
        guard let model = selectedModel else { return }
        suspend()
        do {
            try FileManager.default.removeItem(at: model.directory)
            downloadProgress = 0; downloadStatus = ""
            selectedID = ""
            UserDefaults.standard.set("", forKey: DefaultsKey.dictationModel)
            state = .needsModel; message = DictationStrings.text("chooseModel")
        }
        catch { fail("failed") }
    }
    private func load() {
        guard enabled, let model = selectedModel, model.installed else { return }
        do { try worker.launch(model: model); armTimeout(loading: true) } catch { fail("failed") }
    }
    private var toggleMode: Bool { UserDefaults.standard.bool(forKey: DefaultsKey.dictationToggleMode) }
    private func triggerPressed(_ source: String) {
        guard heldTrigger == nil, enabled, !ShortcutCapture.isCapturing else { return }
        heldTrigger = source
        if toggleMode {
            if source != "modifier" { toggle() }
        } else if [.ready, .review, .permissionRequired, .failed].contains(state) {
            toggle()
            if state == .recording { heldTrigger = source }
        }
    }
    private func triggerReleased(_ source: String) {
        guard heldTrigger == source else { return }
        heldTrigger = nil
        if !toggleMode, state == .recording { finish() }
    }
    private func cancelModifierChord() {
        guard heldTrigger == "modifier", !toggleMode else { return }
        heldTrigger = nil
        if state == .recording { cancel() }
    }
    func toggle() {
        if state == .failed { cancel() }
        if state == .review { state = .ready }
        if state == .permissionRequired {
            if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized { cancel() }
            else { showHUD(); return }
        }
        if state == .loading || state == .processing { cancel(); return }
        if state == .recording { finish(); return }
        guard state == .ready, enabled, SessionActivity.shared.isActive else { return }
        targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        localTextTarget = targetPID == getpid() ? NSApp.keyWindow?.firstResponder as? NSTextView : nil
        targetElement = focusedElement()
        targetWindow = focusedElement(attribute: kAXFocusedWindowAttribute)
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized {
            prepareRecording()
        } else {
            state = .permissionRequired
            message = DictationStrings.text("microphoneReason")
            showHUD()
        }
    }
    func requestMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            let current = token
            Permissions.shared.requestMicrophone { [weak self] allowed in
                guard let self, self.token == current else { return }
                if allowed {
                    if self.state == .permissionRequired { self.cancel() }
                    self.message = DictationStrings.text("permissionReady")
                } else {
                    self.message = DictationStrings.text("permission")
                }
            }
        case .authorized:
            if state == .permissionRequired { cancel() }
        default: Permissions.shared.openMicrophoneSettings()
        }
    }
    private func prepareRecording() {
        guard enabled, state == .ready else { return }
        // Capture immediately, including the first utterance while the model loads.
        begin()
        if state == .recording, !modelLoaded { load() }
    }
    private func begin() {
        guard state == .ready, enabled else { return }
        do {
            token = UUID()
            message = DictationStrings.text("warmup")
            try capture.start(deviceUID: microphoneID)
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("vorssaint-dictation-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            recordingFolder = folder
            transcript = ""; requestWasFinal = false; previewAt = Date(); previewCompletedAt = .distantPast
            capture.begin(limitMinutes: UserDefaults.standard.object(forKey: DefaultsKey.dictationRecordingLimitMinutes) as? Int ?? 5); state = .recording; message = DictationStrings.text("listening")
            let started = ProcessInfo.processInfo.systemUptime
            recordingStartedAt = started
            captureAttemptAt = started
            captureRestarted = false
            playStartSound()
            showHUD()
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.level = self.capture.level
                if self.capture.count == 0, ProcessInfo.processInfo.systemUptime - self.captureAttemptAt >= 1.5 {
                    guard !self.captureRestarted else { self.fail("captureUnavailable"); return }
                    self.captureRestarted = true
                    do {
                        try self.capture.restart(deviceUID: self.microphoneID)
                        self.capture.begin(limitMinutes: UserDefaults.standard.object(forKey: DefaultsKey.dictationRecordingLimitMinutes) as? Int ?? 5)
                        self.captureAttemptAt = ProcessInfo.processInfo.systemUptime
                    } catch { self.fail("captureUnavailable") }
                    return
                }
                if self.capture.reachedLimit { self.finish() }
                else if self.streaming, self.modelLoaded, self.requestID == nil, Date().timeIntervalSince(self.previewAt) >= 0.65,
                        Date().timeIntervalSince(self.previewCompletedAt) >= 0.15,
                        self.capture.count >= 6_400 {
                    self.previewAt = Date(); self.requestTranscription()
                }
            }
        } catch { fail("failed") }
    }
    func finish() {
        guard state == .recording else { return }
        capture.end()
        Self.logger.notice("Recording stopped: captured samples=\(self.capture.count)")
        // Ignore presses shorter than 400 ms at 16 kHz before decoding.
        // Keep an already loaded worker available for the next recording.
        if capture.count < 6_400 {
            // A long press with no buffers is a capture failure, not an
            // accidental click. Never silently discard a real recording attempt.
            if let started = recordingStartedAt, ProcessInfo.processInfo.systemUptime - started >= 0.4 {
                fail("captureUnavailable")
                return
            }
            if modelLoaded {
                cleanupRecording(); heldTrigger = nil; transcript = ""
                state = .ready; message = DictationStrings.text("ready")
            } else { cancel() }
            return
        }
        timer?.invalidate(); timer = nil; capture.end(); mute.restore()
        playStopSound()
        state = .processing; message = DictationStrings.text("processingStatus"); level = 0
        if !keepReady { capture.pause() }
        if modelLoaded, requestID == nil { requestTranscription() }
        else if !modelLoaded { message = DictationStrings.text("loading") }
    }
    private func requestTranscription() {
        guard let folder = recordingFolder, capture.count > 0 else { cancel(); showInsertionIssue("empty"); return }
        let id = UUID().uuidString, path = folder.appendingPathComponent(UUID().uuidString + ".wav")
        do {
            try capture.snapshot(to: path)
            requestID = id; requestFile = path; requestWasFinal = state == .processing
            try worker.transcribe(path, id: id); armTimeout()
        } catch { fail("failed") }
    }
    private func receive(_ reply: DictationWorker.Reply) {
        if reply.id == "ready" {
            timeout?.cancel()
            guard reply.error == nil else { fail("failed"); message += " " + (reply.error ?? ""); return }
            modelLoaded = true
            if state == .processing {
                message = DictationStrings.text("processingStatus")
                requestTranscription()
            } else if state == .recording { message = DictationStrings.text("listening") }
            return
        }
        if reply.id == "exit" { fail("failed"); return }
        guard reply.id == requestID else { return }
        timeout?.cancel(); requestID = nil; previewCompletedAt = Date()
        if let requestFile { try? FileManager.default.removeItem(at: requestFile) }; requestFile = nil
        guard reply.error == nil else { fail("failed"); message += " " + (reply.error ?? ""); return }
        transcript = (reply.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if state == .processing {
            if !requestWasFinal {
                // A preview may have been in flight when Stop was pressed. Always
                // decode a final snapshot that includes the end of the utterance.
                requestTranscription(); return
            }
            complete()
        }
    }
    private func complete() {
        let text = transcript
        if !text.isEmpty { lastTranscript = text }
        cleanupRecording()
        state = .ready
        guard !text.isEmpty else { showInsertionIssue("empty"); return }
        // Trying dictation from a settings button has no insertion target.
        // Sending Command-V there produces the system's invalid-action sound.
        // Keep the result in Last transcription without touching the clipboard.
        if targetPID == getpid(), localTextTarget?.isEditable != true {
            message = DictationStrings.text("finished")
            return
        }
        guard AXIsProcessTrusted() else { showInsertionIssue("accessibility"); return }
        guard targetStillFocused() else { showInsertionIssue("focusChanged"); return }
        let autoSend = UserDefaults.standard.bool(forKey: DefaultsKey.dictationAutoSend)
        let current = token
        let started = paste.paste(text, shouldPostShortcut: { [weak self] in self?.token == current && self?.targetStillFocused() == true }, didPostShortcut: { [weak self] in
            guard let self, self.token == current else { return }
            self.message = DictationStrings.text("finished")
            if autoSend {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    guard self.token == current, self.targetStillFocused() else { return }
                    let down = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true)
                    let up = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: false)
                    down?.post(tap: .cghidEventTap); up?.post(tap: .cghidEventTap)
                }
            }
        }, didFail: { [weak self] in
            guard let self, self.token == current else { return }
            self.showInsertionIssue("insertFailed")
        })
        if !started { showInsertionIssue("insertFailed") }
    }
    private func showInsertionIssue(_ key: String) {
        reviewDismissal?.cancel(); reviewDismissal = nil
        state = .review; message = DictationStrings.text(key); showHUD()
        guard key == "empty" else { return }
        let current = token
        let dismissal = DispatchWorkItem { [weak self] in
            guard let self, self.token == current, self.state == .review else { return }
            self.hideHUD()
            self.state = .ready
            self.message = DictationStrings.text(self.modelLoaded ? "ready" : "onDemand")
        }
        reviewDismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: dismissal)
    }
    private func focusedElement(attribute: String = kAXFocusedUIElementAttribute) -> AXUIElement? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private func targetStillFocused() -> Bool {
        guard let targetPID, targetPID == NSWorkspace.shared.frontmostApplication?.processIdentifier else { return false }
        if targetPID == getpid() {
            guard let localTextTarget, localTextTarget.isEditable,
                  NSApp.keyWindow?.firstResponder === localTextTarget else { return false }
        }
        if let targetWindow, let current = focusedElement(attribute: kAXFocusedWindowAttribute), !CFEqual(targetWindow, current) { return false }
        // Some apps accept keyboard paste without exposing an AX text element.
        // Missing AX metadata must not disable ordinary Command-V insertion.
        if let targetElement, let current = focusedElement() { return CFEqual(targetElement, current) }
        return true
    }

    func copyLastTranscript() {
        guard !lastTranscript.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastTranscript, forType: .string)
    }
    func clearLastTranscript() { lastTranscript = "" }
    func copyTranscript() {
        guard !transcript.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(transcript, forType: .string)
        message = DictationStrings.text("copied")
    }
    func cancel() {
        suspend()
        transcript = ""
        state = selectedModel?.installed == true ? .ready : .needsModel
        message = DictationStrings.text("onDemand")
    }
    func previewSounds() {
        guard !active else { return }
        sounds.play("preview")
    }
    private func playStartSound() {
        pendingStartCue?.cancel(); sounds.stop(); startCuePlayed = false
        let current = token
        let muteAfterCue = { [weak self] in
            guard let self, self.token == current, self.state == .recording,
                  (UserDefaults.standard.bool(forKey: DefaultsKey.dictationMuteOutput) ||
                   UserDefaults.standard.bool(forKey: DefaultsKey.dictationLowerOutput)) else { return }
            self.mute.begin()
        }
        guard UserDefaults.standard.bool(forKey: DefaultsKey.dictationSounds) else { muteAfterCue(); return }
        // Ignore a modifier that immediately becomes an ordinary keyboard chord.
        // Capture begins immediately; only the cue waits for this brief debounce.
        let cue = DispatchWorkItem { [weak self] in
            guard let self, self.token == current, self.state == .recording else { return }
            self.pendingStartCue = nil
            self.startCuePlayed = self.sounds.play("start", completion: muteAfterCue)
        }
        pendingStartCue = cue
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: cue)
    }
    private func playStopSound() {
        pendingStartCue?.cancel(); pendingStartCue = nil
        sounds.stop()
        let played = startCuePlayed; startCuePlayed = false
        if played, UserDefaults.standard.bool(forKey: DefaultsKey.dictationSounds) { sounds.play("stop") }
    }
    private func cleanupRecording() {
        let wasRecording = state == .recording
        timer?.invalidate(); timer = nil; timeout?.cancel(); timeout = nil
        capture.end(); capture.clear()
        recordingStartedAt = nil
        if !keepReady { capture.stop() }
        mute.restore()
        if wasRecording { playStopSound() }
        hideHUD(); level = 0
        requestID = nil; requestFile = nil; requestWasFinal = false
        if let recordingFolder { try? FileManager.default.removeItem(at: recordingFolder) }; recordingFolder = nil
    }
    private func suspend() {
        downloadTask?.cancel(); downloadTask = nil
        token = UUID(); heldTrigger = nil; modelLoaded = false
        cleanupRecording(); capture.stop(); worker.stop(); state = .disabled
    }
    func stop() {
        downloadTask?.cancel(); downloadTask = nil; suspend(); mute.restoreImmediately(); hotkey.unregister(); stopMouse()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; observers = []
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }; configurationObserver = nil
        transcript = ""; message = ""
    }
    private func fail(_ key: String) {
        Self.logger.error("Dictation failed: \(key, privacy: .public)")
        let wasVisible = panel != nil
        heldTrigger = nil; modelLoaded = false
        cleanupRecording(); capture.stop(); worker.stop(); state = .failed; message = DictationStrings.text(key)
        if wasVisible {
            showHUD()
            let current = token
            let dismissal = DispatchWorkItem { [weak self] in
                guard let self, self.token == current, self.state == .failed else { return }
                self.hideHUD()
            }
            reviewDismissal = dismissal
            DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: dismissal)
        }
    }
    private func armTimeout(loading: Bool = false) {
        timeout?.cancel()
        let key = loading ? "loadingTimeout" : "transcriptionTimeout"
        let task = DispatchWorkItem { [weak self] in self?.fail(key) }
        let seconds: Double = loading && ["bark-clean", "phonon-english"].contains(selectedModel?.id ?? "") ? 600 : 120
        timeout = task; DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: task)
    }
    private func hideHUD() {
        reviewDismissal?.cancel(); reviewDismissal = nil
        guard let closing = panel else { return }
        panel = nil
        closing.ignoresMouseEvents = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.08
            closing.animator().alphaValue = 0
        } completionHandler: { closing.orderOut(nil) }
    }
    private func showHUD() {
        if panel != nil { return }
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let width = min(streaming ? 440.0 : 300.0, screen.visibleFrame.width - 32)
        let panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: streaming ? 158 : 128), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: DictationHUD(service: self))
        panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - width / 2, y: screen.visibleFrame.minY + 36))
        self.panel = panel
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.10
            panel.animator().alphaValue = 1
        }
    }
    private func syncMouse() {
        let preferences = UserDefaults.standard
        let selected = Set((preferences.string(forKey: DefaultsKey.dictationMouseButtons) ?? "").split(separator: ",").compactMap { Int64($0) }.filter { (2...4).contains($0) })
        let modifier = DictationShortcut.modifier(preferences.string(forKey: DefaultsKey.dictationShortcut) ?? "")
        let needsTap = !selected.isEmpty || modifier != nil
        guard needsTap else { stopMouse(); triggerWarning = ""; return }
        guard AXIsProcessTrusted() else {
            stopMouse(); triggerWarning = DictationStrings.text("triggerPermission"); return
        }
        if selected == mouseButtons, modifier == modifierKey, let mouseTap {
            CGEvent.tapEnable(tap: mouseTap, enable: true)
            triggerWarning = ""
            return
        }
        stopMouse(); mouseButtons = selected; modifierKey = modifier
        var types: [CGEventType] = [.otherMouseDown, .otherMouseUp, .otherMouseDragged]
        if modifier != nil { types += [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown] }
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return Unmanaged<DictationService>.fromOpaque(context).takeUnretainedValue().handleTrigger(type, event: event)
        }, userInfo: context), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            triggerWarning = DictationStrings.text("triggerFailed")
            return
        }
        mouseTap = tap; mouseSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        triggerWarning = ""
    }
    private func handleTrigger(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if heldTrigger != nil { cancel() }
            modifierDown = false; modifierSolo = false; ownedMouseButtons.removeAll()
            if let mouseTap { CGEvent.tapEnable(tap: mouseTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        // Finish the mouse gesture we accepted even if loading/recognition changed state.
        if type == .otherMouseUp, ownedMouseButtons.contains(button) {
            ownedMouseButtons.remove(button)
            if enabled && SessionActivity.shared.isActive && !ShortcutCapture.isCapturing {
                DispatchQueue.main.async { self.triggerReleased("mouse:\(button)") }
            }
            return nil
        }
        if type == .otherMouseDragged, ownedMouseButtons.contains(button) { return nil }
        guard enabled, SessionActivity.shared.isActive, !ShortcutCapture.isCapturing else {
            modifierDown = false; modifierSolo = false
            return Unmanaged.passUnretained(event)
        }
        if let modifierKey, type == .flagsChanged {
            if event.getIntegerValueField(.keyboardEventKeycode) == modifierKey {
                let down = DictationShortcut.isDown(modifierKey, flags: event.flags.rawValue)
                if down && !modifierDown {
                    modifierSolo = DictationShortcut.isSolo(modifierKey, flags: event.flags.rawValue)
                    if modifierSolo { DispatchQueue.main.async { self.triggerPressed("modifier") } }
                } else if !down && modifierDown {
                    let solo = modifierSolo
                    modifierSolo = false
                    DispatchQueue.main.async {
                        if solo, self.toggleMode { self.toggle() }
                        self.triggerReleased("modifier")
                    }
                }
                modifierDown = down
            } else if modifierDown {
                modifierSolo = false
                DispatchQueue.main.async { self.cancelModifierChord() }
            }
            // Preserve normal modifier-key combinations in the foreground app.
            return Unmanaged.passUnretained(event)
        }
        if modifierDown && [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown].contains(type) {
            modifierSolo = false
            DispatchQueue.main.async { self.cancelModifierChord() }
        }
        if type == .otherMouseDown,
           mouseButtons.contains(button),
           [.ready, .recording, .loading, .processing, .permissionRequired, .review, .failed].contains(state) {
            ownedMouseButtons.insert(button)
            DispatchQueue.main.async { self.triggerPressed("mouse:\(button)") }
            return nil
        }
        return Unmanaged.passUnretained(event)
    }
    private func stopMouse() {
        if let mouseTap { CGEvent.tapEnable(tap: mouseTap, enable: false); CFMachPortInvalidate(mouseTap) }
        if let mouseSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), mouseSource, .commonModes) }
        mouseTap = nil; mouseSource = nil; mouseButtons.removeAll()
        modifierKey = nil; modifierDown = false; modifierSolo = false; ownedMouseButtons.removeAll()
    }
}

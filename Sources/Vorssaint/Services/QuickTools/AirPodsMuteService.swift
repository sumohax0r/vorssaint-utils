// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AppKit
import AVFoundation
import CoreAudio
import os

/// Apple's accessory mute API needs active input I/O. This opt-in session uses
/// a non-Bluetooth microphone and discards every buffer; it never saves audio.
final class AirPodsMuteService: NSObject, ObservableObject, @unchecked Sendable {
    static let shared = AirPodsMuteService()
    @Published private(set) var status = "Off"
    private let queue = DispatchQueue(label: "com.vorssaint.airpods-mute")
    private let input = AirPodsMuteInput()
    private let activity = AirPodsMicrophoneActivity() // main confined
    private var registered = false // queue confined
    private var muteObserver: NSObjectProtocol? // queue confined
    private static let logger = Logger(subsystem: "com.vorssaint.utils", category: "AirPodsMute")
    private let mirrorLock = NSLock()
    private var mirroring = false
    private var observers: [NSObjectProtocol] = []
    private var generation = UUID() // main confined

    private override init() {
        super.init()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.sync() })
        }
        SessionActivity.shared.onChange { [weak self] _ in self?.sync() }

    }
    func requestEnable() {
        Permissions.shared.requestMicrophone { [weak self] _ in self?.sync() }
    }
    func sync() {
        guard AppFeature.micMute.isAvailable,
              UserDefaults.standard.bool(forKey: DefaultsKey.micMuteAirPodsEnabled),
              SessionActivity.shared.isActive else { stop(); return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            stop(message: "Microphone permission is required for AirPods controls."); return
        }
        activity.start { [weak self] in
            guard let self else { return }
            Self.logger.info("External microphone activity changed: active=\(self.activity.isActive)")
            self.sync()
        }
        guard activity.isActive else {
            suspendCapture(message: "Waiting for another app to use a microphone. AirPods keep their normal media controls while idle.")
            return
        }
        let competing = Set(["com.apple.FaceTime", "com.apple.Phone", "com.microsoft.teams2", "com.microsoft.teams", "net.whatsapp.WhatsApp"])
        if let app = NSWorkspace.shared.runningApplications.first(where: { competing.contains($0.bundleIdentifier ?? "") }) {
            suspendCapture(message: "Paused while \(app.localizedName ?? "another calling app") manages AirPods controls."); return
        }
        let current = UUID(); generation = current
        let muted = MicMuteService.shared.isMuted
        queue.async {
            do {
                if !self.registered {
                    let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
                    guard let device = devices.first(where: { UInt32(bitPattern: $0.transportType) == kAudioDeviceTransportTypeBuiltIn }) else {
                        self.publish("A built-in microphone is required to keep AirPods playback unchanged.", generation: current)
                        return
                    }
                    try AVAudioApplication.shared.setInputMuteStateChangeHandler { [weak self] muted in
                        guard let self else { return false }
                        if self.mirrorLock.withLock({ self.mirroring }) { return true }
                        Self.logger.info("Received mute request: muted=\(muted)")
                        // The hardware API needs the actual result, not an optimistic
                        // acknowledgement before a background mute has completed.
                        let applied = Thread.isMainThread
                            ? MicMuteService.shared.applyAirPodsMute(muted)
                            : DispatchQueue.main.sync { MicMuteService.shared.applyAirPodsMute(muted) }
                        Self.logger.info("Hardware mute request applied=\(applied)")
                        return applied
                    }
                    self.registered = true
                    // Register after the handler: earlier observation has been
                    // reported to prevent delivery of accessory mute gestures.
                    self.muteObserver = NotificationCenter.default.addObserver(
                        forName: AVAudioApplication.inputMuteStateChangeNotification,
                        object: nil, queue: .main
                    ) { notification in
                        let muted = (notification.userInfo?[AVAudioApplication.muteStateKey] as? NSNumber)?.boolValue ?? false
                        Self.logger.info("System mute state notification: muted=\(muted)")
                    }
                    self.setSystemState(muted)
                    try self.input.start(deviceUID: device.uniqueID)
                    Self.logger.info("Mute handler registered before notification observer; direct input I/O running")
                }
                self.publish("Ready · press an AirPod stem to mute or unmute all microphones.", generation: current)
            } catch {
                Self.logger.error("AirPods controls startup failed: \(error.localizedDescription, privacy: .public)")
                self.teardown()
                self.publish("AirPods controls could not start. Toggle to retry.", generation: current)
            }
        }
    }
    func mirror(_ muted: Bool) {
        queue.async { if self.registered { self.setSystemState(muted) } }
    }
    private func setSystemState(_ muted: Bool) {
        guard AVAudioApplication.shared.isInputMuted != muted else { return }
        mirrorLock.withLock { mirroring = true }
        defer { mirrorLock.withLock { mirroring = false } }
        try? AVAudioApplication.shared.setInputMuted(muted)
    }
    func stop(message: String = "Off") {
        activity.stop()
        suspendCapture(message: message)
    }
    private func suspendCapture(message: String) {
        generation = UUID(); status = message
        queue.async { self.teardown() }
    }
    private func teardown() {
        if registered { try? AVAudioApplication.shared.setInputMuteStateChangeHandler(nil) }
        if registered { setSystemState(false) }
        registered = false
        if let muteObserver { NotificationCenter.default.removeObserver(muteObserver) }
        muteObserver = nil
        input.stop()
    }
    private func publish(_ text: String, generation: UUID) {
        DispatchQueue.main.async { if self.generation == generation { self.status = text } }
    }
}

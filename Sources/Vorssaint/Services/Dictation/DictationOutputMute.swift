// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AudioToolbox
import CoreAudio
import Foundation
import OSLog

/// Fade one device-wide control, preserving stereo balance and the original output.
final class DictationOutputMute {
    private static let logger = Logger(subsystem: "com.vorssaint.utils", category: "DictationVolume")
    private var device: AudioDeviceID?
    private struct Volume {
        let device: AudioDeviceID
        let selector: AudioObjectPropertySelector
        let original: Float32
        let bluetooth: Bool
        var last: Float32
        var previous: Float32
        var writtenAt: TimeInterval = 0
    }
    private var volumes: [Volume] = []
    private var timer: Timer?
    private var restoring = false
    private var settling: DispatchWorkItem?
    private var settlingEpoch = 0
    private var softwareGain: Float?
    private var softwareDevice: AudioDeviceID?
    private var softwareOriginal: Float32 = 1
    func begin() {
        settling?.cancel(); settling = nil
        settlingEpoch += 1
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var id: AudioDeviceID = 0, size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr else { return }
        if UserDefaults.standard.bool(forKey: DefaultsKey.dictationMuteOutput) {
            restoreImmediately()
            if read(id) == 0, write(id, value: 1) { device = id }
            return
        }
        if isBluetooth(id), UserDefaults.standard.bool(forKey: DefaultsKey.dictationSoftwareBluetooth),
           AppFeature.mixer.isAvailable {
            if softwareDevice != id {
                let original = volumes.first(where: { $0.device == id })?.original
                    ?? volume(id, kAudioDevicePropertyVolumeScalar)
                    ?? volume(id, kAudioHardwareServiceDeviceProperty_VirtualMainVolume) ?? 1
                restoreImmediately()
                softwareDevice = id; softwareOriginal = original; softwareGain = 1
            }
            let raw = UserDefaults.standard.double(forKey: DefaultsKey.dictationOutputLevel)
            let level = Float32(raw.isFinite ? min(1, max(0, raw)) : 0.1)
            let ratio = softwareOriginal > 0 ? min(1, level / softwareOriginal) : 1
            restoring = false
            fadeSoftware(to: MixerRoutingSupport.gain(forVolume: Double(ratio)))
            return
        }
        if softwareGain != nil { restoreImmediately() }
        if volumes.first?.device != id { restoreImmediately() }
        if volumes.isEmpty {
            // Prefer the native master used by system volume controls. A
            // virtual master may fan out writes behind the driver's interface.
            // Never drive individual left/right controls.
            let selectors: [AudioObjectPropertySelector] = [
                kAudioDevicePropertyVolumeScalar,
                kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            ]
            for selector in selectors {
                var property = volumeAddress(selector)
                var settable: DarwinBoolean = false
                guard AudioObjectIsPropertySettable(id, &property, &settable) == noErr,
                      settable.boolValue, let value = volume(id, selector) else { continue }
                volumes.append(Volume(device: id, selector: selector, original: value,
                                      bluetooth: isBluetooth(id), last: value, previous: value))
                break
            }
        }
        fade(restoring: false)
    }
    func restore() {
        if softwareGain != nil {
            if !restoring { restoring = true; fadeSoftware(to: 1) }
            return
        }
        if let device, read(device) == 1 { _ = write(device, value: 0) }
        device = nil
        if !restoring { fade(restoring: true) }
    }
    func restoreImmediately() {
        settling?.cancel(); settling = nil
        settlingEpoch += 1
        timer?.invalidate(); timer = nil
        if softwareGain != nil {
            AppVolumeMixer.shared.setDictationOutputGain(1)
            softwareGain = nil; softwareDevice = nil
        }
        if let device, read(device) == 1 { _ = write(device, value: 0) }
        device = nil
        for entry in volumes where owns(entry) {
            _ = setVolume(entry.device, entry.selector, entry.original)
        }
        volumes.removeAll(); restoring = false
    }
    private func fadeSoftware(to target: Float) {
        timer?.invalidate(); timer = nil
        let raw = UserDefaults.standard.double(forKey: DefaultsKey.dictationOutputFade)
        let duration = raw.isFinite ? min(3, max(0, raw)) : 0.3
        let start = softwareGain ?? 1
        let started = ProcessInfo.processInfo.systemUptime
        let tick: () -> Void = { [weak self] in
            guard let self else { return }
            let progress = duration == 0 ? 1 : min(1, (ProcessInfo.processInfo.systemUptime - started) / duration)
            let eased = Float(progress * progress * (3 - 2 * progress))
            let gain = start + (target - start) * eased
            self.softwareGain = gain
            AppVolumeMixer.shared.setDictationOutputGain(gain)
            if progress >= 1 {
                self.timer?.invalidate(); self.timer = nil
                if target == 1 {
                    self.softwareGain = nil; self.softwareDevice = nil; self.restoring = false
                }
                Self.logger.notice("Software volume transition completed: gain=\(target)")
            }
        }
        if duration == 0 { tick() }
        else {
            let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { _ in tick() }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    private func owns(_ entry: Volume) -> Bool {
        guard let current = volume(entry.device, entry.selector) else { return false }
        if abs(current - entry.last) < 0.005 { return true }
        // Bluetooth may acknowledge a requested level before the hardware
        // reports it. Accept the previous level briefly; do not mistake that
        // delayed acknowledgement for a user's change and abandon restoration.
        return entry.bluetooth && ProcessInfo.processInfo.systemUptime - entry.writtenAt < 1
            && abs(current - entry.previous) < 0.005
    }
    private func fade(restoring: Bool) {
        timer?.invalidate(); timer = nil
        volumes.removeAll { !owns($0) }
        self.restoring = restoring
        guard !volumes.isEmpty else { return }
        let preferences = UserDefaults.standard
        let rawDuration = preferences.double(forKey: DefaultsKey.dictationOutputFade)
        // Bluetooth volume is a hardware command, not a software gain ramp.
        // Rapid commands can reach the earbuds at different times. Send a
        // single native-master change in each direction instead.
        let duration = volumes.contains(where: \.bluetooth) ? 0 :
            (rawDuration.isFinite ? min(3, max(0, rawDuration)) : 0.3)
        let rawLevel = preferences.double(forKey: DefaultsKey.dictationOutputLevel)
        let level = Float32(rawLevel.isFinite ? min(1, max(0, rawLevel)) : 0.1)
        let starts = volumes.map(\.last)
        let started = ProcessInfo.processInfo.systemUptime
        let tick: () -> Void = { [weak self] in
            guard let self else { return }
            let progress = duration == 0 ? 1 : min(1, (ProcessInfo.processInfo.systemUptime - started) / duration)
            let eased = Float32(progress * progress * (3 - 2 * progress))
            for index in self.volumes.indices {
                let entry = self.volumes[index]
                guard self.owns(entry) else { continue }
                let target = restoring ? entry.original : min(entry.original, level)
                let value = starts[index] + (target - starts[index]) * eased
                let previous = self.volume(entry.device, entry.selector) ?? entry.last
                if self.setVolume(entry.device, entry.selector, value) {
                    Self.logger.notice("Volume command: bluetooth=\(entry.bluetooth) restoring=\(restoring) level=\(value)")
                    self.volumes[index].previous = previous
                    self.volumes[index].last = value
                    self.volumes[index].writtenAt = ProcessInfo.processInfo.systemUptime
                }
            }
            if progress >= 1 {
                self.timer?.invalidate(); self.timer = nil
                if restoring {
                    let restored = self.volumes
                    if restored.contains(where: \.bluetooth) {
                        // Retain the original level during settling, so a
                        // rapid new recording cannot snapshot a lowered level.
                        self.verifyRestoration(restored)
                    } else { self.volumes.removeAll(); self.restoring = false }
                }
            }
        }
        if duration == 0 { tick() }
        else {
            let steps = min(4, max(1, Int(ceil(duration / 0.15))))
            let timer = Timer(timeInterval: duration / Double(steps), repeats: true) { _ in tick() }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    private func isBluetooth(_ id: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var transport: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }
    private func verifyRestoration(_ entries: [Volume]) {
        settling?.cancel()
        settlingEpoch += 1
        let epoch = settlingEpoch
        let check = DispatchWorkItem { [weak self] in
            guard let self, self.settlingEpoch == epoch else { return }
            self.settling = nil
            for entry in entries where entry.bluetooth && self.owns(entry) {
                guard let current = self.volume(entry.device, entry.selector),
                      abs(current - entry.original) >= 0.005 else { continue }
                // Reassert through the native master after Bluetooth commands
                // settle, but do not overwrite a subsequent user volume change.
                _ = self.setVolume(entry.device, entry.selector, entry.original)
                Self.logger.notice("Correcting delayed Bluetooth restoration")
            }
            self.volumes.removeAll(); self.restoring = false
        }
        settling = check
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: check)
    }
    private func volumeAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }
    private func volume(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> Float32? {
        var address = volumeAddress(selector)
        var value: Float32 = 0, size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
    private func setVolume(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector, _ value: Float32) -> Bool {
        var address = volumeAddress(selector), value = value
        return AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }
    private func read(_ id: AudioDeviceID) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0, size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
    private func write(_ id: AudioDeviceID, value: UInt32) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var value = value
        return AudioObjectSetPropertyData(id, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }
}

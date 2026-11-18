// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import CoreAudio
import Foundation

/// Watches input activity without opening an audio device or sampling audio.
/// All state and listener delivery are confined to the main queue.
final class AirPodsMicrophoneActivity {
    private(set) var isActive = false
    private var watching = false
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var changed: (() -> Void)?
    private var pending: DispatchWorkItem?
    private var fallback: Timer?

    func start(changed: @escaping () -> Void) {
        guard !watching else { return }
        watching = true
        self.changed = changed
        refresh()
        // Some macOS versions accept running-input listeners without delivering
        // changes. A bounded metadata read also catches the initial HAL cache
        // settling after startup. It never opens a device or samples audio.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.watching else { return }
            let previous = self.isActive
            self.refresh(rebuildListeners: false)
            if previous != self.isActive { self.changed?() }
        }
        timer.tolerance = 0.2
        fallback = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        watching = false
        fallback?.invalidate(); fallback = nil
        pending?.cancel(); pending = nil
        removeListeners()
        changed = nil
        isActive = false
    }

    private func removeListeners() {
        for (object, var address, block) in listeners {
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, block)
        }
        listeners.removeAll()
    }

    private func listen(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) {
        var address = Self.address(selector)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.scheduleRefresh()
        }
        if AudioObjectAddPropertyListenerBlock(object, &address, .main, block) == noErr {
            listeners.append((object, address, block))
        }
    }

    private func scheduleRefresh() {
        guard watching, pending == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pending = nil
            guard self.watching else { return }
            let previous = self.isActive
            self.refresh()
            if previous != self.isActive { self.changed?() }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: item)
    }

    private func refresh(rebuildListeners: Bool = true) {
        if rebuildListeners { removeListeners() }
        let system = AudioObjectID(kAudioObjectSystemObject)
        if rebuildListeners { listen(system, kAudioHardwarePropertyProcessObjectList) }
        var address = Self.address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
            isActive = false; return
        }
        guard size >= MemoryLayout<AudioObjectID>.size else { isActive = false; return }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let result = processes.withUnsafeMutableBytes {
            AudioObjectGetPropertyData(system, &address, 0, nil, &size, $0.baseAddress!)
        }
        guard result == noErr else { isActive = false; return }
        var active = false
        for process in processes.prefix(Int(size) / MemoryLayout<AudioObjectID>.size) {
            var pid: pid_t = 0
            var pidSize = UInt32(MemoryLayout<pid_t>.size)
            var pidAddress = Self.address(kAudioProcessPropertyPID)
            guard AudioObjectGetPropertyData(process, &pidAddress, 0, nil, &pidSize, &pid) == noErr,
                  pid > 0, pid != getpid() else { continue }
            // Our helper must never keep itself alive through its own input.
            if rebuildListeners { listen(process, kAudioProcessPropertyIsRunningInput) }
            var running: UInt32 = 0
            var valueSize = UInt32(MemoryLayout<UInt32>.size)
            var runningAddress = Self.address(kAudioProcessPropertyIsRunningInput)
            if AudioObjectGetPropertyData(process, &runningAddress, 0, nil, &valueSize, &running) == noErr,
               running != 0 { active = true }
        }
        isActive = active
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                   mElement: kAudioObjectPropertyElementMain)
    }
}

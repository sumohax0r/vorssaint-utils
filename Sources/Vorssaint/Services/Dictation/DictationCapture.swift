// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AVFoundation
import AudioToolbox
import CoreAudio
import OSLog

final class DictationCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private static let logger = Logger(subsystem: "com.vorssaint.utils", category: "DictationCapture")
    struct Device: Identifiable { let id: String; let name: String; let objectID: AudioDeviceID }
    let session = AVCaptureSession()
    private var output = AVCaptureAudioDataOutput()
    private let sampleQueue = DispatchQueue(label: "com.vorssaint.dictation.capture")
    private let lock = NSLock()
    private var samples: [Float] = []
    private var recording = false
    private var loggedFormat = false
    private var amplitude: Float = 0
    private var sampleLimit = 16_000 * 60 * 5
    var reachedLimit: Bool { lock.lock(); defer { lock.unlock() }; return samples.count >= sampleLimit }
    var isRunning: Bool { session.isRunning }
    var level: Float { lock.lock(); defer { lock.unlock() }; return amplitude }
    var count: Int { lock.lock(); defer { lock.unlock() }; return samples.count }

    func start(deviceUID: String) throws {
        guard !session.isRunning else { return }
        let device = deviceUID.isEmpty ? AVCaptureDevice.default(for: .audio) : AVCaptureDevice(uniqueID: deviceUID)
        guard let device, device.hasMediaType(.audio) else { throw CocoaError(.fileNoSuchFile) }
        // A stopped session can retain stale device/format state after sleep
        // or an audio-service restart. Rebuild its graph on every cold start;
        // Keep microphone ready still reuses an already-running session.
        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            session.inputs.forEach { session.removeInput($0) }
            session.outputs.forEach { session.removeOutput($0) }
            output.setSampleBufferDelegate(nil, queue: nil)
            output = AVCaptureAudioDataOutput()
            guard session.canAddInput(input), session.canAddOutput(output) else {
                session.commitConfiguration()
                throw CocoaError(.featureUnsupported)
            }
            // Capture only the selected input; never create a default-device
            // aggregate that can briefly activate a Bluetooth headset mic.
            session.addInput(input)
            output.audioSettings = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 32,
                AVLinearPCMIsFloatKey: true,
                AVLinearPCMIsNonInterleaved: false
            ]
            output.setSampleBufferDelegate(self, queue: sampleQueue)
            session.addOutput(output)
            session.commitConfiguration()
        }
        session.startRunning()
        guard session.isRunning else { throw CocoaError(.featureUnsupported) }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        lock.lock()
        let logFormat = !loggedFormat
        loggedFormat = true
        lock.unlock()
        if logFormat, let description = CMSampleBufferGetFormatDescription(sampleBuffer),
           let format = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee {
            Self.logger.info("Capture format: rate=\(format.mSampleRate) channels=\(format.mChannelsPerFrame) bits=\(format.mBitsPerChannel) flags=\(format.mFormatFlags)")
        }
        let count = CMSampleBufferGetNumSamples(sampleBuffer)
        guard count > 0, count <= Int(Int32.max),
              let description = CMSampleBufferGetFormatDescription(sampleBuffer),
              let stream = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              stream.pointee.mSampleRate == 16_000, stream.pointee.mChannelsPerFrame == 1,
              stream.pointee.mFormatID == kAudioFormatLinearPCM,
              stream.pointee.mBitsPerChannel == 32,
              stream.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { return }
        buffer.frameLength = AVAudioFrameCount(count)
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(count), into: buffer.mutableAudioBufferList) == noErr,
              let channel = buffer.floatChannelData?[0] else { return }
        let values = UnsafeBufferPointer(start: channel, count: count)
        let rms = sqrt(values.reduce(Float(0)) { $0 + $1 * $1 } / Float(max(1, values.count)))
        lock.lock()
        // Normalize the visual meter in decibels, not linear sample amplitude.
        // Quiet speech otherwise moves less than one point in the compact HUD.
        // This affects only the display, never the audio sent to recognition.
        let decibels = 20 * log10(max(rms.isFinite ? rms : 0, 0.000_001))
        let normalized = min(1, max(0, (decibels + 60) / 42))
        let target = pow(normalized, 0.65)
        let seconds = Float(values.count) / 16_000
        let timeConstant: Float = target > amplitude ? 0.035 : 0.16
        let blend = 1 - exp(-seconds / timeConstant)
        amplitude += (target - amplitude) * blend
        if recording { samples.append(contentsOf: values.prefix(max(0, sampleLimit - samples.count))) }
        lock.unlock()
    }

    func begin(limitMinutes: Int) {
        lock.lock(); defer { lock.unlock() }
        let limit = max(1, limitMinutes).multipliedReportingOverflow(by: 16_000 * 60)
        sampleLimit = limit.overflow ? Int.max : limit.partialValue
        samples.removeAll(keepingCapacity: true); amplitude = 0; recording = true; loggedFormat = false
    }
    func end() { lock.lock(); recording = false; lock.unlock() }
    func clear() { lock.lock(); samples.removeAll(); amplitude = 0; lock.unlock() }
    func pause() {
        end()
        session.stopRunning()
        // Drain callbacks before another recording can reuse the sample buffer.
        sampleQueue.sync {}
    }
    func stop() { pause(); clear() }
    func restart(deviceUID: String) throws {
        stop()
        Self.logger.notice("Rebuilding stalled microphone capture")
        try start(deviceUID: deviceUID)
    }
    func snapshot(to url: URL) throws {
        lock.lock(); let copy = samples; lock.unlock()
        guard !copy.isEmpty,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000) else { throw CocoaError(.fileReadCorruptFile) }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        // Write bounded chunks, even when the user chooses a long recording limit.
        try copy.withUnsafeBufferPointer { values in
            for offset in stride(from: 0, to: copy.count, by: 16_000) {
                let count = min(16_000, copy.count - offset)
                buffer.frameLength = AVAudioFrameCount(count)
                buffer.floatChannelData![0].update(from: values.baseAddress! + offset, count: count)
                try file.write(from: buffer)
            }
        }
    }

    static func devices() -> [Device] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
            var bytes: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &bytes) == noErr, bytes > 0 else { return nil }
            func string(_ selector: AudioObjectPropertySelector) -> String? {
                var a = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                var value: CFString = "" as CFString
                var length = UInt32(MemoryLayout<CFString>.size)
                let result = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(id, &a, 0, nil, &length, $0) }
                guard result == noErr else { return nil }
                return value as String
            }
            guard let uid = string(kAudioDevicePropertyDeviceUID), let name = string(kAudioObjectPropertyName) else { return nil }
            return Device(id: uid, name: name, objectID: id)
        }
    }
}

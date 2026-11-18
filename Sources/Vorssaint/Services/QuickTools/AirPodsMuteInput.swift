// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AudioToolbox
import CoreAudio
import Foundation

/// Process-owned input I/O for AVAudioApplication accessory gesture routing.
/// No output bus, recording, transcription, or per-callback allocations.
final class AirPodsMuteInput {
    private var unit: AudioUnit?
    private var buffers: UnsafeMutableAudioBufferListPointer?
    private var capacity: UInt32 = 0

    func start(deviceUID: String) throws {
        guard unit == nil else { return }
        do {
            var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var uid = deviceUID as CFString
            var device: AudioDeviceID = 0
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            try check(withUnsafePointer(to: &uid) {
                AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                    UInt32(MemoryLayout<CFString>.size), $0, &size, &device)
            })
            guard device != 0 else { throw CocoaError(.fileNoSuchFile) }
            var description = AudioComponentDescription(componentType: kAudioUnitType_Output,
                componentSubType: kAudioUnitSubType_HALOutput, componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0, componentFlagsMask: 0)
            guard let component = AudioComponentFindNext(nil, &description) else { throw CocoaError(.featureUnsupported) }
            var created: AudioUnit?
            try check(AudioComponentInstanceNew(component, &created))
            guard let created else { throw CocoaError(.featureUnsupported) }
            unit = created
            var enabled: UInt32 = 1, disabled: UInt32 = 0
            try check(AudioUnitSetProperty(created, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enabled, 4))
            try check(AudioUnitSetProperty(created, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &disabled, 4))
            try check(AudioUnitSetProperty(created, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, 4))
            var hardware = AudioStreamBasicDescription()
            size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check(AudioUnitGetProperty(created, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 1, &hardware, &size))
            guard hardware.mSampleRate > 0, (1...32).contains(hardware.mChannelsPerFrame) else { throw CocoaError(.featureUnsupported) }
            var format = AudioStreamBasicDescription(mSampleRate: hardware.mSampleRate,
                mFormatID: kAudioFormatLinearPCM,
                mFormatFlags: kAudioFormatFlagsNativeFloatPacked | kAudioFormatFlagIsNonInterleaved,
                mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
                mChannelsPerFrame: hardware.mChannelsPerFrame, mBitsPerChannel: 32, mReserved: 0)
            try check(AudioUnitSetProperty(created, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &format, size))
            var callback = AURenderCallbackStruct(inputProc: { context, flags, time, _, frames, _ in
                return Unmanaged<AirPodsMuteInput>.fromOpaque(context).takeUnretainedValue().discard(flags: flags, time: time, frames: frames)
            }, inputProcRefCon: Unmanaged.passUnretained(self).toOpaque())
            try check(AudioUnitSetProperty(created, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 0,
                &callback, UInt32(MemoryLayout<AURenderCallbackStruct>.size)))
            try check(AudioUnitInitialize(created))
            var maximum: UInt32 = 0
            size = 4
            try check(AudioUnitGetProperty(created, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maximum, &size))
            guard maximum > 0, maximum <= 65_536 else { throw CocoaError(.featureUnsupported) }
            capacity = maximum
            let list = AudioBufferList.allocate(maximumBuffers: Int(format.mChannelsPerFrame))
            list.unsafeMutablePointer.pointee.mNumberBuffers = format.mChannelsPerFrame
            for i in 0..<list.count {
                list[i] = AudioBuffer(mNumberChannels: 1, mDataByteSize: maximum * 4,
                    mData: UnsafeMutableRawPointer.allocate(byteCount: Int(maximum) * 4, alignment: MemoryLayout<Float>.alignment))
            }
            buffers = list
            try check(AudioOutputUnitStart(created))
        } catch { stop(); throw error }
    }
    private func discard(flags: UnsafeMutablePointer<AudioUnitRenderActionFlags>, time: UnsafePointer<AudioTimeStamp>, frames: UInt32) -> OSStatus {
        guard let unit, let buffers, frames <= capacity else { return kAudioUnitErr_TooManyFramesToProcess }
        for i in 0..<buffers.count { buffers[i].mDataByteSize = frames * 4 }
        return AudioUnitRender(unit, flags, time, 1, frames, buffers.unsafeMutablePointer)
    }
    func stop() {
        if let unit {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
        }
        unit = nil
        if let buffers {
            for buffer in buffers { buffer.mData?.deallocate() }
            buffers.unsafeMutablePointer.deallocate()
        }
        buffers = nil; capacity = 0
    }
    private func check(_ status: OSStatus) throws {
        if status != noErr { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
    deinit { stop() }
}

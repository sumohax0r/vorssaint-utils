// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import SwiftUI
import Darwin

/// Poll only this fixed-height leaf while Details is expanded. Never publish
/// resource samples through the service shared by the HUD and settings form.
struct DictationResourceUsageView: View {
    private struct Sample {
        let pid: pid_t
        let bytes: UInt64
        let neuralBytes: UInt64?
        let cpuTicks: UInt64
        let time: TimeInterval
    }
    @State private var app: Sample?
    @State private var model: Sample?
    @State private var appCPU: Double?
    @State private var modelCPU: Double?
    @State private var modelRunning = false
    @State private var appDiskBytes: Int64?
    @State private var engineDiskBytes: Int64?
    private var combined: UInt64? {
        guard let app, !modelRunning || model != nil else { return nil }
        return app.bytes + (model?.bytes ?? 0)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Live resource usage", systemImage: "memorychip").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                GridRow {
                    Text("Process").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Memory").frame(width: 100, alignment: .trailing)
                    Text("CPU").frame(width: 65, alignment: .trailing)
                }.font(.caption).foregroundStyle(.secondary)
                GridRow {
                    Text("Vorssaint app")
                    Text(memory(app?.bytes)).frame(width: 100, alignment: .trailing)
                    Text(cpu(appCPU)).frame(width: 65, alignment: .trailing)
                }
                GridRow {
                    Text("Model worker")
                    Text(modelRunning ? memory(model?.bytes) : "0 MiB").frame(width: 100, alignment: .trailing)
                    Text(modelRunning ? cpu(modelCPU) : "0%").frame(width: 65, alignment: .trailing)
                }
                GridRow {
                    Text("Neural Engine · separate")
                    Text(modelRunning ? memory(model?.neuralBytes) : "0 MiB")
                        .frame(width: 100, alignment: .trailing)
                    Text("—").frame(width: 65, alignment: .trailing)
                }
            }.font(.system(size: 13)).monospacedDigit()
            HStack {
                Text(modelRunning ? "Model process running" : "Model unloaded")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("App + worker: \(memory(combined))").monospacedDigit()
            }.font(.caption).lineLimit(1)
            Text("Updates every second while Details is open. App and worker show macOS physical footprints, including compressed memory and GPU memory charged to each process. Core ML models also use the separate Neural Engine counter shown here; it is not added to the process subtotal. These counters do not measure all system caches. 100% CPU equals one core. Model download size is separate from memory usage.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Unload model", action: DictationService.shared.offload)
                .disabled(!modelRunning)
            Divider()
            DictationDetailRow(icon: "app", title: "Installed app", value: disk(appDiskBytes),
                              subtitle: "App bundle on disk · includes the dictation engine")
            DictationDetailRow(icon: "waveform", title: "Dictation engine & sounds", value: disk(engineDiskBytes),
                              subtitle: "Included in the app size above · model downloads are separate")
        }
        .task {
            guard !Task.isCancelled else { return }
            refresh()
            let bundle = Bundle.main.bundleURL
            let sizeTask = Task.detached(priority: .utility) {
                let app = Self.folderSize(bundle)
                let engine = Self.folderSize(bundle.appendingPathComponent("Contents/MacOS/DictationEngine"))
                let sounds = Self.folderSize(bundle.appendingPathComponent("Contents/Resources/DictationSounds"))
                return (app, engine + sounds)
            }
            let sizes = await withTaskCancellationHandler {
                await sizeTask.value
            } onCancel: {
                sizeTask.cancel()
            }
            guard !Task.isCancelled else { return }
            appDiskBytes = sizes.0; engineDiskBytes = sizes.1
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { break }
                guard !Task.isCancelled else { break }
                refresh()
            }
        }
    }
    private func memory(_ bytes: UInt64?) -> String {
        guard let bytes else { return "—" }
        return String(format: "%.1f MiB", Double(bytes) / 1_048_576)
    }
    private func disk(_ bytes: Int64?) -> String {
        bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—"
    }
    private func cpu(_ value: Double?) -> String { value.map { String(format: "%.1f%%", $0) } ?? "—" }
    private func refresh() {
        let nextApp = Self.sample(getpid())
        appCPU = Self.cpuDelta(app, nextApp); app = nextApp
        let pid = DictationService.shared.modelProcessID
        modelRunning = pid != nil
        let nextModel = pid.flatMap(Self.sample)
        modelCPU = Self.cpuDelta(model, nextModel); model = nextModel
    }
    private static func sample(_ pid: pid_t) -> Sample? {
        var info = rusage_info_current()
        func read(_ flavor: Int32) -> Int32 {
            withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, flavor, $0)
                }
            }
        }
        // V6 supplies the separate neural counter. Older macOS releases can
        // still report process memory and CPU with V4; never display a missing
        // neural counter as zero.
        let hasNeural = read(RUSAGE_INFO_V6) == 0
        guard hasNeural || read(RUSAGE_INFO_V4) == 0 else { return nil }
        let total = info.ri_user_time.addingReportingOverflow(info.ri_system_time)
        guard !total.overflow else { return nil }
        return Sample(pid: pid, bytes: info.ri_phys_footprint,
                      neuralBytes: hasNeural ? info.ri_neural_footprint : nil,
                      cpuTicks: total.partialValue,
                      time: ProcessInfo.processInfo.systemUptime)
    }
    private static func cpuDelta(_ previous: Sample?, _ next: Sample?) -> Double? {
        guard let previous, let next, previous.pid == next.pid, next.time > previous.time,
              next.cpuTicks >= previous.cpuTicks else { return nil }
        // proc_pid_rusage reports CPU time in Mach ticks on this platform.
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom > 0 else { return nil }
        let nanoseconds = Double(next.cpuTicks - previous.cpuTicks) * Double(timebase.numer) / Double(timebase.denom)
        return nanoseconds / 1_000_000_000 / (next.time - previous.time) * 100
    }
    nonisolated private static func folderSize(_ url: URL) -> Int64 {
        guard !Task.isCancelled else { return 0 }
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        if let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true {
            return Int64(values.fileSize ?? 0)
        }
        guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in files {
            guard !Task.isCancelled else { return 0 }
            if let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }
}

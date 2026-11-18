// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import SwiftUI
import Combine

struct DictationSettingsCard: View {
    @ObservedObject private var permissions = Permissions.shared
    @StateObject private var settings = DictationSettingsObservation()
    private var service: DictationService { settings.service }
    @AppStorage(DefaultsKey.dictationToggleMode) private var toggleMode = false
    @AppStorage(DefaultsKey.dictationEnabled) private var enabled = false
    @AppStorage(DefaultsKey.dictationModel) private var model = ""
    @AppStorage(DefaultsKey.dictationStreaming) private var streaming = false
    @AppStorage(DefaultsKey.dictationMicrophone) private var microphone = ""
    @AppStorage(DefaultsKey.dictationKeepReady) private var keepReady = false
    @AppStorage(DefaultsKey.dictationMouseButtons) private var mouseTriggers = ""
    @AppStorage(DefaultsKey.dictationAutoSend) private var autoSend = false
    @AppStorage(DefaultsKey.dictationSoundStyle) private var soundStyle = "ready"
    @AppStorage(DefaultsKey.dictationSounds) private var sounds = true
    @AppStorage(DefaultsKey.dictationMuteOutput) private var mute = false
    @AppStorage(DefaultsKey.dictationSoftwareBluetooth) private var softwareBluetooth = false
    @AppStorage(DefaultsKey.dictationLowerOutput) private var lowerOutput = false
    @AppStorage(DefaultsKey.dictationOutputLevel) private var outputLevel = 0.1
    @AppStorage(DefaultsKey.dictationOutputFade) private var outputFade = 0.3
    @State private var detailsExpanded = false
    @AppStorage(DefaultsKey.dictationRecordingLimitMinutes) private var recordingLimitMinutes = 5
    private func t(_ key: String) -> String { DictationStrings.text(key) }
    var body: some View {
        Group {
            Section {
                Toggle(t("enabled"), isOn: $enabled)
                if enabled { permissionRows }
            } header: { Text(t("title")) }
            if enabled {
                Section("Input") { inputRows }
                Section("Trigger") { triggerRows }
                Section {
                    HStack {
                        Text(service.message.isEmpty ? t("ready") : service.message)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.tail)
                            .help(service.message)
                        Spacer(minLength: 8)
                        Button(t(service.active ? "cancel" : service.state == .failed ? "retry" : "start")) {
                            if service.active { service.cancel() }
                            else if service.state == .failed { service.syncWithPreferences() }
                            else { service.toggle() }
                        }
                        .frame(width: 100)
                        .disabled(!service.active && ![.ready, .review, .failed].contains(service.state))
                    }.frame(height: 24)
                }
            }
            Section("Last transcription") {
                DictationSettingsTranscript()
            }
            Section {
                Button {
                    detailsExpanded.toggle()
                } label: {
                    HStack {
                        Label("Details", systemImage: "info.circle")
                            .font(.headline)
                        Spacer()
                        Image(systemName: detailsExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityValue(detailsExpanded ? "Expanded" : "Collapsed")
                if detailsExpanded { details }
            }
        }
        .onAppear {
            if soundStyle == "radio" { soundStyle = "wood" }
            service.refreshDevices(); service.syncWithPreferences()
        }
        .onChange(of: enabled) { _, _ in service.syncWithPreferences() }
        .onChange(of: model) { _, _ in service.selectModel() }
        .onChange(of: microphone) { _, _ in service.syncWithPreferences() }
        .onChange(of: keepReady) { _, _ in service.syncWithPreferences() }
        .onChange(of: permissions.accessibility) { _, _ in service.syncWithPreferences() }
        .onChange(of: mouseTriggers) { _, _ in service.syncWithPreferences() }
    }
    @ViewBuilder private var permissionRows: some View {
        if permissions.microphone != .granted {
            VStack(alignment: .leading, spacing: 5) {
                Text(t("microphoneReason")).font(.caption).foregroundStyle(.secondary)
                Button(t(permissions.microphone == .denied ? "microphoneSettings" : "allowMicrophone"), action: service.requestMicrophone)
            }
        }
        if !permissions.accessibility {
            VStack(alignment: .leading, spacing: 5) {
                Text(t("accessibilityReason")).font(.caption).foregroundStyle(.secondary)
                Button(t("allowAccessibility")) { permissions.requestAccessibility() }
            }
        }
    }
    private var inputRows: some View {
        Group {
            HStack {
                Picker(selection: $model) {
                    Text(t("chooseModel")).tag("")
                    ForEach(service.models) {
                        Text("\($0.title) · \(service.modelStatus($0))").tag($0.id)
                    }
                } label: { Label("Engine", systemImage: "cpu") }
                if let selected = service.selectedModel {
                    Menu {
                        Text(ByteCountFormatter.string(fromByteCount: selected.bytes, countStyle: .file))
                        if service.modelLoaded || service.active { Button(t("offload"), action: service.offload) }
                        if selected.installed { Button(t("remove"), action: service.removeModel) }
                        else if service.state != .downloading { Button(t("download"), action: service.download) }
                        Link(t("license"), destination: URL(string: "https://huggingface.co/\(selected.repo)")!)
                    } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).fixedSize().help("Manage model")
                }
            }
            if service.state == .downloading {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        ProgressView(value: service.downloadProgress)
                        Text(service.downloadProgress, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit().frame(width: 38, alignment: .trailing)
                        Button(t("cancel"), action: service.cancelDownload)
                    }
                    Text(service.downloadStatus).font(.caption).monospacedDigit()
                        .foregroundStyle(.secondary).lineLimit(2)
                        .frame(height: 30, alignment: .topLeading)
                }
            }
            HStack {
                Label(t("processing"), systemImage: "waveform")
                Spacer()
                Picker(t("processing"), selection: $streaming) {
                    Text(t("streaming")).tag(true); Text(t("batch")).tag(false)
                }.labelsHidden().pickerStyle(.segmented).frame(width: 190).disabled(service.active)
            }
            HStack {
                Picker(selection: $microphone) {
                    Text(t("system")).tag("")
                    if !microphone.isEmpty && !service.devices.contains(where: { $0.id == microphone }) {
                        Text(t("microphoneUnavailable")).tag(microphone)
                    }
                    ForEach(service.devices) { Text($0.name).tag($0.id) }
                } label: { Label(t("microphone"), systemImage: "mic") }
                .disabled(service.active)
                Button(action: service.refreshDevices) { Image(systemName: "arrow.clockwise") }.help(t("refresh"))
            }
            Toggle(isOn: $keepReady) { Label(t("keepReady"), systemImage: "mic.badge.plus") }
                .disabled(service.active).help(t("keepHint"))
            if model == "bark-clean" {
                Text("English dictation with fillers and repeats removed. Uses 4-bit weights to reduce memory; speed and accuracy may differ from the original. First preparation may briefly use about 6 GB of RAM. Remove download also removes the prepared cache.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent { Text(model.isEmpty ? "—" : t(model == "parakeet" ? "automatic" : "english")) }
                label: { Label(t("language"), systemImage: "globe") }
        }
    }
    private var selectedMouseButtons: [Int] {
        Array(Set(mouseTriggers.split(separator: ",").compactMap { Int($0) }.filter { (2...4).contains($0) })).sorted()
    }
    private func saveMouseButtons(_ buttons: [Int]) {
        mouseTriggers = Array(Set(buttons)).sorted().map(String.init).joined(separator: ",")
    }
    private var secondaryTriggers: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Secondary triggers", systemImage: "computermouse")
                Spacer()
                Button {
                    if let next = (2...4).first(where: { !selectedMouseButtons.contains($0) }) {
                        saveMouseButtons(selectedMouseButtons + [next])
                    }
                } label: { Image(systemName: "plus") }
                .help("Add secondary trigger").accessibilityLabel("Add secondary trigger")
                .disabled(selectedMouseButtons.count == 3 || service.active)
            }
            ForEach(selectedMouseButtons, id: \.self) { button in
                HStack {
                    Picker("Mouse button", selection: Binding(get: { button }, set: { replacement in
                        saveMouseButtons(selectedMouseButtons.map { $0 == button ? replacement : $0 })
                    })) {
                        ForEach(Array(2...4), id: \.self) { choice in
                            Text(t(choice == 2 ? "middle" : choice == 3 ? "mouse4" : "mouse5"))
                                .tag(choice).disabled(choice != button && selectedMouseButtons.contains(choice))
                        }
                    }.labelsHidden()
                    Button {
                        saveMouseButtons(selectedMouseButtons.filter { $0 != button })
                    } label: { Image(systemName: "minus.circle") }
                    .help("Remove trigger").accessibilityLabel("Remove trigger")
                }.disabled(service.active)
            }
        }
    }
    private var triggerRows: some View {
        Group {
            DictationShortcutRow()
            secondaryTriggers
            Picker(t("triggerMode"), selection: $toggleMode) {
                Text(t("holdMode")).tag(false); Text(t("toggleMode")).tag(true)
            }.disabled(service.active)
            if !service.triggerWarning.isEmpty, permissions.accessibility {
                Text(service.triggerWarning).font(.caption).foregroundStyle(.orange)
                Button(t("retryTriggers"), action: service.syncWithPreferences)
            }
            Toggle(isOn: $autoSend) { Label(t("autoSend"), systemImage: "paperplane") }.help(t("autoSendHint"))
            Toggle(isOn: $mute) { Label(t("mute"), systemImage: "speaker.slash") }
                .disabled(service.active)
                .onChange(of: mute) { _, value in if value { lowerOutput = false } }
            Toggle(isOn: $lowerOutput) { Label("Lower audio while dictating", systemImage: "speaker.wave.1") }
                .disabled(service.active)
                .onChange(of: lowerOutput) { _, value in if value { mute = false } }
            if lowerOutput {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Keep Bluetooth hardware volume fixed", isOn: $softwareBluetooth)
                        .disabled(!AppFeature.mixer.isAvailable)
                        .help("Uses Volume mixer and macOS System Audio Recording access to lower compatible apps in software. Some apps, including Zoom and audio workstations, bypass the mixer.")
                    if softwareBluetooth {
                        Text("Uses System Audio Recording access to lower compatible apps locally. Zoom and audio workstations may remain unchanged. Your saved app volumes are preserved.")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Recording volume")
                        Spacer()
                        Text(outputLevel, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                    }
                    Slider(value: $outputLevel, in: 0...1, step: 0.01)
                        .accessibilityLabel("Recording volume")
                    HStack {
                        Text("Fade in and out")
                        Spacer()
                        Text(String(format: "%.1f s", outputFade)).monospacedDigit()
                    }
                    Slider(value: $outputFade, in: 0...3, step: 0.1)
                        .accessibilityLabel("Fade duration")
                    Text("Restores the original volume when you stop. Bluetooth outputs change volume directly to keep earbuds synchronized; other outputs use the fade. Audio already quieter stays quieter. Fixed-volume outputs and apps using another output are unaffected.")
                        .font(.caption).foregroundStyle(.secondary)
                }.disabled(service.active)
            }
            Toggle(isOn: $sounds) { Label(t("sounds"), systemImage: "bell") }
            if sounds {
                HStack {
                    Picker("Sound", selection: $soundStyle) {
                        Text("Ready / Done").tag("ready")
                        Text("Wood").tag("wood")
                        Text("Bubble").tag("bubble")
                        Divider()
                        Text("Soft").tag("soft")
                        Text("Glass").tag("glass")
                        Text("Click").tag("click")
                    }
                    Button(action: service.previewSounds) { Image(systemName: "play.fill") }
                        .help("Preview start and stop").disabled(service.active)
                }
            }
        }
    }
    private var details: some View {
        VStack(alignment: .leading, spacing: 16) {
            DictationDetailRow(icon: "lock.shield", title: "Processing", value: "On-device",
                              subtitle: "Audio stays on this Mac.")
            Divider()
            DictationResourceUsageView()
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Recording limit", systemImage: "timer")
                    Spacer()
                    TextField("Minutes", value: $recordingLimitMinutes, format: .number.grouping(.never))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                        .accessibilityLabel("Recording limit in minutes")
                    Text("minutes").foregroundStyle(.secondary)
                }
                Text("Applies to the next recording. Longer recordings use more memory.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .onChange(of: recordingLimitMinutes) { _, value in
                if value < 1 { recordingLimitMinutes = 1 }
            }
            Divider()
            if let selected = service.selectedModel {
                DictationDetailRow(icon: "internaldrive", title: "Model download",
                                  value: ByteCountFormatter.string(fromByteCount: selected.bytes, countStyle: .file),
                                  subtitle: selected.installed ? "Saved on disk · separate from RAM" : "Not downloaded · required disk space")
                Link("Model license and credits", destination: URL(string: "https://huggingface.co/\(selected.repo)")!)
                    .font(.caption)
            }
            Text("The last transcription stays in memory until cleared or you quit.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 6)
    }
}

struct DictationDetailRow: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(value).monospacedDigit().foregroundStyle(.secondary)
                }
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// The settings form does not subscribe to the HUD's 10 Hz meter or live text.
/// Only configuration/status changes invalidate the surrounding form.
private final class DictationSettingsObservation: ObservableObject {
    let service = DictationService.shared
    private var subscriptions = Set<AnyCancellable>()
    init() {
        observe(service.$state.removeDuplicates().dropFirst())
        observe(service.$message.removeDuplicates().dropFirst())
        observe(service.$modelLoaded.removeDuplicates().dropFirst())
        observe(service.$triggerWarning.removeDuplicates().dropFirst())
        observe(service.$downloadProgress.removeDuplicates().dropFirst())
        observe(service.$downloadStatus.removeDuplicates().dropFirst())
        observe(service.$devices.dropFirst())
    }
    private func observe<P: Publisher>(_ publisher: P) where P.Failure == Never {
        publisher.sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &subscriptions)
    }
}

/// A fixed-size leaf keeps growing transcripts from resizing the settings form.
private struct DictationSettingsTranscript: View {
    @State private var transcript = DictationService.shared.lastTranscript
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                Text(transcript.isEmpty ? "Your last completed transcription will appear here." : transcript)
                    .font(.callout).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 100)
            HStack {
                Spacer()
                Button("Clear", action: DictationService.shared.clearLastTranscript)
                Button("Copy", action: DictationService.shared.copyLastTranscript)
            }.disabled(transcript.isEmpty)
        }
        .onReceive(DictationService.shared.$lastTranscript.removeDuplicates()) { transcript = $0 }
    }
}

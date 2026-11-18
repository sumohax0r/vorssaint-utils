// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import SwiftUI

struct DictationShortcutRow: View {
    var isEnabled = true
    var onChange: () -> Void = { DictationService.shared.syncWithPreferences() }
    @AppStorage(DefaultsKey.dictationShortcut) private var raw = GlobalShortcut.dictationDefault.storageValue
    @State private var error: String?
    @State private var recording = false
    private var shortcut: GlobalShortcut {
        GlobalShortcut(storageValue: raw, requiringModifier: false) ?? GlobalShortcutRole.dictation.defaultShortcut
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Label(DictationStrings.text("hotkey"), systemImage: "keyboard")
                Spacer()
                ShortcutRecorderButton(shortcut: shortcut, isEnabled: isEnabled,
                    waitingTitle: "Press a key…", requiresModifier: false,
                    emptyTitle: DictationShortcut.modifier(raw).flatMap { DictationShortcut.modifierNames[$0] },
                    recordingChanged: { recording = $0; error = nil },
                    capturePhysicalModifierAction: { code in save("single:\(code)") },
                    invalidAction: { error = "Press one key or a key combination." },
                    captureAction: { captured in
                        if let conflict = GlobalShortcutRole.conflict(for: captured, excluding: .dictation) {
                            error = "Already used by \(conflict.title(L10n.shared.s))."
                        } else if captured.conflictsWithSystemShortcut(for: .dictation) {
                            error = "This shortcut is used by macOS. Choose another key."
                        } else { save(captured.storageValue) }
                    })
                    .frame(width: 150)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            else if recording { Text("Press and release a single key, or enter a combination. Esc cancels.").font(.caption).foregroundStyle(.secondary) }
        }
        .onAppear { DictationShortcut.migrate() }
    }
    private func save(_ value: String) {
        raw = value
        UserDefaults.standard.set(false, forKey: DefaultsKey.dictationRightControl)
        SystemShortcutTakeover.setTakeOver(DefaultsKey.dictationShortcut, false)
        error = nil
        onChange()
    }
}

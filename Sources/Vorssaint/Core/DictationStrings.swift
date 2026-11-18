// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import Foundation

enum DictationStrings {
    static func text(_ key: String) -> String { english[key] ?? key }
    private static let english: [String: String] = [
        "sounds": "Play start and stop sounds",
        "triggerMode": "Shortcut behavior", "holdMode": "Hold to dictate", "toggleMode": "Press to start / stop",
        "holdHint": "Hold your shortcut or mouse button while speaking. Release to stop and insert the transcript when ready.",
        "microphoneReason": "Microphone access lets Vorssaint hear your voice for local dictation. Audio stays on this Mac.",
        "accessibilityReason": "Accessibility lets Vorssaint insert text into the focused app and use single-modifier or mouse triggers. Without it, use a key combination and Copy transcript.",
        "allowMicrophone": "Allow Microphone", "microphoneSettings": "Open Microphone Settings",
        "granted": "Allowed", "permissionReady": "Microphone allowed. Press your shortcut again to start dictating.",
        "loadingTimeout": "Model loading timed out. Cancel, then retry in Dictation settings.",
        "transcriptionTimeout": "Transcription timed out. Cancel, then retry in Dictation settings.",
        "rightControl": "Right Control", "keyCombination": "Key combination",
        "soloHint": "Use Right Control by itself to dictate. Hold it in Hold to dictate mode; combining it with another key cancels the recording.",
        "triggerPermission": "Single-modifier and mouse triggers need Accessibility access for Vorssaint.",
        "triggerFailed": "macOS could not register the dictation triggers. Check Accessibility access, then retry.",
        "allowAccessibility": "Allow Accessibility", "retryTriggers": "Retry triggers",
        "chooseModel": "Select a model…",
        "onDemand": "Downloaded · loads into memory when you start dictating",
        "offload": "Unload from memory", "offloaded": "Model unloaded. It will load again when you start dictating.",
        "selectionHint": "Selecting a model downloads it. Models load into memory only when you start dictating. Unload from memory or remove the download whenever you want.",
        "microphoneUnavailable": "Selected microphone unavailable",
        "title": "Dictation", "description": "Turn speech into text locally, in any app.",
        "enabled": "Enable dictation", "engine": "Speech model", "processing": "Processing",
        "batch": "Batch", "streaming": "Live preview", "microphone": "Microphone",
        "system": "System default", "keepReady": "Keep microphone ready", "keepHint": "Keeps the microphone on while dictation is enabled. Audio is discarded until you start recording.",
        "language": "Language", "english": "English", "automatic": "Automatic · 25 languages",
        "hotkey": "Keyboard shortcut", "mouse": "Second trigger", "none": "None", "middle": "Middle mouse button",
        "mouse4": "Mouse button 4", "mouse5": "Mouse button 5", "autoSend": "Send Return after insertion",
        "autoSendHint": "May send messages immediately. Off by default.", "mute": "Mute Mac audio while recording",
        "download": "Download model", "remove": "Remove download", "cancel": "Cancel", "ready": "Ready",
        "loading": "Loading model…", "downloading": "Downloading model…", "listening": "Listening…",
        "processingStatus": "Transcribing…", "stop": "Stop and transcribe", "start": "Start dictation",
        "copy": "Copy transcript", "retry": "Retry loading", "permission": "Allow Microphone access in System Settings to dictate.",
        "accessibility": "Enable Accessibility to insert text into another app. Otherwise use Copy transcript.",
        "modelNeeded": "Download a speech model to get started.", "helperMissing": "This build does not include the local dictation engine.",
        "osRequired": "Local dictation requires macOS 15 or later.", "privacy": "Audio stays on this Mac. Selecting or downloading a model connects to Hugging Face.",
        "modeHint": "Live preview shows a scrolling transcript above the controls, refreshing about every 0.65 seconds when recognition can keep up. Text is inserted once after you stop. Recordings are limited to three minutes.",
        "focusChanged": "The focused app or field changed. Your transcript is ready to copy.",
        "empty": "No speech was recognized.", "failed": "Dictation could not finish.",
        "captureUnavailable": "The microphone did not deliver enough audio. Please try again. If this continues, reselect your microphone in Dictation settings.",
        "shortcutFailed": "This shortcut is already in use.", "copied": "Transcript copied.",
        "finished": "Transcript inserted.", "insertFailed": "Text could not be inserted. Use Copy transcript.",
        "license": "Model licenses and credits", "warmup": "Preparing microphone…", "refresh": "Refresh microphones"
    ]
}

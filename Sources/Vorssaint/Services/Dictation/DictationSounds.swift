// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint
import AVFoundation

/// One playback lane prevents overlapping or queued start/stop cues.
/// Owned and used on the main run loop, including delegate callbacks.
final class DictationSounds: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var completion: (() -> Void)?
    private var prepared: [String: AVAudioPlayer] = [:]
    private var preparedStyle = ""
    private var firstStart = true

    func prepare() {
        let stored = UserDefaults.standard.string(forKey: DefaultsKey.dictationSoundStyle) ?? "ready"
        let selected = stored == "radio" ? "wood" : stored
        let style = ["soft", "glass", "click", "ready", "wood", "bubble"].contains(selected) ? selected : "ready"
        guard style != preparedStyle else { return }
        stop(); prepared.removeAll(); preparedStyle = style
        for cue in ["start", "start-warm", "stop", "preview"] {
            guard let url = Bundle.main.url(forResource: "\(style)-\(cue)", withExtension: "wav", subdirectory: "DictationSounds"),
                  let sound = try? AVAudioPlayer(contentsOf: url) else { continue }
            sound.prepareToPlay()
            prepared[cue] = sound
        }
    }
    @discardableResult
    func play(_ cue: String, completion: (() -> Void)? = nil) -> Bool {
        stop(); prepare()
        // A silent lead-in on the first start gives a cold output route time
        // to open before the short audible note. Later starts remain immediate.
        let key = cue == "start" && firstStart ? "start-warm" : cue
        guard let next = prepared[key] else { completion?(); return false }
        player = next; self.completion = completion
        next.currentTime = 0; next.delegate = self
        guard next.play() else { stop(); completion?(); return false }
        if cue == "start" { firstStart = false }
        return true
    }
    func stop() {
        player?.delegate = nil; player?.stop(); player = nil; completion = nil
    }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === self.player else { return }
        let finished = completion
        self.player = nil; completion = nil
        finished?()
    }
}

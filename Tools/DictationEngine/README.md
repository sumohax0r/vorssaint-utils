# Local dictation prototype

To package the release app with all supported local speech workers, run `VORSSAINT_DICTATION_ENGINE=1 ./build.sh` on your Apple Silicon Mac. The signed app is staged at `build/stage/Vorssaint.app`. The Bark and Phonon workers use the local Python 3.11 runtime prepared by the build.

To install a separate developer build:

```sh
VORSSAINT_DICTATION_ENGINE=1 ./build.sh --dev --install
```

The worker requires Swift 6.2 and macOS 15 or later. It uses the pinned FluidAudio revision in Package.swift, with TTS, diarization and text-normalization traits disabled. SwiftPM can still fetch the dependency's declared binary artifact during resolution. The app's ordinary build remains independent of this package; dictation reports an unavailable engine in that build.

Enable Dictation in Features → Sound, then open its settings in Quick tools. No model is selected or loaded initially. Selecting a model downloads it; memory loading waits until dictation starts. Unload from memory and Remove download are available even during recording/loading (they cancel the current session). The settings explain Microphone and Accessibility access separately. Starting without microphone access shows an explanation and an explicit permission button; after allowing access, press the shortcut again to record. Denied access links to macOS Microphone settings. Accessibility enables text insertion and the optional mouse trigger. The default shortcut is Control–Option–Shift–D. Hold to dictate is the default behavior: capture starts on press (including while the model loads), release ends capture, and the final transcript is inserted when recognition finishes. Press to start / stop is optional. Click the shortcut recorder and press/release a single key (including left/right Command, Option, Control, Shift or Fn/Globe), or type a combination. Existing Right Control settings migrate automatically. Hold the recorded key alone to dictate, or press/release in toggle mode. In hold mode, combining it with another key cancels that dictation session. Mouse triggers use the same hold/toggle setting and consume the whole click. Standalone modifier keys and mouse triggers require Accessibility; settings show registration problems and offer permission/retry actions. Live preview uses a fixed-height, 440-point-wide scrolling transcript above bottom-anchored controls. It requests updates every 650 ms when the model can keep up, with only one request in flight and a 150 ms recovery interval after replies. This is periodic re-decoding, not token-by-token streaming; the final transcript is inserted only once. Fluid Speech Mini is English-only; Parakeet v3 detects its supported languages automatically.

The small nonactivating HUD is centered near the bottom of the display containing the pointer when recording begins. The HUD labels model loading and transcription separately and keeps failures visible until dismissed. Loading and transcription each time out after two minutes. Ready / Done is the default sound pair. Short synthesized start and stop cues are enabled by default, with Ready / Done, Wood, Bubble, Soft, Glass and Click pairs and a preview button in settings. Playback uses one channel on the normal audio output, following its volume/mute. Capture starts immediately; an 80 ms cue debounce suppresses accidental modifier chords. A stop cue plays only after an announced start. Pending cues are cancelled and playback is replaced rather than queued. Optional output muting waits for the start cue to finish; output is restored before the stop cue. The compact borderless HUD sits 36 points above the usable display bottom, with 100 ms open and 80 ms close fades (instant with Reduce Motion). Cancel discards the recording; Stop transcribes. The recording limit defaults to five minutes and is editable in Details as a positive whole number of minutes, without a preset maximum. Changes apply to the next recording and travel with settings backups. Longer recordings retain more audio in memory; WAV export uses bounded chunks. Keep microphone ready is opt-in and keeps capturing/discarding audio between recordings. Disable dictation to release both microphone and models. After a successful transcription the selected model stays resident and idle for reuse; Unload from memory releases it. A per-user process lock prevents multiple workers from loading models concurrently, including across app builds. A worker exits if its owning app disappears.

Model weights are downloaded on selection or an explicit retry, only from the pinned Hugging Face revisions in Resources/DictationModels.json. Downloads are staged, checked against sizes and available SHA-256 weight hashes, then moved into the app's Application Support directory. Models can be removed in settings. Fluid Speech Mini's compatible JointDecision folder is named JointDecisionv3 locally for the upstream loader; its v3 vocabulary is used. Model downloads require an internet connection; transcription does not.

Audio snapshots are private temporary WAV files used by the subprocess and are removed on completion/cancellation. There is no history or cloud transcription. The latest transcript remains in memory until dictation is disabled or the app exits. Copy transcript is explicit. Automatic insertion rechecks the target app and available window/field metadata before posting Paste. Apps that do not expose a focused Accessibility element can still receive ordinary keyboard paste. An insertion failure stays visible with Copy transcript in the HUD. Return after insertion is opt-in because it can send messages.

## Attribution

- FluidAudio by FluidInference, Apache-2.0: https://github.com/FluidInference/FluidAudio
- Fluid Speech Mini by FluidVoice, CC BY 4.0: https://huggingface.co/FluidVoice-Labs/fluid-speech-mini-coreml
- NVIDIA Parakeet TDT 0.6B v3; Core ML conversion by FluidInference, CC BY 4.0: https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml

The portable Swift inference package and model weights are distinct licensed components. Models are downloaded into user storage, not included in this source tree.

Dictation settings group the everyday controls under Input and Trigger. Model downloads, unload/remove actions and licenses live in the engine menu; detailed explanations and the transcript are under Details. Permission instructions appear only when access is missing.

The waveform is clamped to 4–12 points inside its 18-point lane, preserving vertical clearance even when microphone input saturates.

Secondary mouse triggers sit directly below the keyboard recorder. Use + to add middle mouse, button 4 or button 5, and remove rows individually. Each button can be assigned once; the existing single mouse assignment migrates automatically. Releases are tracked per button so releasing another trigger cannot end the held recording.

Cue players are prepared before use and reused. The first start after launch includes a 160 ms silent lead-in for output-device startup; capture is already running during it. A no-speech result uses a square 30-point close control so the capsule renders as a circle.

The settings form observes configuration and status separately from the floating HUD meter. Status controls reserve a fixed row, and the transcript inside Details has its own fixed-height scrolling area, so live text cannot resize the surrounding settings form.

The waveform uses a display-only logarithmic meter (-60 to -18 dBFS) with gentle compression and fast attack / slower release. Quiet speech therefore produces visible motion while bars remain capped at 12 points. Recorded audio and recognition input are unchanged.

Opening Dictation directly shows only Dictation settings, rather than the shared Quick Tools form. Last transcription is always visible above the collapsed Details section, with Copy and Clear controls and a fixed scrolling height. It updates only for completed, nonempty transcriptions; partial/cancelled/no-speech recordings leave it intact. This single result remains only in memory until cleared or the app quits.

Details has a full-width 44-point disclosure header. While expanded, its resource panel samples the app and model helper once per second using macOS physical-footprint and process CPU counters (converted from Mach ticks). CPU is percent of one core. It also shows combined RAM, installed bundle size, and the engine/sound portion of that bundle separately from the model download. The helper row includes the speech runtime; capture buffers and settings/HUD allocations remain part of the main app and are not falsely attributed as a precise feature total. Polling stops when Details closes.

Model downloads show received/total bytes, smoothed transfer speed, an approximate remaining transfer time, and an explicit verification phase. Progress is throttled to four updates per second per file; SHA-256 reads use a bounded per-chunk autorelease pool. Catalog metadata is decoded once. The app process owns downloads and verification, while Core ML inference occurs in the helper; process RAM must not be confused with model file size or all system-managed inference memory.

Microphone capture uses an AVCaptureSession with only the selected audio input and 16 kHz mono Float32 output. It does not construct an AVAudioEngine default-device aggregate or cancel a recording on an engine configuration-change notification. To avoid activating a Bluetooth headset microphone, select the built-in or another non-Bluetooth microphone; headphone playback remains on the system output. First-start AirPods behavior still requires hardware confirmation.

Bark 3.0 Clean is also available through the optional local Python/MLX worker.
See [Bark runtime notes](../BarkEngine/README.md) for setup, caching, memory,
licensing, and verification limitations. Only Parakeet uses automatic language
selection; Fluid Speech Mini and Bark Clean are English-only.

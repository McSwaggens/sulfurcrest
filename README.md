# Sulfurcrest

A native macOS voice-to-text dictation agent. Hold (or tap) your hotkey (the
**right Command** key by default), speak, and the transcription is pasted into
whatever app you're using.

Transcription runs **fully on-device** with NVIDIA **Parakeet** (via
[FluidAudio](https://github.com/FluidInference/FluidAudio)), compiled to Core ML and
kept resident on the Apple Neural Engine — so it's fast, private, and leaves your CPU
and GPU free.

## Features

- **Two ways to talk** — *hold* the hotkey (push-to-talk) or *tap* it to start and tap
  again to stop (toggle).
- **Configurable hotkey** — record any key combo (e.g. ⌃⌥Space) or a single modifier;
  regular-key combos are captured system-wide and won't type into other apps.
- **Live glass window** — a small, centered, translucent panel shows the transcription
  as you speak, with words fading in one at a time, and grows to fit.
- **Paste anywhere** — inserts into the focused app (native, Electron, terminals, web
  fields) without stealing focus; your clipboard is preserved.
- **Escape to cancel** — abandon a take with no paste.
- **On-device & private** — no network after the one-time model download.
- **Menu-bar agent** — no Dock icon; optional launch at login.
- **Settings** — configurable hotkey, live update rate, word-reveal speed, launch at login.

## Requirements

- Apple Silicon Mac, macOS 14 (Sonoma) or later.
- To build: Xcode 16+ / Swift 6.

## Install

```bash
./build.sh install                 # release build → signed /Applications/Sulfurcrest.app
open /Applications/Sulfurcrest.app
```

`./build.sh` alone builds `build/Sulfurcrest.app` without installing. On first launch
Sulfurcrest downloads the Parakeet Core ML model (~464 MB) into Application Support;
later launches load it from cache.

## Permissions

On first run, grant in **System Settings → Privacy & Security**:

- **Microphone** — to record speech.
- **Accessibility** — for the global hotkey (a `CGEventTap`) and to paste (a
  synthesized ⌘V). The hotkey starts working as soon as this is granted (the monitor
  retries until then) — no relaunch needed.

## Usage

- **Push-to-talk:** hold the hotkey (right ⌘ by default), speak, release.
- **Toggle:** tap the hotkey to start, tap again to stop.
- **Cancel:** press **Esc** while recording — the window closes and nothing is pasted.
- **Change the hotkey:** open Settings → *Hotkey* → **Record shortcut**, then press the
  key combo you want. It takes effect immediately.
- If nothing was said, nothing is pasted.
- **Settings / Quit:** click the menu-bar mic icon → **Settings…** (⌘,).

The default model is English (`parakeet-tdt-0.6b-v2`). For multilingual, set
`ASRService.modelVersion` to `.v3`.

## Development

- Debug build: `swift build`.
- Headless checks: `.build/debug/Sulfurcrest --selftest` (loads the model) and
  `--selftest-asr` (full transcription pipeline).
- Diagnostics: launch with `--debug` (or `SULFURCREST_DEBUG=1`) to log to
  `~/Library/Logs/Sulfurcrest.log`.
- **Stable permissions across rebuilds:** ad-hoc signing changes the code hash every
  build, so macOS forgets the Accessibility grant. Create a one-time self-signed
  **Code Signing** certificate named `Sulfurcrest Dev` (Keychain Access → Certificate
  Assistant → Create a Certificate → *Self Signed Root*, *Code Signing*); `build.sh`
  detects it automatically. Override with `SIGN_IDENTITY=...`.
- Architecture: a global `CGEventTap` hotkey monitor (`Hotkey/HotkeyMonitor.swift`,
  configured by `Hotkey/Hotkey.swift`) feeds a
  serial state machine (`Hotkey/DictationController.swift`) that drives mic capture
  (`Audio/`), the resident on-device Parakeet engine (`ASR/ASRService.swift`), the glass
  HUD (`UI/`), and paste (`Paste/Paster.swift`).

Sulfurcrest ships **non-sandboxed** (pasting into other apps isn't allowed under the
App Sandbox), so it's distributed outside the Mac App Store.

## Credits

- Speech recognition: [FluidAudio](https://github.com/FluidInference/FluidAudio) running
  NVIDIA's [Parakeet](https://huggingface.co/nvidia) models.

## License

MIT — see [LICENSE](LICENSE).

# Speccy

A SwiftUI text‑to‑speech app with selectable engines:
- System TTS (AVSpeechSynthesizer)
- OpenAI TTS with offline cache and progress UI

It’s fully vibe coded — no storyboards, just clean SwiftUI and services.

## Features
- System and OpenAI Text‑to‑Speech
- Download‑once, play‑offline cache for OpenAI audio
- Pause/resume with accurate progress
- Per‑document language selection (System engine)
- Simple Settings screen to manage OpenAI config and default engine

## Getting started
1. Clone the repo and open `speccy.xcodeproj` in Xcode.
2. Build and run on iOS, iPadOS, or macOS (SwiftUI).
3. Tap the gear icon to open Settings.

## OpenAI configuration
You can provide your key in any of these ways:
- In‑app Settings (recommended): set the API key, model, voice, format
- Add to Info.plist: `OPENAI_API_KEY`
- Environment variable: `OPENAI_API_KEY`

Optional keys (also manageable from Settings):
- `OPENAI_TTS_MODEL` (default: `gpt-4o-mini-tts`)
- `OPENAI_TTS_VOICE` (default: `alloy`)
- `OPENAI_TTS_FORMAT` (default: `mp3`)

## How OpenAI audio works
- First play: audio is requested once and downloaded with a visible progress bar
- Subsequent plays: the cached file is used for instant, offline playback
- Cache location: Application Support `tts-cache/`

## Notes
- Speed control applies to the System engine. OpenAI playback uses the generated audio as‑is.
- Engine choice is persisted and restored on launch.

## Tech
- SwiftUI, SwiftData, AVFoundation, URLSession
- No storyboards. Fully vibe coded.

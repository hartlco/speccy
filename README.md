# Speccy

A SwiftUI text‑to‑speech app using OpenAI TTS with offline cache and progress UI

It’s fully vibe coded — no storyboards, just clean SwiftUI and services.

## Features
- OpenAI Text‑to‑Speech with high-quality voices
- Download‑once, play‑offline cache for all audio
- Pause/resume with accurate progress tracking
- Background playback with mini-player controls
- Playback speed control and preferences
- Centralized download management with progress tracking
- Simple Settings screen to manage OpenAI configuration

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

## How it works
- First play: audio is requested once and downloaded with a visible progress bar
- Subsequent plays: the cached file is used for instant, offline playback
- Cache location: Application Support `tts-cache/`

## Background Playback
- Audio continues playing when the detail view is closed
- Mini-player appears at the bottom of the screen during active playback
- Control playback from the mini-player: play/pause, stop, and progress tracking
- Tap the mini-player to return to the full player view

## Notes
- Uses OpenAI's TTS API for high-quality speech synthesis
- Downloads are managed centrally and cached for offline playback
- Background playback works across the entire app interface
- Playback speed can be adjusted in real-time

## Tech
- SwiftUI, SwiftData, AVFoundation, URLSession
- No storyboards. Fully vibe coded.

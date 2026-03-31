# VoiceInk — macOS Voice-to-Text App

## Architecture
Flutter desktop app with dual STT engines (Whisper.cpp CLI wrapper + Sherpa-ONNX via FFI).

```
lib/
├── config/app_config.dart     — App identity, 34 supported languages
├── models/                    — WhisperModel, SherpaModel, WritingStyle
├── services/                  — Core logic (20 services)
│   ├── stt_engine_manager     — Engine selection (whisperCpp vs sherpaOnnx)
│   ├── dictation_service      — Main orchestrator (streaming, toggle mode)
│   ├── whisper_cpp_transcriber — Wraps whisper.cpp CLI binary
│   ├── sherpa_onnx_transcriber — Native FFI transcriber
│   ├── text_injection_service  — Platform keyboard injection
│   └── hotkey_service          — Global hotkey registration
└── ui/                        — 5 screens (onboarding, settings, dictionary, indicator, permissions)
```

## Tech Stack
- Flutter 3.11+, Dart, macOS desktop
- whisper.cpp (C++ native, in native/whisper.cpp/)
- Sherpa-ONNX 1.10.40 (Dart FFI, packages/whisper_flutter_new/)
- SQLite (sqflite), SharedPreferences, Dio for model downloads

## Conventions
- Services are singletons initialized in main.dart
- Models download from HuggingFace URLs defined in model classes
- Audio capture via `record` package → transcription → text cleanup → injection
- Writing styles: verbatim, clean, formal, chat (defined in WritingStyle enum)

## Debugging Notes
- Whisper.cpp runs as subprocess — check stderr for native crashes
- Sherpa-ONNX uses FFI — segfaults appear in platform logs, not Flutter console
- Model download failures: check Dio error codes, HuggingFace URL validity
- Text injection failures: check accessibility permissions on macOS
- Audio issues: check permission_service.dart and audio_device_service.dart

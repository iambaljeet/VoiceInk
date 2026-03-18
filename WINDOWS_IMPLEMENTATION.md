# VoiceInk Windows Implementation Guide

## Overview
Your app is **95% ready for Windows**. All Flutter packages already support Windows. You only need to:
1. Compile whisper.cpp for Windows (CMake + MSVC)
2. Update 2 small Dart functions for Windows paths/permissions
3. Test on Windows

**Estimated time: 2-3 days**

---

## Step 1: Build whisper.cpp for Windows

### Option A: Build on Windows (Recommended)

**Requirements:**
- Windows 10/11
- Visual Studio 2019+ (Community Edition is free)
- CMake 3.14+
- Git

**Build Process:**
```bash
cd native/whisper.cpp
mkdir build
cd build
cmake .. -G "Visual Studio 17 2022" -A x64
cmake --build . --config Release
```

**Result:** `build/bin/Release/whisper-cli.exe`

### Option B: Cross-compile from macOS (Advanced)

```bash
cd native/whisper.cpp
cmake -B build_windows \
  -DCMAKE_SYSTEM_NAME=Windows \
  -DCMAKE_SYSTEM_PROCESSOR=x86_64 \
  -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
  -DCMAKE_CXX_COMPILER=x86_64-w64-mingw32-g++
cmake --build build_windows
```

### Option C: Use GitHub Actions (CI/CD)

Add `.github/workflows/build-windows.yml`:
```yaml
name: Build Windows
on: [push]
jobs:
  build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v3
      - uses: microsoft/setup-msbuild@v1
      - run: |
          cd native/whisper.cpp
          mkdir build && cd build
          cmake .. -G "Visual Studio 17 2022"
          cmake --build . --config Release
      - uses: actions/upload-artifact@v3
        with:
          name: whisper-cli.exe
          path: native/whisper.cpp/build/bin/Release/whisper-cli.exe
```

### Installation

**During Development:**
Place compiled binary in:
```
voice_ink/windows/runner/Release/whisper-cli.exe
```

**For Distribution:**
Windows CMakeLists.txt at line 92 copies native assets. Binary should be available in build directory.

---

## Step 2: Update Dart Code for Windows

### File 1: lib/services/dictation_service.dart

**Change**: Lines 62-87 (function `_resolveWhisperPath()`)

**Current code:**
```dart
Future<String?> _resolveWhisperPath() async {
  final execPath = Platform.resolvedExecutable;
  final appDir = File(execPath).parent.path;

  final candidates = [
    '$appDir/../Resources/whisper-cli',
    '$appDir/whisper-cli',
    '/Users/baljeet/FlutterWorkspace/voice_ink/native/whisper.cpp/build/bin/whisper-cli',
  ];
  // ...
}
```

**Updated code:**
```dart
Future<String?> _resolveWhisperPath() async {
  final execPath = Platform.resolvedExecutable;
  final appDir = File(execPath).parent.path;
  
  // Add .exe extension on Windows
  final ext = Platform.isWindows ? '.exe' : '';

  final candidates = [
    '$appDir/../Resources/whisper-cli$ext',
    '$appDir/whisper-cli$ext',
    '/Users/baljeet/FlutterWorkspace/voice_ink/native/whisper.cpp/build/bin/whisper-cli$ext',
  ];
  
  // Also check current working directory
  final cwd = Directory.current.path;
  candidates.add('$cwd/native/whisper.cpp/build/bin/whisper-cli$ext');

  for (final path in candidates) {
    if (await File(path).exists()) return path;
  }

  // Check PATH
  try {
    final result = await Process.run('where', ['whisper-cli$ext']);
    if (result.exitCode == 0) return (result.stdout as String).trim();
  } catch (_) {}

  return null;
}
```

**Key changes:**
- Line 6: Add `.exe` extension variable
- Lines 9-13: Use `ext` in all candidate paths
- Line 15: Add Windows development path check
- Lines 21-23: Use `where` (Windows equivalent of `which`)

### File 2: lib/services/permission_service.dart

**Change**: Lines 30-50 (function `checkAccessibility()`)

**Current code:**
```dart
Future<bool> checkAccessibility() async {
  if (!Platform.isMacOS) {
    _accessibilityGranted = true;
    return true;
  }
  try {
    // key code 63 = fn key (harmless no-op), requires accessibility
    final result = await Process.run('osascript', [
      '-e',
      'tell application "System Events" to key code 63',
    ]).timeout(const Duration(seconds: 5));
    _accessibilityGranted = result.exitCode == 0;
    // ...
  } catch (e) {
    // ...
  }
  return _accessibilityGranted;
}
```

**This is already correct!**

The code already has:
```dart
if (!Platform.isMacOS) {
  _accessibilityGranted = true;
  return true;
}
```

So Windows will return `true` automatically. **No changes needed.**

### File 3: text_injection_service.dart

**Status:** Already has Windows implementation! ✅

Lines 53-78 already implement `_pasteOnWindows()` using PowerShell.
No changes needed.

---

## Step 3: Windows Build Configuration

Your `windows/CMakeLists.txt` is already configured correctly:
- Line 41-42: MSVC compiler settings ✓
- Line 33: Unicode support ✓
- Line 91-94: Native assets support ✓

**Optional: Add whisper binary to CMakeLists.txt**

To automatically include whisper-cli.exe in distribution:

```cmake
# At end of windows/CMakeLists.txt, after line 108:

# Copy whisper binary
if(EXISTS "${CMAKE_SOURCE_DIR}/../native/whisper.cpp/build/bin/Release/whisper-cli.exe")
  install(FILES "${CMAKE_SOURCE_DIR}/../native/whisper.cpp/build/bin/Release/whisper-cli.exe"
    DESTINATION "${CMAKE_INSTALL_PREFIX}"
    COMPONENT Runtime)
endif()
```

---

## Step 4: Testing on Windows

### Setup

**Option A: Windows VM**
- Use VMware, VirtualBox, or Parallels
- Windows 10/11
- Flutter SDK (same version as macOS)

**Option B: Windows Machine**
- Native Windows PC/Laptop

### Run

```bash
# Enable Windows desktop support
flutter config --enable-windows-desktop

# Build debug APK
flutter run -d windows

# Or build release
flutter build windows --release
```

### Test Checklist

- [ ] Audio recording works (allow microphone permission)
- [ ] Whisper transcription works (download a model in settings)
- [ ] Hotkeys work (Alt+Space, Alt+V)
- [ ] Text injection works (try in Notepad)
- [ ] System tray icon appears
- [ ] Window transparency looks acceptable
- [ ] Settings window opens/closes properly
- [ ] No crashes on startup/shutdown

### Troubleshooting

**"whisper-cli not found"**
- Check `flutter run -v` output for path resolution attempts
- Manually place whisper-cli.exe in `windows/runner/Release/`
- Or update _resolveWhisperPath() to add more search locations

**"Permission denied" on Ctrl+V**
- May happen with antivirus software
- Try disabling antivirus temporarily
- Or use alternative input injection method (see next section)

**Window transparency looks bad**
- Windows transparency != macOS
- This is expected; acceptable for MVP
- If critical, add custom Win32 window setup code (advanced)

**Hotkey not working**
- Some apps capture Alt key (VS Code, browsers)
- Try different hotkey combination in settings
- Document as known limitation

---

## Advanced: Alternative Text Injection (if PowerShell fails)

If PowerShell-based text injection fails on some systems, here's a C# alternative:

**Create windows/runner/win32_keyboard.cpp:**
```cpp
#include <windows.h>

extern "C" void PasteViaSendInput() {
  INPUT inputs[4] = {0};
  
  // Ctrl down
  inputs[0].type = INPUT_KEYBOARD;
  inputs[0].ki.wVk = VK_CONTROL;
  
  // V down
  inputs[1].type = INPUT_KEYBOARD;
  inputs[1].ki.wVk = 'V';
  
  // V up
  inputs[2].type = INPUT_KEYBOARD;
  inputs[2].ki.wVk = 'V';
  inputs[2].ki.dwFlags = KEYEVENTF_KEYUP;
  
  // Ctrl up
  inputs[3].type = INPUT_KEYBOARD;
  inputs[3].ki.wVk = VK_CONTROL;
  inputs[3].ki.dwFlags = KEYEVENTF_KEYUP;
  
  SendInput(4, inputs, sizeof(INPUT));
}
```

Then call from Dart via platform channel. (More complex but more reliable.)

---

## Platform Channel Integration (Optional)

If you want more robust Windows integration, create a platform channel:

**main.dart:**
```dart
const platform = MethodChannel('com.voiceink/keyboard');

Future<void> pasteText(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  try {
    await platform.invokeMethod('paste');
  } on PlatformException catch (e) {
    debugPrint('Paste failed: ${e.message}');
  }
}
```

**windows/runner/main.cc:**
```cpp
// Add to flutter::TextInputPlugin::KeyboardLayoutDidChange() or similar
auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
  engine->messenger(),
  "com.voiceink/keyboard",
  &flutter::StandardMethodCodec::GetInstance());

channel->SetMethodCallHandler(
  [](const auto& call, auto result) {
    if (call->method_name() == "paste") {
      // Call PasteViaSendInput() here
      result->Success();
    }
  });
```

This is optional but makes text injection more robust.

---

## Deployment

### Windows Installer

After `flutter build windows --release`:

Use **MSIX** (Microsoft's modern installer):
```bash
flutter pub get
flutter pub run msix:create
```

Or use **Inno Setup** for classic .exe installer (more user-friendly).

### Code Signing (Optional)

For professional deployment, sign the .exe:
```bash
signtool sign /f cert.pfx /p password /t http://timestamp.server voice_ink.exe
```

---

## Platform-Specific Features to Document

**In README.md, add Windows section:**

```markdown
## Windows

### Supported
- ✅ Audio capture (microphone recording)
- ✅ Voice transcription (whisper.cpp)
- ✅ Global hotkeys (Alt+Space, Alt+V)
- ✅ Floating window
- ✅ Text injection (Ctrl+V simulation)
- ✅ System tray icon
- ✅ Settings/model management

### Known Limitations
- Window transparency may have minor visual artifacts on some Windows versions
- Text injection (Ctrl+V) may fail on:
  - Windows Sandbox / VM environments
  - Machines with strict antivirus policies
  - Some enterprise security software
- Solution: Manually paste using Ctrl+V in the target application

### Requirements
- Windows 10 or later
- Microphone
- ~1-2 GB free disk space (for models)

### Build Instructions
```bash
flutter config --enable-windows-desktop
flutter pub get
flutter build windows --release
```

The Release build will be in: `build/windows/x64/runner/Release/`

### First Run
1. Grant microphone permission when prompted
2. Download a whisper model in Settings
3. Test with Alt+Space to start recording
```

---

## Next Steps

1. **Compile whisper.cpp** (1 day)
   - Run CMake build on Windows
   - Verify whisper-cli.exe works manually

2. **Update Dart code** (1-2 hours)
   - Update dictation_service.dart for .exe extension
   - Verify permission_service.dart already works

3. **Test on Windows** (1 day)
   - Run flutter run on Windows VM/machine
   - Test all features per checklist
   - Fix any issues

4. **Document** (2-4 hours)
   - Update README
   - Add Windows section
   - Document limitations

**Total: 2-3 days to full Windows support**

---

## Resources

- Flutter Windows Guide: https://docs.flutter.dev/platform-integration/windows
- whisper.cpp GitHub: https://github.com/ggerganov/whisper.cpp
- CMake Documentation: https://cmake.org/cmake/help/latest/
- MSIX Packaging: https://docs.microsoft.com/en-us/windows/msix/


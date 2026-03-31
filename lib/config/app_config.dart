/// Centralized app configuration.
/// Change these values to rebrand the app.
/// See README.md for full customization guide.
class AppConfig {
  // ─── App Identity ─────────────────────────────────
  static const String appName = 'VoiceInk';
  static const String appTagline = 'Local Voice Dictation';
  static const String appVersion = '1.0.3';
  static const String appBuildNumber = '4';
  static const String bundleIdentifier = 'com.voiceink.voiceInk';
  static const String copyright =
      'Copyright © 2026 VoiceInk. All rights reserved.';

  // ─── About / Credits ───────────────────────────────
  static const String repoUrl = 'https://github.com/iambaljeet/VoiceInk';
  static const String authorLinkedIn =
      'https://www.linkedin.com/in/devbaljeet';
  static const String authorName = 'Baljeet';
  static const String websiteUrl = 'https://iambaljeet.github.io/VoiceInk/';

  // ─── Tray / System ────────────────────────────────
  /// Asset path for the menu bar (system tray) icon.
  /// Replace `assets/tray_icon.png` with your own 22×22 (or 44×44 @2x) PNG.
  static const String trayIconAsset = 'assets/tray_icon.png';

  /// Tooltip shown when hovering over the tray icon.
  static const String trayTooltip = '$appName — $appTagline';

  // ─── Default Language ─────────────────────────────
  /// Language code used for whisper transcription.
  /// Set during onboarding, persisted in SharedPreferences.
  static const String defaultLanguage = 'en';

  // ─── Supported Languages ──────────────────────────
  /// Languages shown in onboarding and settings.
  /// id: Whisper language code, name: display name, nativeName: in native script.
  static const List<LanguageOption> supportedLanguages = [
    LanguageOption(id: 'en', name: 'English', nativeName: 'English'),
    LanguageOption(id: 'zh', name: 'Chinese', nativeName: '中文'),
    LanguageOption(id: 'de', name: 'German', nativeName: 'Deutsch'),
    LanguageOption(id: 'es', name: 'Spanish', nativeName: 'Español'),
    LanguageOption(id: 'ru', name: 'Russian', nativeName: 'Русский'),
    LanguageOption(id: 'ko', name: 'Korean', nativeName: '한국어'),
    LanguageOption(id: 'fr', name: 'French', nativeName: 'Français'),
    LanguageOption(id: 'ja', name: 'Japanese', nativeName: '日本語'),
    LanguageOption(id: 'pt', name: 'Portuguese', nativeName: 'Português'),
    LanguageOption(id: 'tr', name: 'Turkish', nativeName: 'Türkçe'),
    LanguageOption(id: 'pl', name: 'Polish', nativeName: 'Polski'),
    LanguageOption(id: 'nl', name: 'Dutch', nativeName: 'Nederlands'),
    LanguageOption(id: 'ar', name: 'Arabic', nativeName: 'العربية'),
    LanguageOption(id: 'sv', name: 'Swedish', nativeName: 'Svenska'),
    LanguageOption(id: 'it', name: 'Italian', nativeName: 'Italiano'),
    LanguageOption(id: 'hi', name: 'Hindi', nativeName: 'हिन्दी'),
    LanguageOption(id: 'fi', name: 'Finnish', nativeName: 'Suomi'),
    LanguageOption(id: 'vi', name: 'Vietnamese', nativeName: 'Tiếng Việt'),
    LanguageOption(id: 'uk', name: 'Ukrainian', nativeName: 'Українська'),
    LanguageOption(id: 'el', name: 'Greek', nativeName: 'Ελληνικά'),
    LanguageOption(id: 'cs', name: 'Czech', nativeName: 'Čeština'),
    LanguageOption(id: 'ro', name: 'Romanian', nativeName: 'Română'),
    LanguageOption(id: 'da', name: 'Danish', nativeName: 'Dansk'),
    LanguageOption(id: 'hu', name: 'Hungarian', nativeName: 'Magyar'),
    LanguageOption(id: 'ta', name: 'Tamil', nativeName: 'தமிழ்'),
    LanguageOption(id: 'th', name: 'Thai', nativeName: 'ไทย'),
    LanguageOption(id: 'ur', name: 'Urdu', nativeName: 'اردو'),
    LanguageOption(id: 'hr', name: 'Croatian', nativeName: 'Hrvatski'),
    LanguageOption(id: 'bg', name: 'Bulgarian', nativeName: 'Български'),
    LanguageOption(id: 'sk', name: 'Slovak', nativeName: 'Slovenčina'),
    LanguageOption(id: 'te', name: 'Telugu', nativeName: 'తెలుగు'),
    LanguageOption(id: 'fa', name: 'Persian', nativeName: 'فارسی'),
    LanguageOption(id: 'bn', name: 'Bengali', nativeName: 'বাংলা'),
    LanguageOption(id: 'pa', name: 'Punjabi', nativeName: 'ਪੰਜਾਬੀ'),
  ];
}

class LanguageOption {
  final String id;
  final String name;
  final String nativeName;
  const LanguageOption({
    required this.id,
    required this.name,
    required this.nativeName,
  });
}

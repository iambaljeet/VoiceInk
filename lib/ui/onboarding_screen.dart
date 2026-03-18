import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import '../config/app_config.dart';
import '../services/stt_engine_manager.dart';
import '../services/permission_service.dart';
import '../services/audio_device_service.dart';
import '../services/hotkey_service.dart';
import '../services/model_manager.dart';
import '../models/whisper_model.dart';

const _bgColor = Color(0xFF1a1a2e);
const _accentColor = Color(0xFF3B82F6);

/// Full-screen onboarding wizard shown on first launch.
/// Pages: Welcome → Engine → (Language+Model) → Permissions → Mic → Shortcut
class OnboardingScreen extends StatefulWidget {
  final PermissionService permissions;
  final AudioDeviceService audioDevice;
  final HotkeyService hotkeyService;
  final VoidCallback onComplete;
  final SttEngineManager? engineManager;
  final ModelManager? modelManager;

  const OnboardingScreen({
    super.key,
    required this.permissions,
    required this.audioDevice,
    required this.hotkeyService,
    required this.onComplete,
    this.engineManager,
    this.modelManager,
  });

  /// Returns true if onboarding has been completed before.
  static Future<bool> isComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('onboarding_complete') ?? false;
  }

  /// Mark onboarding as complete.
  static Future<void> markComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _page = 0;
  SttEngine _selectedEngine = SttEngine.native;
  Timer? _permPoll;

  // Total pages: 0=Welcome, 1=Engine, 2=Lang+Model, 3=Permissions, 4=Mic, 5=Shortcut
  static const _totalPages = 6;

  @override
  void initState() {
    super.initState();
    _setupWindow();
  }

  Future<void> _setupWindow() async {
    await windowManager.setSize(const Size(520, 620));
    await windowManager.setMinimumSize(const Size(520, 620));
    await windowManager.setMaximumSize(const Size(520, 620));
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden,
        windowButtonVisibility: false);
    await windowManager.setBackgroundColor(_bgColor);
    await windowManager.setHasShadow(true);
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  void dispose() {
    _permPoll?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _onEngineChanged(SttEngine engine) {
    setState(() => _selectedEngine = engine);
  }

  /// Map actual page index → visual step index (skips page 2 for native).
  int get _visualStep {
    if (_selectedEngine == SttEngine.native && _page > 1) {
      return _page - 1; // skip the lang+model dot
    }
    return _page;
  }

  int get _visiblePageCount =>
      _selectedEngine == SttEngine.native ? _totalPages - 1 : _totalPages;

  void _next() {
    if (_page >= _totalPages - 1) return;
    int target = _page + 1;
    // Skip page 2 (lang+model) when using native engine
    if (_page == 1 && _selectedEngine == SttEngine.native) {
      target = 3;
    }
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _back() {
    if (_page <= 0) return;
    int target = _page - 1;
    // Skip page 2 (lang+model) when going back with native engine
    if (_page == 3 && _selectedEngine == SttEngine.native) {
      target = 1;
    }
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _finish() async {
    await OnboardingScreen.markComplete();
    widget.audioDevice.stopMicTest();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: GestureDetector(
        onPanStart: (_) => windowManager.startDragging(),
        child: Column(
          children: [
            const SizedBox(height: 20),
            _StepIndicator(
              currentStep: _visualStep,
              totalSteps: _visiblePageCount,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _WelcomePage(onNext: _next),
                  _EngineSelectionPage(
                    engineManager: widget.engineManager,
                    onNext: _next,
                    onBack: _back,
                    onEngineChanged: _onEngineChanged,
                  ),
                  _LanguageModelPage(
                    modelManager: widget.modelManager,
                    onNext: _next,
                    onBack: _back,
                  ),
                  _PermissionsPage(
                    permissions: widget.permissions,
                    onNext: _next,
                    onBack: _back,
                    onPollStart: () {
                      _permPoll?.cancel();
                      _permPoll = Timer.periodic(
                        const Duration(seconds: 2),
                        (_) async {
                          await widget.permissions.checkAll();
                          if (mounted) setState(() {});
                        },
                      );
                    },
                    onPollStop: () {
                      _permPoll?.cancel();
                    },
                  ),
                  _MicSetupPage(
                    audioDevice: widget.audioDevice,
                    onNext: _next,
                    onBack: _back,
                  ),
                  _ShortcutPage(
                    hotkeyService: widget.hotkeyService,
                    onFinish: _finish,
                    onBack: _back,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Step indicator ─────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  const _StepIndicator({required this.currentStep, required this.totalSteps});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(totalSteps, (i) {
        final isActive = i <= currentStep;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: i == currentStep ? 28 : 10,
          height: 10,
          decoration: BoxDecoration(
            color: isActive ? _accentColor : Colors.white24,
            borderRadius: BorderRadius.circular(5),
          ),
        );
      }),
    );
  }
}

// ─── Page 0: Welcome ─────────────────────────────────────

class _WelcomePage extends StatelessWidget {
  final VoidCallback onNext;
  const _WelcomePage({required this.onNext});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.mic, size: 64, color: _accentColor),
          const SizedBox(height: 20),
          Text(
            'Welcome to ${AppConfig.appName}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Local voice dictation that stays on your device.\n'
            'Hold a shortcut key to speak — release to type.\n'
            'All processing happens privately on your machine.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: 200,
            height: 44,
            child: ElevatedButton(
              onPressed: onNext,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Get Started', style: TextStyle(fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Page 1: Engine Selection ────────────────────────────

class _EngineSelectionPage extends StatefulWidget {
  final SttEngineManager? engineManager;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final ValueChanged<SttEngine> onEngineChanged;

  const _EngineSelectionPage({
    required this.engineManager,
    required this.onNext,
    required this.onBack,
    required this.onEngineChanged,
  });

  @override
  State<_EngineSelectionPage> createState() => _EngineSelectionPageState();
}

class _EngineSelectionPageState extends State<_EngineSelectionPage> {
  SttEngine _selected = SttEngine.native;

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('stt_engine');
    if (saved == 'model' && mounted) {
      setState(() => _selected = SttEngine.model);
      widget.onEngineChanged(SttEngine.model);
    }
  }

  Future<void> _selectEngine(SttEngine engine) async {
    setState(() => _selected = engine);
    widget.onEngineChanged(engine);
    if (widget.engineManager != null) {
      await widget.engineManager!.setEngine(engine);
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'stt_engine', engine == SttEngine.model ? 'model' : 'native');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          const Text('Speech Engine',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Choose how your voice is transcribed.',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
          const SizedBox(height: 24),
          _engineCard(
            engine: SttEngine.native,
            icon: Icons.record_voice_over,
            title: 'System Speech',
            subtitle:
                "Uses your operating system's built-in speech recognition",
            pros: [
              'No setup or downloads needed',
              'Low battery and memory usage',
              'Great for everyday dictation',
              'Works instantly',
            ],
            cons: [
              'Accuracy varies by OS',
              'Limited language support',
              'May need internet on some systems',
            ],
          ),
          const SizedBox(height: 12),
          _engineCard(
            engine: SttEngine.model,
            icon: Icons.psychology,
            title: 'AI Model (Whisper)',
            subtitle: 'Runs a local AI model for high-quality transcription',
            pros: [
              'Highly accurate transcription',
              '100% offline — zero data leaves your device',
              '52+ languages supported',
              'Best for professional and multilingual use',
            ],
            cons: [
              'Requires one-time model download (75 MB–1.5 GB)',
              'Uses more memory and battery',
              'Slightly higher CPU usage while transcribing',
            ],
          ),
          const Spacer(),
          Row(
            children: [
              TextButton(
                onPressed: widget.onBack,
                child: const Text('Back'),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: widget.onNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Next'),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _engineCard({
    required SttEngine engine,
    required IconData icon,
    required String title,
    required String subtitle,
    required List<String> pros,
    required List<String> cons,
  }) {
    final selected = _selected == engine;
    return GestureDetector(
      onTap: () => _selectEngine(engine),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? _accentColor.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? _accentColor.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected ? _accentColor : Colors.white38,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Icon(icon,
                    color: selected
                        ? _accentColor
                        : Colors.white.withValues(alpha: 0.6),
                    size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                              fontSize: 15)),
                      Text(subtitle,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: pros
                        .map((p) => Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Icon(Icons.add_circle_outline,
                                        color: Colors.green
                                            .withValues(alpha: 0.7),
                                        size: 12),
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(p,
                                        style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: 0.6),
                                            fontSize: 11)),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: cons
                        .map((c) => Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Icon(Icons.remove_circle_outline,
                                        color: Colors.orange
                                            .withValues(alpha: 0.7),
                                        size: 12),
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(c,
                                        style: TextStyle(
                                            color: Colors.white
                                                .withValues(alpha: 0.6),
                                            fontSize: 11)),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Page 2: Language + Model Download ───────────────────

class _LanguageModelPage extends StatefulWidget {
  final ModelManager? modelManager;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const _LanguageModelPage({
    required this.modelManager,
    required this.onNext,
    required this.onBack,
  });

  @override
  State<_LanguageModelPage> createState() => _LanguageModelPageState();
}

class _LanguageModelPageState extends State<_LanguageModelPage> {
  String _selectedLang = 'en';
  String _search = '';
  String? _downloadError;

  @override
  void initState() {
    super.initState();
    _loadSaved();
    widget.modelManager?.addListener(_onModelChange);
    _initModelManager();
  }

  Future<void> _initModelManager() async {
    if (widget.modelManager != null) {
      await widget.modelManager!.init();
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    widget.modelManager?.removeListener(_onModelChange);
    super.dispose();
  }

  void _onModelChange() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('whisper_language');
    if (saved != null && mounted) {
      setState(() => _selectedLang = saved);
    }
  }

  Future<void> _selectLanguage(String id) async {
    setState(() => _selectedLang = id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('whisper_language', id);
  }

  bool get _isEnglish => _selectedLang == 'en';

  List<WhisperModel> get _filteredModels {
    if (_isEnglish) {
      // Show .en models first, then multilingual
      final en = WhisperModel.available
          .where((m) => m.id.endsWith('.en'))
          .toList();
      final multi = WhisperModel.available
          .where((m) => !m.id.endsWith('.en'))
          .toList();
      return [...en, ...multi];
    } else {
      // Hide .en variants for non-English languages
      return WhisperModel.available
          .where((m) => !m.id.endsWith('.en'))
          .toList();
    }
  }

  String _modelRecommendation(WhisperModel model) {
    if (_isEnglish && model.id.endsWith('.en')) {
      if (model.id == 'base.en') return '⭐ Recommended';
      return '⭐ English-optimized';
    }
    if (!_isEnglish && model.id == 'base') return '⭐ Recommended';
    return '';
  }

  List<LanguageOption> get _filteredLanguages {
    if (_search.isEmpty) return AppConfig.supportedLanguages;
    final q = _search.toLowerCase();
    return AppConfig.supportedLanguages.where((l) {
      return l.name.toLowerCase().contains(q) ||
          l.nativeName.toLowerCase().contains(q) ||
          l.id.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _downloadModel(WhisperModel model) async {
    if (widget.modelManager == null) return;
    setState(() => _downloadError = null);
    try {
      await widget.modelManager!.downloadModel(model);
    } catch (e) {
      if (mounted) setState(() => _downloadError = e.toString());
    }
  }

  void _onNextPressed() {
    final mm = widget.modelManager;
    final hasModel = mm != null && mm.downloadedModels.isNotEmpty;
    if (!hasModel) {
      // Show warning but allow proceeding
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.amber.shade800,
          content: const Text(
            "You'll need to download a model from Settings to use AI transcription.",
            style: TextStyle(color: Colors.white),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          const Text('Language & Model',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Choose your primary language and download a model.',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
          const SizedBox(height: 12),

          // Search bar
          Container(
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: TextField(
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search languages...',
                hintStyle:
                    TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                prefixIcon: Icon(Icons.search,
                    color: Colors.white.withValues(alpha: 0.3), size: 18),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          const SizedBox(height: 8),

          // Language grid (compact, 2 columns)
          SizedBox(
            height: 120,
            child: GridView.builder(
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 3.2,
              ),
              itemCount: _filteredLanguages.length,
              itemBuilder: (context, i) {
                final lang = _filteredLanguages[i];
                final selected = lang.id == _selectedLang;
                return GestureDetector(
                  onTap: () => _selectLanguage(lang.id),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: selected
                          ? _accentColor.withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? _accentColor.withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${lang.nativeName}${lang.name != lang.nativeName ? ' (${lang.name})' : ''}',
                            style: TextStyle(
                                color: selected
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.7),
                                fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (selected)
                          Icon(Icons.check_circle,
                              color: _accentColor, size: 14),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 12),
          Divider(color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 8),

          // Model section header
          Text('Recommended Models',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),

          if (_downloadError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_downloadError!,
                  style: TextStyle(
                      color: Colors.red.withValues(alpha: 0.9), fontSize: 11)),
            ),

          // Model list
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: _filteredModels.length,
              itemBuilder: (context, i) {
                final model = _filteredModels[i];
                return _modelCard(model);
              },
            ),
          ),

          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: widget.onBack,
                child: const Text('Back'),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _onNextPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Next'),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _modelCard(WhisperModel model) {
    final mm = widget.modelManager;
    final isDownloaded = mm?.isDownloaded(model.id) ?? false;
    final isDownloading = mm?.isDownloading(model.id) ?? false;
    final progress = mm?.getProgress(model.id) ?? 0.0;
    final isSelected = mm?.selectedModelId == model.id;
    final rec = _modelRecommendation(model);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isSelected
            ? _accentColor.withValues(alpha: 0.1)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected
              ? _accentColor.withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(model.name,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(width: 6),
                        Text(model.sizeLabel,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4),
                                fontSize: 11)),
                      ],
                    ),
                    if (rec.isNotEmpty)
                      Text(rec,
                          style: TextStyle(
                              color: Colors.amber.withValues(alpha: 0.9),
                              fontSize: 10)),
                  ],
                ),
              ),
              if (isDownloaded && isSelected)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('✓ Selected',
                      style: TextStyle(color: Colors.green, fontSize: 11)),
                )
              else if (isDownloaded)
                ElevatedButton(
                  onPressed: () => mm?.selectModel(model.id),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentColor,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                  ),
                  child: const Text('Select', style: TextStyle(fontSize: 11)),
                )
              else if (isDownloading)
                const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                ElevatedButton(
                  onPressed: () => _downloadModel(model),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentColor,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    minimumSize: Size.zero,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                  ),
                  child:
                      const Text('Download', style: TextStyle(fontSize: 11)),
                ),
            ],
          ),
          Text(model.description,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4), fontSize: 11)),
          if (isDownloading)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(_accentColor),
                minHeight: 3,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Page 3: Permissions ─────────────────────────────────

class _PermissionsPage extends StatefulWidget {
  final PermissionService permissions;
  final VoidCallback onNext;
  final VoidCallback onBack;
  final VoidCallback onPollStart;
  final VoidCallback onPollStop;

  const _PermissionsPage({
    required this.permissions,
    required this.onNext,
    required this.onBack,
    required this.onPollStart,
    required this.onPollStop,
  });

  @override
  State<_PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<_PermissionsPage> {
  @override
  void initState() {
    super.initState();
    widget.permissions.checkAll().then((_) {
      if (mounted) setState(() {});
    });
    widget.onPollStart();
  }

  @override
  void dispose() {
    widget.onPollStop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.permissions;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          const Text('Permissions',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(
              '${AppConfig.appName} needs a couple of permissions to work properly.',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
          const SizedBox(height: 24),
          _permCard(
            icon: Icons.mic,
            title: 'Microphone Access',
            subtitle:
                'Lets ${AppConfig.appName} hear your voice. Your audio is '
                'processed locally and never sent anywhere.',
            granted: p.micGranted,
            buttonLabel: 'Grant Access',
            onTap: () async {
              await p.checkMicrophone();
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(height: 12),
          _permCard(
            icon: Icons.keyboard_alt_outlined,
            title: 'Accessibility / Input Monitoring',
            subtitle: Platform.isMacOS
                ? 'Allows ${AppConfig.appName} to type transcribed text '
                    'directly into any text field in any app.'
                : 'Allows ${AppConfig.appName} to simulate keyboard '
                    'input to type text.',
            granted: p.accessibilityGranted,
            buttonLabel: 'Open Settings',
            onTap: () => p.openAccessibilitySettings(),
          ),
          const Spacer(),
          Row(
            children: [
              TextButton(
                onPressed: widget.onBack,
                child: const Text('Back'),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: p.allGranted ? widget.onNext : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.white12,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Next'),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _permCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool granted,
    required String buttonLabel,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: granted
              ? Colors.green.withValues(alpha: 0.4)
              : Colors.orange.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(granted ? Icons.check_circle : icon,
              color: granted ? Colors.green : Colors.orange, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(subtitle,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                        height: 1.4)),
                if (granted)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('✓ Granted',
                        style: TextStyle(
                            color: Colors.green.withValues(alpha: 0.9),
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                  ),
                if (!granted)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ElevatedButton(
                      onPressed: onTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text(buttonLabel,
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Page 4: Mic Setup ──────────────────────────────────

class _MicSetupPage extends StatefulWidget {
  final AudioDeviceService audioDevice;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const _MicSetupPage({
    required this.audioDevice,
    required this.onNext,
    required this.onBack,
  });

  @override
  State<_MicSetupPage> createState() => _MicSetupPageState();
}

class _MicSetupPageState extends State<_MicSetupPage> {
  @override
  void initState() {
    super.initState();
    widget.audioDevice.addListener(_update);
    widget.audioDevice.refreshDevices();
  }

  @override
  void dispose() {
    widget.audioDevice.removeListener(_update);
    widget.audioDevice.stopMicTest();
    super.dispose();
  }

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ad = widget.audioDevice;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          const Text('Microphone Setup',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Select your mic and verify it is working.',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
          const SizedBox(height: 24),

          // Device picker
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: DropdownButton<String>(
              value: ad.selectedDevice?.id,
              hint: const Text('System Default',
                  style: TextStyle(color: Colors.white54)),
              isExpanded: true,
              dropdownColor: const Color(0xFF222244),
              underline: const SizedBox.shrink(),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('System Default'),
                ),
                ...ad.devices.map((d) => DropdownMenuItem(
                      value: d.id,
                      child: Text(d.label, overflow: TextOverflow.ellipsis),
                    )),
              ],
              onChanged: (id) {
                if (id == null) {
                  ad.selectDevice(null);
                } else {
                  final device = ad.devices.firstWhere((d) => d.id == id);
                  ad.selectDevice(device);
                }
              },
            ),
          ),
          const SizedBox(height: 24),

          // Level meter
          const Text('Audio Level',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 8),
          _MicLevelBar(level: ad.level),
          const SizedBox(height: 16),

          // Test button
          Center(
            child: ElevatedButton.icon(
              onPressed: () {
                if (ad.isTesting) {
                  ad.stopMicTest();
                } else {
                  ad.startMicTest();
                }
              },
              icon: Icon(ad.isTesting ? Icons.stop : Icons.mic),
              label: Text(ad.isTesting ? 'Stop Test' : 'Test Microphone'),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    ad.isTesting ? Colors.red.shade700 : _accentColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          if (ad.isTesting)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Center(
                child: Text(
                  ad.level > 0.02
                      ? '✓ Microphone is working!'
                      : 'Speak to test your microphone...',
                  style: TextStyle(
                    color: ad.level > 0.02 ? Colors.green : Colors.white54,
                    fontSize: 13,
                  ),
                ),
              ),
            ),

          const Spacer(),
          Row(
            children: [
              TextButton(
                onPressed: () {
                  ad.stopMicTest();
                  widget.onBack();
                },
                child: const Text('Back'),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () {
                  ad.stopMicTest();
                  widget.onNext();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Next'),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ─── Page 5: Shortcut Test ──────────────────────────────

class _ShortcutPage extends StatefulWidget {
  final HotkeyService hotkeyService;
  final VoidCallback onFinish;
  final VoidCallback onBack;

  const _ShortcutPage({
    required this.hotkeyService,
    required this.onFinish,
    required this.onBack,
  });

  @override
  State<_ShortcutPage> createState() => _ShortcutPageState();
}

class _ShortcutPageState extends State<_ShortcutPage> {
  bool _tested = false;

  @override
  void initState() {
    super.initState();
    widget.hotkeyService.addListener(_update);
    // Register a test handler
    widget.hotkeyService.registerPushToTalk(
      () async {
        // keyDown — just mark as tested
        if (!_tested) {
          _tested = true;
          if (mounted) setState(() {});
        }
      },
      () async {
        // keyUp — nothing to do in test mode
      },
    );
  }

  @override
  void dispose() {
    widget.hotkeyService.removeListener(_update);
    widget.hotkeyService.unregister();
    super.dispose();
  }

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hs = widget.hotkeyService;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          const Text('Shortcut Key',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Hold the shortcut to speak, release to type.',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 13)),
          const SizedBox(height: 24),

          // Preset picker
          ...ShortcutPreset.values.map((preset) {
            final selected = hs.preset == preset;
            return GestureDetector(
              onTap: () async {
                _tested = false;
                await hs.setPreset(preset);
                // Re-register test handler
                await hs.registerPushToTalk(
                  () async {
                    _tested = true;
                    if (mounted) setState(() {});
                  },
                  () async {},
                );
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: selected
                      ? _accentColor.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: selected
                        ? _accentColor.withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: selected ? _accentColor : Colors.white38,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(preset.label,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w500,
                                fontSize: 15)),
                        Text(preset.description,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 20),

          // Test area
          Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 180,
              height: 60,
              decoration: BoxDecoration(
                color: hs.isPressed
                    ? Colors.green.withValues(alpha: 0.3)
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: hs.isPressed
                      ? Colors.green
                      : _tested
                          ? Colors.green.withValues(alpha: 0.5)
                          : Colors.white.withValues(alpha: 0.15),
                  width: hs.isPressed ? 2 : 1,
                ),
              ),
              child: Center(
                child: Text(
                  hs.isPressed
                      ? '🎙️ Listening...'
                      : _tested
                          ? '✓ Shortcut works!'
                          : 'Press ${hs.preset.label} to test',
                  style: TextStyle(
                    color: hs.isPressed
                        ? Colors.green
                        : _tested
                            ? Colors.green
                            : Colors.white54,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),

          const Spacer(),
          Row(
            children: [
              TextButton(
                onPressed: widget.onBack,
                child: const Text('Back'),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: widget.onFinish,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accentColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: Text('Start Using ${AppConfig.appName}'),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ─── Shared widget: Mic Level Bar ───────────────────────

class MicLevelBar extends StatelessWidget {
  final double level;
  const MicLevelBar({super.key, required this.level});
  @override
  Widget build(BuildContext context) => _MicLevelBar(level: level);
}

class _MicLevelBar extends StatelessWidget {
  final double level;
  const _MicLevelBar({required this.level});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            AnimatedFractionallySizedBox(
              duration: const Duration(milliseconds: 80),
              widthFactor: level.clamp(0.0, 1.0),
              alignment: Alignment.centerLeft,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.green,
                      level > 0.6 ? Colors.orange : Colors.green.shade300,
                      if (level > 0.8) Colors.red,
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

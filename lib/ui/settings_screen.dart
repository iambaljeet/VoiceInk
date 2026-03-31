import 'dart:io';
import 'package:flutter/material.dart';
import '../models/whisper_model.dart';
import '../models/sherpa_model.dart';
import '../models/writing_style.dart';
import '../services/model_manager.dart';
import '../services/sherpa_model_manager.dart';
import '../services/dictation_service.dart';
import '../services/stt_engine_manager.dart';
import '../services/whisper_streaming_service.dart';
import '../services/hotkey_service.dart';
import '../services/audio_device_service.dart';
import '../services/stats_service.dart';
import 'onboarding_screen.dart';
import 'dictionary_screen.dart';

import '../config/app_config.dart';

class SettingsScreen extends StatefulWidget {
  final ModelManager modelManager;
  final SherpaModelManager? sherpaModelManager;
  final DictationService dictationService;
  final SttEngineManager? engineManager;
  final WhisperStreamingService? whisperStreaming;
  final HotkeyService? hotkeyService;
  final AudioDeviceService? audioDevice;
  final bool capsuleBorderVisible;
  final ValueChanged<bool>? onCapsuleBorderChanged;

  const SettingsScreen({
    super.key,
    required this.modelManager,
    this.sherpaModelManager,
    required this.dictationService,
    this.engineManager,
    this.whisperStreaming,
    this.hotkeyService,
    this.audioDevice,
    this.capsuleBorderVisible = true,
    this.onCapsuleBorderChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    widget.sherpaModelManager?.addListener(_rebuild);
    widget.engineManager?.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.sherpaModelManager?.removeListener(_rebuild);
    widget.engineManager?.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a1a2e),
      appBar: AppBar(
        title: Text('${AppConfig.appName} Settings'),
        backgroundColor: const Color(0xFF16213e),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListenableBuilder(
        listenable: widget.modelManager,
        builder: (context, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Stats & Streaks (top of settings) ──
                _buildSectionHeader('Stats & Streaks'),
                const SizedBox(height: 8),
                _buildStatsSection(),
                const SizedBox(height: 32),

                // STT Provider selection
                if (widget.engineManager != null) ...[
                  _buildSectionHeader('STT Provider'),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose the speech-to-text engine for transcription.',
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  ...SttProvider.values.map((provider) => _buildProviderCard(provider)),
                  const SizedBox(height: 24),
                ],
                // Show models based on selected provider
                if (widget.engineManager?.provider == SttProvider.whisperCpp) ...[
                  _buildSectionHeader('Speech Models (Whisper.cpp)'),
                  const SizedBox(height: 8),
                  const Text(
                    'Download and manage Whisper models. Larger models are more accurate but slower.\nTap a downloaded model to select it as active.',
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  ...WhisperModel.available.map(_buildModelCard),
                ] else if (widget.engineManager?.provider == SttProvider.sherpaOnnx) ...[
                  _buildSectionHeader('Speech Models (Sherpa-ONNX)'),
                  const SizedBox(height: 8),
                  const Text(
                    'Download and manage Sherpa-ONNX models. Uses native FFI for fast inference.\nTap a downloaded model to select it as active.',
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  ...SherpaModel.available.map(_buildSherpaModelCard),
                ],
                const SizedBox(height: 32),
                _buildSectionHeader('Text Cleanup'),
                const SizedBox(height: 16),
                _buildToggle(
                  'Remove filler words',
                  'Removes "um", "uh", "like" etc.',
                  widget.dictationService.cleanup.removeFillers,
                  (v) {
                    setState(() {
                      widget.dictationService.cleanup.removeFillers = v;
                    });
                    widget.dictationService.savePreferences();
                  },
                ),
                _buildToggle(
                  'Skip non-speech sounds',
                  'Removes (laughing), (clicking), [BLANK_AUDIO] etc.',
                  widget.dictationService.cleanup.skipNonSpeech,
                  (v) {
                    setState(() {
                      widget.dictationService.cleanup.skipNonSpeech = v;
                    });
                    widget.dictationService.savePreferences();
                  },
                ),
                _buildToggle(
                  'Convert spoken punctuation',
                  '"comma" → "," / "period" → "." etc.',
                  widget.dictationService.cleanup.convertPunctuation,
                  (v) {
                    setState(() {
                      widget.dictationService.cleanup.convertPunctuation = v;
                    });
                    widget.dictationService.savePreferences();
                  },
                ),
                _buildToggle(
                  'Auto-capitalize',
                  'Capitalize first letter of sentences.',
                  widget.dictationService.cleanup.autoCapitalize,
                  (v) {
                    setState(() {
                      widget.dictationService.cleanup.autoCapitalize = v;
                    });
                    widget.dictationService.savePreferences();
                  },
                ),
                const SizedBox(height: 32),

                // ── Writing Style ──
                _buildSectionHeader('Writing Style'),
                const SizedBox(height: 8),
                const Text(
                  'Choose how your transcriptions are formatted.',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
                const SizedBox(height: 12),
                ...WritingStyle.values.map((style) {
                  final isSelected = widget.dictationService.writingStyle == style;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        widget.dictationService.writingStyle = style;
                      });
                      widget.dictationService.savePreferences();
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF3B82F6).withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF3B82F6).withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                            color: isSelected ? const Color(0xFF3B82F6) : Colors.white38,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(style.label,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500,
                                        fontSize: 15)),
                                Text(style.description,
                                    style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.5),
                                        fontSize: 11)),
                              ],
                            ),
                          ),
                          if (isSelected)
                            const Text('Active',
                                style: TextStyle(
                                    color: Color(0xFF3B82F6),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12)),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 32),

                // ── Custom Dictionary ──
                _buildSectionHeader('Custom Dictionary'),
                const SizedBox(height: 8),
                const Text(
                  'Add word replacement rules for auto-correction and custom terms.',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
                const SizedBox(height: 12),
                _buildToggle(
                  'Enable dictionary',
                  'Apply custom word replacements to transcriptions.',
                  widget.dictationService.dictionary.isEnabled,
                  (v) {
                    setState(() {
                      widget.dictationService.dictionary.isEnabled = v;
                    });
                    widget.dictationService.savePreferences();
                  },
                ),
                const SizedBox(height: 8),
                Center(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const DictionaryScreen(),
                      ));
                    },
                    icon: const Icon(Icons.book_outlined, size: 16),
                    label: const Text('Manage Dictionary', style: TextStyle(fontSize: 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Only show keyboard shortcut & mic sections on desktop
                ...[
                  // ── Microphone Selection ──
                  if (widget.audioDevice != null) ...[
                    const SizedBox(height: 32),
                    _buildSectionHeader('Microphone'),
                    const SizedBox(height: 8),
                    const Text(
                      'Select which microphone to use for dictation.',
                      style: TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    _buildMicSection(),
                  ],
                  // ── Shortcut Key ──
                  if (widget.hotkeyService != null) ...[
                    const SizedBox(height: 32),
                    _buildSectionHeader('Shortcut Key'),
                    const SizedBox(height: 8),
                    const Text(
                      'Hold the shortcut to speak, release to type.',
                      style: TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    _buildShortcutSection(),
                  ],
                ],
                // ── Appearance ──
                const SizedBox(height: 32),
                _buildSectionHeader('Appearance'),
                const SizedBox(height: 8),
                const Text(
                  'Customise how the floating indicator looks.',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
                const SizedBox(height: 12),
                _buildToggle(
                  'More visibility',
                  'Adds a thin border around the floating capsule so it\'s easier to spot.',
                  widget.capsuleBorderVisible,
                  (v) {
                    widget.onCapsuleBorderChanged?.call(v);
                  },
                ),
                const SizedBox(height: 32),
                _buildSectionHeader('About'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${AppConfig.appName} v${AppConfig.appVersion}',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Local voice dictation powered by whisper.cpp.\n'
                        'All processing happens on your device — no data is sent to the cloud.',
                        style: TextStyle(color: Colors.white60, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildModelCard(WhisperModel model) {
    final isDownloaded = widget.modelManager.isDownloaded(model.id);
    final isDownloading = widget.modelManager.isDownloading(model.id);
    final isSelected = widget.modelManager.selectedModelId == model.id;
    final progress = widget.modelManager.getProgress(model.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.blue.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? Colors.blue.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: isDownloaded
            ? Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: isSelected ? Colors.blue : Colors.white38,
              )
            : const Icon(Icons.cloud_download_outlined, color: Colors.white38),
        title: Text(
          model.name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${model.description} (${model.sizeLabel})',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            if (isDownloading && progress != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white12,
                  color: Colors.blue,
                ),
              ),
          ],
        ),
        trailing: _buildModelAction(model, isDownloaded, isDownloading, isSelected),
        onTap: isDownloaded
            ? () {
                widget.modelManager.selectModel(model.id);
                widget.dictationService.savePreferences();
              }
            : null,
      ),
    );
  }

  Widget? _buildModelAction(
    WhisperModel model,
    bool isDownloaded,
    bool isDownloading,
    bool isSelected,
  ) {
    if (isDownloading) {
      return IconButton(
        icon: const Icon(Icons.cancel, color: Colors.white54),
        onPressed: () => widget.modelManager.cancelDownload(),
      );
    }
    if (isDownloaded) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSelected)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Text(
                'Active',
                style: TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          if (!isSelected)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white38),
              onPressed: () => widget.modelManager.deleteModel(model.id),
            ),
        ],
      );
    }
    return TextButton(
      onPressed: () => widget.modelManager.downloadModel(model),
      child: const Text('Download'),
    );
  }

  Widget _buildSherpaModelCard(SherpaModel model) {
    final sm = widget.sherpaModelManager;
    if (sm == null) return const SizedBox.shrink();
    final isDownloaded = sm.isDownloaded(model.id);
    final isDownloading = sm.isDownloading(model.id);
    final isSelected = sm.selectedModelId == model.id;
    final progress = sm.getProgress(model.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.blue.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? Colors.blue.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: isDownloaded
            ? Icon(
                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: isSelected ? Colors.blue : Colors.white38,
              )
            : const Icon(Icons.cloud_download_outlined, color: Colors.white38),
        title: Text(
          model.name,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${model.description} (${model.sizeLabel})',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            if (isDownloading && progress != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white12,
                  color: Colors.blue,
                ),
              ),
          ],
        ),
        trailing: _buildSherpaModelAction(model, isDownloaded, isDownloading, isSelected),
        onTap: isDownloaded ? () => sm.selectModel(model.id) : null,
      ),
    );
  }

  Widget? _buildSherpaModelAction(
    SherpaModel model,
    bool isDownloaded,
    bool isDownloading,
    bool isSelected,
  ) {
    final sm = widget.sherpaModelManager;
    if (sm == null) return null;
    if (isDownloading) {
      return IconButton(
        icon: const Icon(Icons.cancel, color: Colors.white54),
        onPressed: () => sm.cancelDownload(),
      );
    }
    if (isDownloaded) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSelected)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Text(
                'Active',
                style: TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          if (!isSelected)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white38),
              onPressed: () => sm.deleteModel(model.id),
            ),
        ],
      );
    }
    return TextButton(
      onPressed: () => sm.downloadModel(model),
      child: const Text('Download'),
    );
  }

  Widget _buildToggle(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: SwitchListTile(
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        value: value,
        onChanged: onChanged,
        activeTrackColor: Colors.blue,
      ),
    );
  }

  Widget _buildProviderCard(SttProvider provider) {
    final mgr = widget.engineManager!;
    final isSelected = mgr.provider == provider;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.blue.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected
              ? Colors.blue.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(
          isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
          color: isSelected ? Colors.blue : Colors.white38,
        ),
        title: Row(
          children: [
            Text(provider.icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(
              provider.label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        subtitle: Text(
          provider.description,
          style: const TextStyle(color: Colors.white60, fontSize: 12),
        ),
        trailing: isSelected
            ? const Text('Active',
                style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.w600,
                    fontSize: 12))
            : null,
        onTap: () {
          mgr.setProvider(provider);
          setState(() {});
        },
      ),
    );
  }

  // ── Microphone Selection ──

  Widget _buildMicSection() {
    final ad = widget.audioDevice!;
    return ListenableBuilder(
      listenable: ad,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Device dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: Colors.white.withValues(alpha: 0.1)),
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
                        child:
                            Text(d.label, overflow: TextOverflow.ellipsis),
                      )),
                ],
                onChanged: (id) {
                  if (id == null) {
                    ad.selectDevice(null);
                  } else {
                    final device =
                        ad.devices.firstWhere((d) => d.id == id);
                    ad.selectDevice(device);
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            // Level meter
            MicLevelBar(level: ad.level),
            const SizedBox(height: 8),
            Center(
              child: ElevatedButton.icon(
                onPressed: () {
                  if (ad.isTesting) {
                    ad.stopMicTest();
                  } else {
                    ad.startMicTest();
                  }
                },
                icon: Icon(ad.isTesting ? Icons.stop : Icons.mic, size: 16),
                label: Text(
                  ad.isTesting ? 'Stop Test' : 'Test Microphone',
                  style: const TextStyle(fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      ad.isTesting ? Colors.red.shade700 : const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            if (ad.isTesting && ad.level > 0.02)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Center(
                  child: Text('✓ Microphone is working!',
                      style: TextStyle(color: Colors.green, fontSize: 12)),
                ),
              ),
            const SizedBox(height: 4),
            Center(
              child: TextButton(
                onPressed: () => ad.refreshDevices(),
                child: const Text('Refresh Devices',
                    style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Stats Section ──

  Widget _buildStatsSection() {
    final stats = StatsService.instance;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildStatTile('Today', '${stats.wordsToday}', 'words'),
              const SizedBox(width: 12),
              _buildStatTile('This Month', '${stats.wordsThisMonth}', 'words'),
              const SizedBox(width: 12),
              _buildStatTile('Total', '${stats.wordsTotal}', 'words'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildStatTile('Streak', '${stats.currentStreak}', 'days'),
              const SizedBox(width: 12),
              _buildStatTile('Best Streak', '${stats.bestStreak}', 'days'),
              const SizedBox(width: 12),
              _buildStatTile('Today', '${stats.transcriptionsToday}', 'transcriptions'),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: const Color(0xFF1a1a2e),
                    title: const Text('Reset Stats?', style: TextStyle(color: Colors.white)),
                    content: const Text(
                      'This will reset all word counts, streaks, and transcription counts to zero.',
                      style: TextStyle(color: Colors.white60),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Reset', style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await stats.resetAll();
                  setState(() {});
                }
              },
              icon: const Icon(Icons.restart_alt, size: 16, color: Colors.white38),
              label: const Text('Reset Stats', style: TextStyle(color: Colors.white38, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile(String label, String value, String unit) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Color(0xFF3B82F6),
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              unit,
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 11),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ── Shortcut Key Configuration ──

  Widget _buildShortcutSection() {
    final hs = widget.hotkeyService!;
    return ListenableBuilder(
      listenable: hs,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Mode toggle ──
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // fn key mode is macOS-only
                if (Platform.isMacOS)
                  _buildModeChip(
                    label: 'Fn Key',
                    selected: hs.mode == HotkeyMode.fnKey,
                    onTap: () => hs.setMode(HotkeyMode.fnKey),
                  ),
                _buildModeChip(
                  label: 'Function Key',
                  selected: hs.mode == HotkeyMode.singleKey,
                  onTap: () => hs.setMode(HotkeyMode.singleKey),
                ),
                _buildModeChip(
                  label: 'Key Combination',
                  selected: hs.mode == HotkeyMode.combination,
                  onTap: () => hs.setMode(HotkeyMode.combination),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Options for selected mode ──
            if (hs.mode == HotkeyMode.fnKey) ...[
              Text(
                'Hold the fn key to dictate. Release to stop and transcribe.',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
              ),
              const SizedBox(height: 6),
              Text(
                'Tip: If fn opens the emoji picker, go to System Settings → '
                'Keyboard → "Press 🌐 key to" and set it to "Do Nothing".',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35), fontSize: 10),
              ),
            ] else if (hs.mode == HotkeyMode.singleKey) ...[
              Text(
                'Long-press a function key to dictate.',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: FunctionKeyPreset.values.map((fk) {
                  final selected = hs.fnKey == fk;
                  return GestureDetector(
                    onTap: () => hs.setFunctionKey(fk),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF3B82F6).withValues(alpha: 0.15)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF3B82F6).withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Text(
                        fk.label,
                        style: TextStyle(
                          color: selected
                              ? const Color(0xFF3B82F6)
                              : Colors.white70,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ] else ...[
              ...ShortcutPreset.values.map((preset) {
                final selected = hs.combo == preset;
                return GestureDetector(
                  onTap: () => hs.setCombo(preset),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF3B82F6).withValues(alpha: 0.15)
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF3B82F6).withValues(alpha: 0.5)
                            : Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: selected
                              ? const Color(0xFF3B82F6)
                              : Colors.white38,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(preset.label,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 15)),
                              Text(preset.description,
                                  style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.5),
                                      fontSize: 11)),
                            ],
                          ),
                        ),
                        if (selected)
                          const Text('Active',
                              style: TextStyle(
                                  color: Color(0xFF3B82F6),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12)),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ],
        );
      },
    );
  }

  Widget _buildModeChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF3B82F6).withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? const Color(0xFF3B82F6).withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF3B82F6) : Colors.white60,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

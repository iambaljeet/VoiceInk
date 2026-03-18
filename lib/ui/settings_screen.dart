import 'dart:io';
import 'package:flutter/material.dart';
import '../models/whisper_model.dart';
import '../services/model_manager.dart';
import '../services/dictation_service.dart';
import '../services/stt_engine_manager.dart';
import '../services/whisper_streaming_service.dart';
import '../services/hotkey_service.dart';
import '../services/audio_device_service.dart';
import 'onboarding_screen.dart';

import '../config/app_config.dart';

class SettingsScreen extends StatefulWidget {
  final ModelManager modelManager;
  final DictationService dictationService;
  final SttEngineManager? engineManager;
  final WhisperStreamingService? whisperStreaming;
  final HotkeyService? hotkeyService;
  final AudioDeviceService? audioDevice;

  const SettingsScreen({
    super.key,
    required this.modelManager,
    required this.dictationService,
    this.engineManager,
    this.whisperStreaming,
    this.hotkeyService,
    this.audioDevice,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
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
                // Engine selection
                if (widget.engineManager != null) ...[
                  _buildSectionHeader('Speech Engine'),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose how ${AppConfig.appName} converts speech to text.',
                    style: TextStyle(color: Colors.white60, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  ...SttEngine.values.map((engine) => _buildEngineCard(engine)),
                  const SizedBox(height: 24),
                ],
                _buildSectionHeader('Speech Models (Whisper)'),
                const SizedBox(height: 8),
                const Text(
                  'Download and manage Whisper models. Larger models are more accurate but slower.\nTap a downloaded model to select it as active.',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
                const SizedBox(height: 16),
                ...WhisperModel.available.map(_buildModelCard),
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

  Widget _buildEngineCard(SttEngine engine) {
    final mgr = widget.engineManager!;
    final isSelected = mgr.engine == engine;
    final isDisabled = engine == SttEngine.native && !mgr.nativeAvailable;

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
          color: isDisabled
              ? Colors.white24
              : isSelected
                  ? Colors.blue
                  : Colors.white38,
        ),
        title: Row(
          children: [
            Text(engine.icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(
              engine.label,
              style: TextStyle(
                color: isDisabled ? Colors.white38 : Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        subtitle: Text(
          isDisabled
              ? 'Not available on this device'
              : engine.description,
          style: TextStyle(
            color: isDisabled ? Colors.white24 : Colors.white60,
            fontSize: 12,
          ),
        ),
        trailing: isSelected
            ? const Text('Active',
                style: TextStyle(
                    color: Colors.blue,
                    fontWeight: FontWeight.w600,
                    fontSize: 12))
            : null,
        onTap: isDisabled
            ? null
            : () {
                mgr.setEngine(engine);
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

  // ── Shortcut Key Configuration ──

  Widget _buildShortcutSection() {
    final hs = widget.hotkeyService!;
    return ListenableBuilder(
      listenable: hs,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...ShortcutPreset.values.map((preset) {
              final selected = hs.preset == preset;
              return GestureDetector(
                onTap: () => hs.setPreset(preset),
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
        );
      },
    );
  }
}

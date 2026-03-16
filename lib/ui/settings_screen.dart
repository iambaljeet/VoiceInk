import 'package:flutter/material.dart';
import '../models/whisper_model.dart';
import '../services/model_manager.dart';
import '../services/dictation_service.dart';

class SettingsScreen extends StatefulWidget {
  final ModelManager modelManager;
  final DictationService dictationService;

  const SettingsScreen({
    super.key,
    required this.modelManager,
    required this.dictationService,
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
        title: const Text('VoiceInk Settings'),
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
                _buildSectionHeader('Speech Models'),
                const SizedBox(height: 8),
                const Text(
                  'Download and manage Whisper models. Larger models are more accurate but slower.',
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
                const SizedBox(height: 32),
                _buildSectionHeader('Keyboard Shortcut'),
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
                  child: const Row(
                    children: [
                      Icon(Icons.keyboard, color: Colors.white70),
                      SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Option + Space',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Toggle dictation on/off',
                            style: TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
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
                        'VoiceInk v1.0.0',
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
        leading: Icon(
          isDownloaded ? Icons.check_circle : Icons.cloud_download_outlined,
          color: isDownloaded ? Colors.green : Colors.white38,
        ),
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
        onTap: isDownloaded ? () => widget.modelManager.selectModel(model.id) : null,
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
}

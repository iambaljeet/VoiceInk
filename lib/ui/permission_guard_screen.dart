import 'dart:async';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import '../services/permission_service.dart';
import '../config/app_config.dart';

const _bgColor = Color(0xFF1a1a2e);
const _accentColor = Color(0xFF3B82F6);

/// Shown when the user has completed onboarding but later disabled a required
/// permission. Polls every 2 seconds and auto-dismisses when all permissions
/// are restored.
class PermissionGuardScreen extends StatefulWidget {
  final PermissionService permissions;
  final VoidCallback onAllGranted;

  const PermissionGuardScreen({
    super.key,
    required this.permissions,
    required this.onAllGranted,
  });

  @override
  State<PermissionGuardScreen> createState() => _PermissionGuardScreenState();
}

class _PermissionGuardScreenState extends State<PermissionGuardScreen> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _setupWindow();
    _startPolling();
  }

  Future<void> _setupWindow() async {
    await windowManager.setSize(const Size(420, 380));
    await windowManager.setMinimumSize(const Size(420, 380));
    await windowManager.setMaximumSize(const Size(420, 380));
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden,
        windowButtonVisibility: false);
    await windowManager.setBackgroundColor(_bgColor);
    await windowManager.setHasShadow(true);
    await windowManager.center();
    await windowManager.show();
    await windowManager.focus();
  }

  void _startPolling() {
    _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
      await widget.permissions.checkAll();
      if (!mounted) return;
      setState(() {});
      if (widget.permissions.allGranted) {
        _poll?.cancel();
        widget.onAllGranted();
      }
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.permissions;
    return Scaffold(
      backgroundColor: _bgColor,
      body: GestureDetector(
        onPanStart: (_) => windowManager.startDragging(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              const Center(
                child: Icon(Icons.shield_outlined,
                    size: 48, color: Colors.orange),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'Permissions Required',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  '${AppConfig.appName} needs these permissions to work. '
                  'Please re-enable them.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (!p.micGranted)
                _permCard(
                  icon: Icons.mic,
                  title: 'Microphone',
                  subtitle:
                      'Required to capture your voice for transcription. '
                      'Without this, ${AppConfig.appName} cannot hear you.',
                  buttonLabel: 'Grant Access',
                  onTap: () async {
                    await p.checkMicrophone();
                    if (mounted) setState(() {});
                  },
                ),
              if (!p.micGranted && !p.accessibilityGranted)
                const SizedBox(height: 12),
              if (!p.accessibilityGranted)
                _permCard(
                  icon: Icons.accessibility_new,
                  title: 'Accessibility',
                  subtitle:
                      'Required to type transcribed text into other apps. '
                      'Without this, ${AppConfig.appName} can only show text '
                      'but not type it for you.',
                  buttonLabel: 'Open Settings',
                  onTap: () => p.openAccessibilitySettings(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _permCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required String buttonLabel,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.orange, size: 28),
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
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: onTap,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child:
                      Text(buttonLabel, style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

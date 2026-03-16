import 'dart:math';
import 'package:flutter/material.dart';
import '../services/dictation_service.dart';

/// Floating pill overlay that shows recording/processing state
class FloatingIndicator extends StatefulWidget {
  final DictationState state;
  final String? lastText;
  final String? error;
  final VoidCallback? onCancel;

  const FloatingIndicator({
    super.key,
    required this.state,
    this.lastText,
    this.error,
    this.onCancel,
  });

  @override
  State<FloatingIndicator> createState() => _FloatingIndicatorState();
}

class _FloatingIndicatorState extends State<FloatingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      child: _buildIndicator(),
    );
  }

  Widget _buildIndicator() {
    switch (widget.state) {
      case DictationState.idle:
        if (widget.error != null) {
          return _buildPill(
            key: const ValueKey('error'),
            color: Colors.red.shade700,
            icon: Icons.error_outline,
            text: widget.error!,
            showClose: true,
          );
        }
        if (widget.lastText != null && widget.lastText!.isNotEmpty) {
          return _buildPill(
            key: const ValueKey('done'),
            color: Colors.green.shade700,
            icon: Icons.check_circle_outline,
            text: _truncate(widget.lastText!, 50),
            showClose: false,
          );
        }
        return const SizedBox.shrink(key: ValueKey('hidden'));

      case DictationState.recording:
        return AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return _buildPill(
              key: const ValueKey('recording'),
              color: Color.lerp(
                Colors.red.shade600,
                Colors.red.shade900,
                _pulseController.value,
              )!,
              icon: Icons.mic,
              text: 'Listening...',
              showClose: true,
              showWaveform: true,
            );
          },
        );

      case DictationState.processing:
        return _buildPill(
          key: const ValueKey('processing'),
          color: Colors.blue.shade700,
          icon: Icons.hourglass_top,
          text: 'Transcribing...',
          showClose: false,
          showSpinner: true,
        );
    }
  }

  Widget _buildPill({
    required Key key,
    required Color color,
    required IconData icon,
    required String text,
    bool showClose = false,
    bool showWaveform = false,
    bool showSpinner = false,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSpinner)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          else
            Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          if (showWaveform) ...[
            _WaveformWidget(animation: _pulseController),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (showClose) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: widget.onCancel,
              child: const Icon(
                Icons.close,
                color: Colors.white70,
                size: 16,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _truncate(String text, int maxLen) {
    if (text.length <= maxLen) return text;
    return '${text.substring(0, maxLen)}...';
  }
}

class _WaveformWidget extends StatelessWidget {
  final Animation<double> animation;
  const _WaveformWidget({required this.animation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (i) {
            final height = 6.0 +
                10.0 *
                    sin((animation.value * 3.14159) + (i * 0.8)).abs();
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 1),
              width: 3,
              height: height,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(1.5),
              ),
            );
          }),
        );
      },
    );
  }
}

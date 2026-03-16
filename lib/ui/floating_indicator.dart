import 'dart:math';
import 'package:flutter/material.dart';
import '../services/dictation_service.dart';

/// Minimal transparent floating capsule showing recording state
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
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    switch (widget.state) {
      case DictationState.idle:
        if (widget.error != null) {
          return _capsule(
            key: const ValueKey('error'),
            color: Colors.red.withValues(alpha: 0.85),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.white, size: 14),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    widget.error!,
                    style: const TextStyle(color: Colors.white, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }
        return const SizedBox.shrink(key: ValueKey('hidden'));

      case DictationState.recording:
        return AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) {
            return _capsule(
              key: const ValueKey('recording'),
              color: Color.lerp(
                Colors.red.withValues(alpha: 0.75),
                Colors.red.withValues(alpha: 0.95),
                _pulseController.value,
              )!,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _WaveformBars(animation: _pulseController),
                  const SizedBox(width: 8),
                  const Text(
                    'Listening',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            );
          },
        );

      case DictationState.processing:
        return _capsule(
          key: const ValueKey('processing'),
          color: Colors.blue.withValues(alpha: 0.85),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 8),
              Text(
                'Finishing...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        );
    }
  }

  Widget _capsule({
    required Key key,
    required Color color,
    required Widget child,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _WaveformBars extends StatelessWidget {
  final Animation<double> animation;
  const _WaveformBars({required this.animation});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(4, (i) {
        final h = 4.0 + 8.0 * sin((animation.value * 3.14159) + (i * 1.0)).abs();
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 1),
          width: 2.5,
          height: h,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(1.5),
          ),
        );
      }),
    );
  }
}

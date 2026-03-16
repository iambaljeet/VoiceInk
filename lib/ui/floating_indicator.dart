import 'dart:math';
import 'package:flutter/material.dart';
import '../services/dictation_service.dart';

/// Fixed-size capsule: red "⌥Space" when idle, green waveform+Listening when recording.
class FloatingIndicator extends StatefulWidget {
  final DictationState state;
  const FloatingIndicator({super.key, required this.state});

  @override
  State<FloatingIndicator> createState() => _FloatingIndicatorState();
}

class _FloatingIndicatorState extends State<FloatingIndicator>
    with TickerProviderStateMixin {
  late AnimationController _pulse;
  late AnimationController _colorAnim;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _colorAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _sync();
  }

  @override
  void didUpdateWidget(FloatingIndicator old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _sync();
  }

  void _sync() {
    if (widget.state == DictationState.recording) {
      _pulse.repeat(reverse: true);
      _colorAnim.forward();
    } else {
      _pulse.stop();
      _pulse.value = 0;
      _colorAnim.reverse();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _colorAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulse, _colorAnim]),
      builder: (context, _) {
        final t = _colorAnim.value;
        final isRec = widget.state == DictationState.recording;

        final color = Color.lerp(
          const Color(0xFFE53935),
          const Color(0xFF43A047),
          t,
        )!;

        final glow = isRec ? 4.0 + 8.0 * _pulse.value : 0.0;

        return Container(
          width: 140,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 4 + glow,
                spreadRadius: glow * 0.3,
              ),
            ],
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: isRec ? _recordingContent() : _idleContent(),
            ),
          ),
        );
      },
    );
  }

  Widget _idleContent() {
    return const Text(
      '⌥ Space',
      key: ValueKey('idle'),
      style: TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        decoration: TextDecoration.none,
      ),
    );
  }

  Widget _recordingContent() {
    return Row(
      key: const ValueKey('recording'),
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        _WaveformBars(animation: _pulse),
        const SizedBox(width: 8),
        const Text(
          'Listening',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            decoration: TextDecoration.none,
          ),
        ),
      ],
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
        final h = 4.0 + 10.0 * sin((animation.value * pi) + (i * 0.8)).abs();
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          width: 3,
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

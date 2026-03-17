import 'dart:math';
import 'package:flutter/material.dart';
import '../services/dictation_service.dart';

// ─── Design tokens ──────────────────────────────────────
const _idleColor = Color(0xFF1C1C2E);
const _recordColor = Color(0xFF22C55E);
const _processColor = Color(0xFF3B82F6);

const _idleWidth = 120.0;
const _idleHeight = 34.0;
const _expandedWidth = 200.0;
const _expandedHeight = 48.0;
const _borderRadius = 24.0;

/// Dynamic-Island-style capsule indicator.
///
/// Idle     → compact dark pill showing shortcut label
/// Recording → expands, turns green with waveform + "Listening"
/// Processing → stays expanded, turns blue with spinner + "Typing…"
class FloatingIndicator extends StatefulWidget {
  final DictationState state;
  final String shortcutLabel;
  const FloatingIndicator({
    super.key,
    required this.state,
    this.shortcutLabel = '⌥ Space',
  });

  @override
  State<FloatingIndicator> createState() => _FloatingIndicatorState();
}

class _FloatingIndicatorState extends State<FloatingIndicator>
    with TickerProviderStateMixin {
  // Waveform / glow pulse (loops while recording)
  late AnimationController _pulse;

  // Subtle idle breathing glow
  late AnimationController _idleBreath;

  // Processing dots animation
  late AnimationController _dots;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _idleBreath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    _dots = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _sync();
  }

  @override
  void didUpdateWidget(FloatingIndicator old) {
    super.didUpdateWidget(old);
    if (old.state != widget.state) _sync();
  }

  void _sync() {
    switch (widget.state) {
      case DictationState.recording:
        _idleBreath.stop();
        _dots.stop();
        _pulse.repeat(reverse: true);
        break;
      case DictationState.processing:
        _pulse.stop();
        _idleBreath.stop();
        _dots.repeat();
        break;
      case DictationState.idle:
        _pulse.stop();
        _pulse.value = 0;
        _dots.stop();
        _dots.value = 0;
        _idleBreath.repeat(reverse: true);
        break;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _idleBreath.dispose();
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isIdle = widget.state == DictationState.idle;
    final isRec = widget.state == DictationState.recording;
    final isProc = widget.state == DictationState.processing;

    final targetColor =
        isRec ? _recordColor : isProc ? _processColor : _idleColor;
    final targetW = isIdle ? _idleWidth : _expandedWidth;
    final targetH = isIdle ? _idleHeight : _expandedHeight;

    return AnimatedBuilder(
      animation: Listenable.merge([_pulse, _idleBreath, _dots]),
      builder: (context, _) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          width: targetW,
          height: targetH,
          decoration: BoxDecoration(
            color: targetColor,
            borderRadius: BorderRadius.circular(_borderRadius),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_borderRadius),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: isRec
                  ? _RecordingContent(key: const ValueKey('rec'), pulse: _pulse)
                  : isProc
                      ? _ProcessingContent(
                          key: const ValueKey('proc'), dots: _dots)
                      : _IdleContent(
                          key: const ValueKey('idle'),
                          label: widget.shortcutLabel,
                        ),
            ),
          ),
        );
      },
    );
  }
}

// ─── Idle ────────────────────────────────────────────────

class _IdleContent extends StatelessWidget {
  final String label;
  const _IdleContent({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFF64748B),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.4,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Recording ──────────────────────────────────────────

class _RecordingContent extends StatelessWidget {
  final AnimationController pulse;
  const _RecordingContent({super.key, required this.pulse});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _WaveformBars(animation: pulse),
          const SizedBox(width: 10),
          const Text(
            'Listening',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Processing ─────────────────────────────────────────

class _ProcessingContent extends StatelessWidget {
  final AnimationController dots;
  const _ProcessingContent({super.key, required this.dots});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TypingDots(animation: dots),
          const SizedBox(width: 10),
          const Text(
            'Typing…',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Waveform bars ──────────────────────────────────────

class _WaveformBars extends StatelessWidget {
  final Animation<double> animation;
  const _WaveformBars({required this.animation});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(5, (i) {
        final phase = (animation.value * pi) + (i * 0.7);
        final h = 6.0 + 14.0 * sin(phase).abs();
        return AnimatedContainer(
          duration: const Duration(milliseconds: 60),
          margin: const EdgeInsets.symmetric(horizontal: 1.2),
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

// ─── Typing dots ────────────────────────────────────────

class _TypingDots extends StatelessWidget {
  final Animation<double> animation;
  const _TypingDots({required this.animation});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        // Stagger each dot by 0.25 of the cycle
        final t = (animation.value + i * 0.25) % 1.0;
        // Bounce: rises 0→0.5, falls 0.5→1
        final bounce = t < 0.5 ? t * 2 : (1.0 - t) * 2;
        final y = -4.0 * bounce;
        return Transform.translate(
          offset: Offset(0, y),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7 + 0.3 * bounce),
              shape: BoxShape.circle,
            ),
          ),
        );
      }),
    );
  }
}

import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/dictation_service.dart';

// ─── Design tokens ──────────────────────────────────────
const _idleColor = Color(0xFF1C1C2E);
const _recordColor = Color(0xFF22C55E);
const _processColor = Color(0xFF3B82F6);

// Idle collapsed – ultra-thin line pill
const _idleW = 48.0;
const _idleH = 6.0;

// Idle hovered – shows shortcut label
const _hoverW = 120.0;
const _hoverH = 28.0;

// Recording / Processing – compact icon-only pill
const _activeW = 48.0;
const _activeH = 28.0;

const _pillRadius = 14.0;
const _lineRadius = 3.0;

/// Minimal WisprFlow-style capsule indicator.
///
/// Idle       → ultra-thin dark line pill; expands on hover to show shortcut
/// Recording  → compact green pill with animated waveform icon (no text)
/// Processing → compact blue pill with animated typing dots (no text)
class FloatingIndicator extends StatefulWidget {
  static String get _defaultShortcut =>
      Platform.isMacOS ? '⌥ Space' : 'Alt + Space';

  final DictationState state;
  final String shortcutLabel;
  final bool isHovered;
  final bool showBorder;
  FloatingIndicator({
    super.key,
    required this.state,
    String? shortcutLabel,
    this.isHovered = false,
    this.showBorder = true,
  }) : shortcutLabel = shortcutLabel ?? _defaultShortcut;

  @override
  State<FloatingIndicator> createState() => _FloatingIndicatorState();
}

class _FloatingIndicatorState extends State<FloatingIndicator>
    with TickerProviderStateMixin {
  late AnimationController _pulse;
  late AnimationController _idleBreath;
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
    final hovered = widget.isHovered && isIdle;

    return AnimatedBuilder(
      animation: Listenable.merge([_pulse, _idleBreath, _dots]),
      builder: (context, _) {
        double targetW, targetH;
        Color targetColor;
        double radius;
        List<BoxShadow>? shadows;

        if (isRec) {
          targetW = _activeW;
          targetH = _activeH;
          targetColor = _recordColor;
          radius = _pillRadius;
          shadows = [
            BoxShadow(
              color: _recordColor.withValues(alpha: 0.4),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ];
        } else if (isProc) {
          targetW = _activeW;
          targetH = _activeH;
          targetColor = _processColor;
          radius = _pillRadius;
          shadows = [
            BoxShadow(
              color: _processColor.withValues(alpha: 0.3),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ];
        } else if (hovered) {
          targetW = _hoverW;
          targetH = _hoverH;
          targetColor = _idleColor;
          radius = _pillRadius;
        } else {
          targetW = _idleW;
          targetH = _idleH;
          final breathAlpha = 0.6 + 0.4 * _idleBreath.value;
          targetColor = _idleColor.withValues(alpha: breathAlpha);
          radius = _lineRadius;
        }

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          clipBehavior: Clip.hardEdge,
          width: targetW,
          height: targetH,
          decoration: BoxDecoration(
            color: targetColor,
            borderRadius: BorderRadius.circular(radius),
            boxShadow: shadows,
            border: widget.showBorder
                ? Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                    width: 0.5,
                  )
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              child: isRec
                  ? FittedBox(
                      key: const ValueKey('rec'),
                      fit: BoxFit.scaleDown,
                      child: _RecordingContent(pulse: _pulse),
                    )
                  : isProc
                      ? FittedBox(
                          key: const ValueKey('proc'),
                          fit: BoxFit.scaleDown,
                          child: _ProcessingContent(dots: _dots),
                        )
                      : hovered
                          ? FittedBox(
                              key: const ValueKey('idle-hover'),
                              fit: BoxFit.scaleDown,
                              child: _IdleHoveredContent(
                                label: widget.shortcutLabel,
                              ),
                            )
                          : const SizedBox.shrink(
                              key: ValueKey('idle-line')),
            ),
          ),
        );
      },
    );
  }
}

// ─── Idle hovered (shows shortcut) ──────────────────────

class _IdleHoveredContent extends StatelessWidget {
  final String label;
  const _IdleHoveredContent({required this.label});



  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: Color(0xFF64748B),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            maxLines: 1,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Recording (icon only) ──────────────────────────────

class _RecordingContent extends StatelessWidget {
  final AnimationController pulse;
  const _RecordingContent({required this.pulse});

  @override
  Widget build(BuildContext context) {
    return Center(child: _WaveformBars(animation: pulse));
  }
}

// ─── Processing (icon only) ─────────────────────────────

class _ProcessingContent extends StatelessWidget {
  final AnimationController dots;
  const _ProcessingContent({required this.dots});

  @override
  Widget build(BuildContext context) {
    return Center(child: _TypingDots(animation: dots));
  }
}

// ─── Waveform bars (compact, 3 bars) ────────────────────

class _WaveformBars extends StatelessWidget {
  final Animation<double> animation;
  const _WaveformBars({required this.animation});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: List.generate(3, (i) {
        final phase = (animation.value * pi) + (i * 0.9);
        final h = 4.0 + 10.0 * sin(phase).abs();
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

// ─── Typing dots (compact) ──────────────────────────────

class _TypingDots extends StatelessWidget {
  final Animation<double> animation;
  const _TypingDots({required this.animation});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final t = (animation.value + i * 0.25) % 1.0;
        final bounce = t < 0.5 ? t * 2 : (1.0 - t) * 2;
        final y = -3.0 * bounce;
        return Transform.translate(
          offset: Offset(0, y),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 4,
            height: 4,
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

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/motion_tokens.dart';

class PressableScale extends StatefulWidget {
  const PressableScale({
    required this.child,
    this.onTap,
    this.semanticLabel,
    this.scale = 0.98,
    this.enableHaptic = false,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final double scale;
  final bool enableHaptic;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  var _pressed = false;
  var _hovered = false;
  var _focused = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _setFocused(bool value) {
    if (_focused == value) return;
    setState(() => _focused = value);
  }

  Future<void> _handleTap() async {
    if (widget.enableHaptic) {
      await HapticFeedback.selectionClick();
    }
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null;
    final scale = _pressed
        ? widget.scale
        : _hovered
        ? 1.01
        : _focused
        ? 1.005
        : 1.0;
    final opacity = _pressed
        ? 0.92
        : (_hovered || _focused)
        ? 0.98
        : 1.0;
    final animatedChild = AnimatedScale(
      scale: scale,
      duration: MotionTokens.instant,
      curve: MotionTokens.curveStandard,
      child: AnimatedOpacity(
        opacity: opacity,
        duration: MotionTokens.instant,
        curve: MotionTokens.curveStandard,
        child: widget.child,
      ),
    );
    final child = interactive
        ? ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            child: animatedChild,
          )
        : animatedChild;

    return Semantics(
      button: interactive,
      enabled: interactive,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: interactive,
        mouseCursor: interactive
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: _setHovered,
        onShowFocusHighlight: _setFocused,
        shortcuts: interactive
            ? const <ShortcutActivator, Intent>{
                SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
              }
            : const <ShortcutActivator, Intent>{},
        actions: interactive
            ? <Type, Action<Intent>>{
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) {
                    _handleTap();
                    return null;
                  },
                ),
              }
            : const <Type, Action<Intent>>{},
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: interactive ? _handleTap : null,
          onTapDown: interactive ? (_) => _setPressed(true) : null,
          onTapUp: interactive ? (_) => _setPressed(false) : null,
          onTapCancel: interactive ? () => _setPressed(false) : null,
          child: child,
        ),
      ),
    );
  }
}

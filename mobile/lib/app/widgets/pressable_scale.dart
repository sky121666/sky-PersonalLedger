import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/motion_tokens.dart';

class PressableScale extends StatefulWidget {
  const PressableScale({
    required this.child,
    this.onTap,
    this.semanticLabel,
    this.scale = 0.985,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final double scale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  void _handleTap() {
    widget.onTap?.call();
  }

  void _setPressed(bool pressed) {
    if (_pressed == pressed) {
      return;
    }
    setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null;
    final content = ConstrainedBox(
      constraints: interactive
          ? const BoxConstraints(minWidth: 44, minHeight: 44)
          : const BoxConstraints(),
      child: AnimatedOpacity(
        opacity: interactive && _pressed ? 0.92 : 1,
        duration: MotionTokens.short,
        curve: MotionTokens.curveStandard,
        child: AnimatedScale(
          scale: interactive && _pressed ? widget.scale : 1,
          duration: MotionTokens.short,
          curve: MotionTokens.curveStandard,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: interactive ? _handleTap : null,
              onTapDown: interactive ? (_) => _setPressed(true) : null,
              onTapCancel: interactive ? () => _setPressed(false) : null,
              onTapUp: interactive ? (_) => _setPressed(false) : null,
              child: widget.child,
            ),
          ),
        ),
      ),
    );

    return Semantics(
      button: interactive,
      enabled: interactive,
      label: widget.semanticLabel,
      onTap: interactive ? _handleTap : null,
      child: FocusableActionDetector(
        enabled: interactive,
        mouseCursor: interactive
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
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
        child: content,
      ),
    );
  }
}

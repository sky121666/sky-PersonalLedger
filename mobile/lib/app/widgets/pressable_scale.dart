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

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  Future<void> _handleTap() async {
    if (widget.enableHaptic) {
      await HapticFeedback.selectionClick();
    }
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final child = AnimatedScale(
      scale: _pressed ? widget.scale : 1,
      duration: MotionTokens.instant,
      curve: MotionTokens.curveStandard,
      child: AnimatedOpacity(
        opacity: _pressed ? 0.92 : 1,
        duration: MotionTokens.instant,
        curve: MotionTokens.curveStandard,
        child: widget.child,
      ),
    );

    return Semantics(
      button: widget.onTap != null,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap == null ? null : _handleTap,
        onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
        onTapUp: widget.onTap == null ? null : (_) => _setPressed(false),
        onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
        child: child,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PressableScale extends StatelessWidget {
  const PressableScale({
    required this.child,
    this.onTap,
    this.semanticLabel,
    this.scale = 0.98,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final double scale;

  void _handleTap() {
    onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final interactive = onTap != null;
    final content = ConstrainedBox(
      constraints: interactive
          ? const BoxConstraints(minWidth: 44, minHeight: 44)
          : const BoxConstraints(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(onTap: interactive ? _handleTap : null, child: child),
      ),
    );

    return Semantics(
      button: interactive,
      enabled: interactive,
      label: semanticLabel,
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

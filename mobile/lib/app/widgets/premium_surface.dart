import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'pressable_scale.dart';

class PremiumSurface extends StatelessWidget {
  const PremiumSurface({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(20),
    this.radius = AppTheme.surfaceRadius,
    this.accentColor,
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? accentColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final trimmedSemanticLabel = semanticLabel?.trim();
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tint = accentColor ?? colorScheme.primary;
    final background = Color.alphaBlend(
      tint.withValues(alpha: isDark ? 0.06 : 0.025),
      colorScheme.surface,
    );
    final borderColor = Color.alphaBlend(
      tint.withValues(alpha: isDark ? 0.16 : 0.08),
      colorScheme.outlineVariant.withValues(alpha: isDark ? 0.34 : 0.40),
    );

    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
      ),
      child: Padding(padding: padding, child: child),
    );

    if (onTap == null) {
      if (trimmedSemanticLabel == null || trimmedSemanticLabel.isEmpty) {
        return surface;
      }

      return Semantics(
        container: true,
        label: trimmedSemanticLabel,
        child: surface,
      );
    }

    return PressableScale(
      onTap: onTap,
      semanticLabel: trimmedSemanticLabel,
      child: surface,
    );
  }
}

import 'package:flutter/material.dart';

import 'premium_surface.dart';

class AuthFlowShell extends StatelessWidget {
  const AuthFlowShell({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.accentColor,
    required this.children,
    this.serverUrl,
    this.footer,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String primaryLabel;
  final Color accentColor;
  final String? serverUrl;
  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final isCompactLayout = MediaQuery.sizeOf(context).width < 720;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              isCompactLayout ? 14 : 24,
              20,
              (isCompactLayout ? 20 : 28) + bottomInset,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: isCompactLayout ? 0 : constraints.maxHeight - 48,
              ),
              child: Align(
                alignment: isCompactLayout
                    ? Alignment.topCenter
                    : Alignment.center,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _AuthHeroPanel(
                        icon: icon,
                        title: title,
                        subtitle: subtitle,
                        primaryLabel: primaryLabel,
                        serverUrl: serverUrl,
                        accentColor: accentColor,
                      ),
                      const SizedBox(height: 12),
                      PremiumSurface(
                        accentColor: accentColor,
                        semanticLabel: '$primaryLabel 表单',
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: children,
                        ),
                      ),
                      if (footer != null) ...[
                        const SizedBox(height: 8),
                        Align(alignment: Alignment.centerRight, child: footer!),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

InputDecoration authFlowInputDecoration(
  BuildContext context, {
  required String labelText,
  String? hintText,
  String? errorText,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: colorScheme.outlineVariant),
  );
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    errorText: errorText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    filled: true,
    fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
    border: border,
    enabledBorder: border,
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: colorScheme.error),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: colorScheme.error, width: 1.4),
    ),
  );
}

class _AuthHeroPanel extends StatelessWidget {
  const _AuthHeroPanel({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.accentColor,
    this.serverUrl,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String primaryLabel;
  final Color accentColor;
  final String? serverUrl;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final subtitleText = subtitle.trim();
    return PremiumSurface(
      semanticLabel: '$title，$primaryLabel',
      accentColor: accentColor.withValues(alpha: 0.82),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    accentColor.withValues(alpha: 0.12),
                    colorScheme.surface,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      primaryLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: accentColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    if (serverUrl != null && serverUrl!.trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        serverUrl!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (subtitleText.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              subtitleText,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

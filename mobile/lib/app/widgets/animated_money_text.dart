import 'package:flutter/material.dart';

class AnimatedMoneyText extends StatelessWidget {
  const AnimatedMoneyText({
    super.key,
    required this.amount,
    this.currencySymbol = '¥',
    this.style,
  });

  final double amount;
  final String currencySymbol;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = (style ?? Theme.of(context).textTheme.titleLarge)
        ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final semanticValue = _formatMoney(amount);

    return Semantics(
      label: semanticValue,
      child: ExcludeSemantics(
        child: Text(semanticValue, style: effectiveStyle),
      ),
    );
  }

  String _formatMoney(double value) {
    final sign = value < 0 ? '-' : '';
    return '$sign$currencySymbol${value.abs().toStringAsFixed(2)}';
  }
}

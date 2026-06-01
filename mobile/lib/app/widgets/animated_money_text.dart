import 'package:flutter/material.dart';
import 'package:personal_ledger/app/theme/motion_tokens.dart';

class AnimatedMoneyText extends StatelessWidget {
  const AnimatedMoneyText({
    super.key,
    required this.amount,
    this.currencySymbol = '¥',
    this.style,
    this.duration = MotionTokens.long,
    this.curve = MotionTokens.curveStandard,
  });

  final double amount;
  final String currencySymbol;
  final TextStyle? style;
  final Duration duration;
  final Curve curve;

  @override
  Widget build(BuildContext context) {
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final effectiveStyle = (style ?? Theme.of(context).textTheme.titleLarge)
        ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final semanticValue = _formatMoney(amount);

    return Semantics(
      label: semanticValue,
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: amount),
          duration: disableAnimations ? Duration.zero : duration,
          curve: curve,
          builder: (context, value, child) {
            return Text(_formatMoney(value), style: effectiveStyle);
          },
        ),
      ),
    );
  }

  String _formatMoney(double value) {
    final sign = value < 0 ? '-' : '';
    return '$sign$currencySymbol${value.abs().toStringAsFixed(2)}';
  }
}

import 'package:flutter/material.dart';

class AdaptivePageContainer extends StatelessWidget {
  const AdaptivePageContainer({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.semanticLabel,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  /// 构建适配手机和平板宽度的页面容器。
  @override
  Widget build(BuildContext context) {
    final content = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Padding(padding: padding, child: child),
      ),
    );
    final label = semanticLabel?.trim();
    return SafeArea(
      child: label == null || label.isEmpty
          ? content
          : Semantics(container: true, label: label, child: content),
    );
  }
}

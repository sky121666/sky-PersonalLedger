import 'package:flutter/material.dart';

class AdaptivePageContainer extends StatelessWidget {
  const AdaptivePageContainer({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// 构建适配手机和平板宽度的页面容器。
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

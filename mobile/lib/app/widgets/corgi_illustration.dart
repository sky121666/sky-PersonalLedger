import 'package:flutter/material.dart';

enum CorgiIllustrationAsset {
  sitting('assets/brand/corgi-sitting.png'),
  brand('assets/brand/corgi-brand.png'),
  pig('assets/brand/corgi-pig.png');

  const CorgiIllustrationAsset(this.path);

  final String path;
}

class CorgiIllustration extends StatelessWidget {
  const CorgiIllustration({
    this.asset = CorgiIllustrationAsset.sitting,
    this.width = 72,
    this.opacity = 1,
    this.alignment = Alignment.center,
    super.key,
  });

  final CorgiIllustrationAsset asset;
  final double width;
  final double opacity;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      asset.path,
      key: ValueKey('corgi-illustration-${asset.name}'),
      width: width,
      fit: BoxFit.contain,
      alignment: alignment,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      errorBuilder: (context, error, stackTrace) {
        return SizedBox(
          width: width,
          height: width * 0.62,
          child: Icon(
            Icons.savings_outlined,
            size: width * 0.38,
            color: Theme.of(context).colorScheme.primary,
          ),
        );
      },
    );
    return RepaintBoundary(
      child: IgnorePointer(
        child: opacity >= 1 ? image : Opacity(opacity: opacity, child: image),
      ),
    );
  }
}

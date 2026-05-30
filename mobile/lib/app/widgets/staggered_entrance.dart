import 'package:flutter/material.dart';

import '../theme/motion_tokens.dart';

class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance({
    required this.child,
    this.index = 0,
    this.offset = const Offset(0, 12),
    super.key,
  });

  final Widget child;
  final int index;
  final Offset offset;

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _position;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: MotionTokens.long);
    final curved = CurvedAnimation(
      parent: _controller,
      curve: MotionTokens.curveStandard,
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(curved);
    _position = Tween<Offset>(
      begin: widget.offset,
      end: Offset.zero,
    ).animate(curved);

    Future<void>.delayed(MotionTokens.staggerStep * widget.index, () {
      if (!mounted) return;
      if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.translate(offset: _position.value, child: child),
        );
      },
    );
  }
}

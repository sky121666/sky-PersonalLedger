import 'package:flutter/material.dart';

class StaggeredEntrance extends StatelessWidget {
  const StaggeredEntrance({
    required this.child,
    this.index = 0,
    this.offset = Offset.zero,
    super.key,
  });

  final Widget child;
  final int index;
  final Offset offset;

  @override
  Widget build(BuildContext context) => child;
}

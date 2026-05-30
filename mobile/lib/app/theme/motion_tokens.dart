import 'package:flutter/animation.dart';

class MotionTokens {
  const MotionTokens._();

  static const Duration instant = Duration(milliseconds: 96);
  static const Duration short = Duration(milliseconds: 160);
  static const Duration medium = Duration(milliseconds: 240);
  static const Duration long = Duration(milliseconds: 360);
  static const Duration emphasized = Duration(milliseconds: 480);
  static const Duration staggerStep = Duration(milliseconds: 44);

  static const Curve curveStandard = Curves.easeOutCubic;
  static const Curve curveExit = Curves.easeInCubic;
  static const Curve curveEmphasized = Curves.fastOutSlowIn;

  static const Curve enter = curveStandard;
  static const Curve exit = curveExit;
  static const Curve emphasizedCurve = curveEmphasized;
}

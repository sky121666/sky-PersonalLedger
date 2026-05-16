import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import 'app/personal_ledger_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _configureSystemUi();
  runApp(const ProviderScope(child: PersonalLedgerApp()));
}

void _configureSystemUi() {
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );
}

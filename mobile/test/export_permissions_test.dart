import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final name in ['DebugProfile', 'Release']) {
    test(
      'macOS $name permits writing only a user-selected export destination',
      () {
        final xml = File('macos/Runner/$name.entitlements').readAsStringSync();
        expect(
          xml,
          contains(
            '<key>com.apple.security.files.user-selected.read-write</key>',
          ),
        );
        expect(
          xml,
          isNot(contains('com.apple.security.files.user-selected.read-only')),
        );
        expect(xml, isNot(contains('com.apple.security.files.all')));
        expect(xml, contains('<key>com.apple.security.app-sandbox</key>'));
      },
    );
  }
}

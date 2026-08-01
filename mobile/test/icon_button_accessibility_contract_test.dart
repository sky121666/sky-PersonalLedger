import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every IconButton declares a non-null tooltip', () {
    final violations = <String>[];
    final dartFiles =
        Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart'))
            .toList()
          ..sort((left, right) => left.path.compareTo(right.path));

    final constructorPattern = RegExp(
      r'\bIconButton(?:\.(?:filled|filledTonal|outlined))?\s*\(',
    );

    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      for (final match in constructorPattern.allMatches(source)) {
        final openingParenthesis = source.indexOf('(', match.start);
        final closingParenthesis = _findMatchingParenthesis(
          source,
          openingParenthesis,
        );
        final line =
            '\n'.allMatches(source.substring(0, match.start)).length + 1;
        if (closingParenthesis == -1) {
          violations.add('${file.path}:$line 无法解析 IconButton');
          continue;
        }

        final arguments = source.substring(
          openingParenthesis + 1,
          closingParenthesis,
        );
        if (!RegExp(r'\btooltip\s*:').hasMatch(arguments)) {
          violations.add('${file.path}:$line 缺少 tooltip');
        } else if (RegExp(r'\btooltip\s*:\s*null\b').hasMatch(arguments)) {
          violations.add('${file.path}:$line tooltip 不能为 null');
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: '仅图标按钮必须提供明确操作名称：\n${violations.join('\n')}',
    );
  });
}

int _findMatchingParenthesis(String source, int openingParenthesis) {
  var depth = 0;
  var quote = '';
  var escaped = false;
  var lineComment = false;
  var blockComment = false;

  for (var index = openingParenthesis; index < source.length; index += 1) {
    final character = source[index];
    final next = index + 1 < source.length ? source[index + 1] : '';

    if (lineComment) {
      if (character == '\n') {
        lineComment = false;
      }
      continue;
    }
    if (blockComment) {
      if (character == '*' && next == '/') {
        blockComment = false;
        index += 1;
      }
      continue;
    }
    if (quote.isNotEmpty) {
      if (escaped) {
        escaped = false;
      } else if (character == '\\') {
        escaped = true;
      } else if (character == quote) {
        quote = '';
      }
      continue;
    }

    if (character == '/' && next == '/') {
      lineComment = true;
      index += 1;
      continue;
    }
    if (character == '/' && next == '*') {
      blockComment = true;
      index += 1;
      continue;
    }
    if (character == "'" || character == '"') {
      quote = character;
      continue;
    }
    if (character == '(') {
      depth += 1;
    } else if (character == ')') {
      depth -= 1;
      if (depth == 0) {
        return index;
      }
    }
  }

  return -1;
}

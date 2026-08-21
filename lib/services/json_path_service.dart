class JsonPathException implements Exception {
  final String message;

  const JsonPathException(this.message);

  @override
  String toString() => 'JsonPathException: $message';
}

/// Supports the JSONPath subset used by KazumiRules API rules.
///
/// Supported forms include `$.data.records[*]`, `$.items[0]`, `$.title`,
/// bracket-quoted keys, and `$` for the current node.
class JsonPathService {
  const JsonPathService();

  List<Object?> readAll(Object? root, String path) {
    final tokens = _tokenize(path);
    var current = <Object?>[root];
    for (final token in tokens) {
      final next = <Object?>[];
      for (final value in current) {
        switch (token.kind) {
          case _JsonPathTokenKind.key:
            if (value is Map && value.containsKey(token.value)) {
              next.add(value[token.value]);
            }
          case _JsonPathTokenKind.arrayIndex:
            if (value is List) {
              final index = int.parse(token.value);
              if (index >= 0 && index < value.length) next.add(value[index]);
            }
          case _JsonPathTokenKind.wildcard:
            if (value is List) {
              next.addAll(value);
            } else if (value is Map) {
              next.addAll(value.values);
            }
        }
      }
      current = next;
    }
    return current;
  }

  Object? readFirst(Object? root, String path) {
    if (path.trim().isEmpty || path.trim() == r'$') return root;
    final values = readAll(root, path);
    return values.isEmpty ? null : values.first;
  }

  List<Object?> readList(Object? root, String path) {
    final values = readAll(root, path);
    if (values.length == 1 && values.first is List) {
      return List<Object?>.from(values.first as List);
    }
    return values;
  }

  List<_JsonPathToken> _tokenize(String rawPath) {
    final path = rawPath.trim();
    if (path.isEmpty || !path.startsWith(r'$')) {
      throw JsonPathException('JSONPath 必须以 \$ 开头: $rawPath');
    }

    final tokens = <_JsonPathToken>[];
    var index = 1;
    while (index < path.length) {
      final character = path[index];
      if (character == '.') {
        index++;
        if (index < path.length && path[index] == '.') {
          throw JsonPathException('不支持递归 JSONPath: $rawPath');
        }
        final start = index;
        while (index < path.length && _isKeyCharacter(path[index])) {
          index++;
        }
        if (start == index) {
          throw JsonPathException('JSONPath 缺少字段名: $rawPath');
        }
        tokens.add(
          _JsonPathToken(_JsonPathTokenKind.key, path.substring(start, index)),
        );
        continue;
      }

      if (character == '[') {
        final end = path.indexOf(']', index + 1);
        if (end < 0) throw JsonPathException('JSONPath 缺少 ]: $rawPath');
        final content = path.substring(index + 1, end).trim();
        if (content == '*') {
          tokens.add(const _JsonPathToken(_JsonPathTokenKind.wildcard, '*'));
        } else if (_isInteger(content)) {
          tokens.add(_JsonPathToken(_JsonPathTokenKind.arrayIndex, content));
        } else if (_isQuoted(content)) {
          tokens.add(
            _JsonPathToken(
              _JsonPathTokenKind.key,
              content.substring(1, content.length - 1),
            ),
          );
        } else {
          throw JsonPathException('不支持的 JSONPath 下标: $rawPath');
        }
        index = end + 1;
        continue;
      }

      throw JsonPathException('不支持的 JSONPath 语法: $rawPath');
    }
    return tokens;
  }

  bool _isKeyCharacter(String character) =>
      RegExp(r'[A-Za-z0-9_\-$]').hasMatch(character);

  bool _isInteger(String value) => RegExp(r'^\d+$').hasMatch(value);

  bool _isQuoted(String value) =>
      value.length >= 2 &&
      ((value.startsWith("'") && value.endsWith("'")) ||
          (value.startsWith('"') && value.endsWith('"')));
}

enum _JsonPathTokenKind { key, arrayIndex, wildcard }

class _JsonPathToken {
  final _JsonPathTokenKind kind;
  final String value;

  const _JsonPathToken(this.kind, this.value);
}

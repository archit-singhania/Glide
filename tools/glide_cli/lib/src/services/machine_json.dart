import 'dart:convert';

/// Extracts a JSON object (`open: '{'`) or array (`open: '['`) from tool
/// output that may have banners or warnings around it.
///
/// Flutter can print lines such as "Waiting for another flutter command to
/// release the startup lock..." before the JSON. Returns null if no candidate
/// parses.
Object? decodeEmbeddedJson(String text, {required String open}) {
  final close = open == '{' ? '}' : ']';
  final end = text.lastIndexOf(close);
  if (end < 0) return null;

  var lineStart = 0;
  for (final line in text.split('\n')) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith(open)) {
      final start = lineStart + (line.length - trimmed.length);
      if (start < end) {
        try {
          return jsonDecode(text.substring(start, end + 1));
        } on FormatException {
          // Not JSON from this line; try the next candidate.
        }
      }
    }
    lineStart += line.length + 1;
  }
  return null;
}

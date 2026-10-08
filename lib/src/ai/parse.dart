import 'dart:convert';

/// Lenient extraction helpers for model output.
/// A malformed response must never crash the app.
class Parse {
  Parse._();

  /// Finds the first {...} block in [raw] and decodes it.
  static Map<String, dynamic>? extractJson(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(raw.substring(start, end + 1));
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// Last-resort: pull a quoted value out of non-JSON text.
  static String? firstQuoted(String raw, String key) {
    final m = RegExp('"?$key"?\\s*:\\s*"([^"]+)"').firstMatch(raw);
    return m?.group(1);
  }

  /// Parse a yes/no reply from the vision model.
  /// Anything starting with 'y' counts as yes; 'n' as no.
  static bool yesNo(String raw, {bool defaultTo = true}) {
    final t = raw.trim().toLowerCase();
    if (t.startsWith('y')) return true;
    if (t.startsWith('n')) return false;
    return defaultTo;
  }
}

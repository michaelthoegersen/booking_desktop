/// Strips the "CSS_" prefix from bus identifiers for display purposes.
/// e.g. "CSS_1034" → "1034", "YCR 682" → "YCR 682"
String fmtBus(String? raw) {
  if (raw == null || raw.isEmpty) return '';
  if (raw.startsWith('CSS_')) return raw.substring(4);
  return raw;
}

// SPDX-License-Identifier: GPL-3.0-only

String normalizeMoespFileName(String value) {
  final name = value.trim();
  if (name.isEmpty ||
      name.length > 120 ||
      name.contains(RegExp(r'[/\\:*?"<>|\u0000-\u001f]'))) {
    throw const FormatException('Invalid document file name.');
  }
  return name.toLowerCase().endsWith('.moesp') ? name : '$name.moesp';
}

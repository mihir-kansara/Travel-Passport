bool isValidDisplayName(String value) {
  final trimmed = value.trim();
  if (trimmed.length < 2 || trimmed.length > 30) {
    return false;
  }
  final pattern = RegExp(r"^[A-Za-z0-9 ._\-\u2019']+$");
  return pattern.hasMatch(trimmed);
}

String? displayNameError(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return 'Display name is required.';
  }
  if (trimmed.length < 2 || trimmed.length > 30) {
    return 'Display name must be 2-30 characters.';
  }
  final pattern = RegExp(r"^[A-Za-z0-9 ._\-\u2019']+$");
  if (!pattern.hasMatch(trimmed)) {
    return 'Use letters, numbers, spaces, . _ - or apostrophes.';
  }
  return null;
}

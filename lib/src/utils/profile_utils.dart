bool isValidDisplayName(String value) {
  final trimmed = value.trim();
  if (trimmed.length < 2 || trimmed.length > 30) {
    return false;
  }
  final pattern = RegExp(
    r"^[\p{L}\p{M}0-9 ._\-\u2019']+$",
    unicode: true,
  );
  return pattern.hasMatch(trimmed);
}

String normalizeHandle(String value) {
  var trimmed = value.trim();
  if (trimmed.startsWith('@')) {
    trimmed = trimmed.substring(1);
  }
  return trimmed.toLowerCase();
}

bool isValidHandle(String value) {
  final normalized = normalizeHandle(value);
  if (normalized.length < 3 || normalized.length > 20) {
    return false;
  }
  final pattern = RegExp(r'^[a-z0-9_]+$');
  return pattern.hasMatch(normalized);
}

String? handleError(String value) {
  final normalized = normalizeHandle(value);
  if (normalized.isEmpty) {
    return null;
  }
  if (normalized.length < 3 || normalized.length > 20) {
    return 'Username must be 3-20 characters.';
  }
  final pattern = RegExp(r'^[a-z0-9_]+$');
  if (!pattern.hasMatch(normalized)) {
    return 'Use lowercase letters, numbers, or underscores.';
  }
  return null;
}

String? bioError(String value) {
  final trimmed = value.trim();
  if (trimmed.length > 160) {
    return 'Bio must be 160 characters or fewer.';
  }
  return null;
}

String? displayNameError(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return 'Display name is required.';
  }
  if (trimmed.length < 2 || trimmed.length > 30) {
    return 'Display name must be 2-30 characters.';
  }
  final pattern = RegExp(
    r"^[\p{L}\p{M}0-9 ._\-\u2019']+$",
    unicode: true,
  );
  if (!pattern.hasMatch(trimmed)) {
    return 'Use letters, numbers, spaces, . _ - or apostrophes.';
  }
  return null;
}

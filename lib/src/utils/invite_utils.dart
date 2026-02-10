import 'package:shared_preferences/shared_preferences.dart';

const String _pendingInviteKey = 'pending_invite_token';
const String _inviteHost = 'travelpassport.app';

String? parseInviteTokenFromUri(Uri uri) {
  final tokenParam = uri.queryParameters['token'];
  if (tokenParam != null && tokenParam.trim().isNotEmpty) {
    return tokenParam.trim();
  }
  if (uri.scheme == 'travelpassport' && uri.host == 'invite') {
    return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
  }
  if ((uri.scheme == 'https' || uri.scheme == 'http') &&
      uri.host == _inviteHost &&
      uri.pathSegments.isNotEmpty &&
      uri.pathSegments.first == 'invite') {
    return uri.pathSegments.length > 1 ? uri.pathSegments[1] : null;
  }
  return null;
}

String? parseInviteTokenFromText(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return null;

  final directUri = _tryParseUri(trimmed);
  if (directUri != null) {
    final token = parseInviteTokenFromUri(directUri);
    if (token != null && token.isNotEmpty) return token;
  }

  final urlMatch = RegExp(r'(https?://\S+|travelpassport://\S+)')
      .firstMatch(trimmed);
  if (urlMatch != null) {
    final urlText = urlMatch.group(0);
    if (urlText != null) {
      final urlUri = _tryParseUri(urlText.replaceAll(RegExp(r'[).,]$'), ''));
      if (urlUri != null) {
        final token = parseInviteTokenFromUri(urlUri);
        if (token != null && token.isNotEmpty) return token;
      }
    }
  }

  final labeledToken = RegExp(
    r'(token|invite|code)\s*[:\-]?\s*([A-Za-z0-9-]{6,})',
    caseSensitive: false,
  ).firstMatch(trimmed);
  if (labeledToken != null) {
    return labeledToken.group(2);
  }

  if (!trimmed.contains(RegExp(r'\s'))) {
    return _looksLikeToken(trimmed) ? trimmed : null;
  }

  return null;
}

bool _looksLikeToken(String value) {
  if (value.length < 6) return false;
  return RegExp(r'^[A-Za-z0-9-]+$').hasMatch(value);
}

Uri? _tryParseUri(String value) {
  try {
    final uri = Uri.parse(value);
    if (!uri.hasScheme) return null;
    return uri;
  } catch (_) {
    return null;
  }
}

class InviteTokenStore {
  static Future<void> savePendingToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingInviteKey, token);
  }

  static Future<String?> loadPendingToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_pendingInviteKey);
  }

  static Future<void> clearPendingToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingInviteKey);
  }
}

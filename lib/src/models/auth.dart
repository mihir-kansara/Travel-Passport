class AuthSession {
  final String userId;
  final String displayName;
  final String? email;
  final String? avatarUrl;

  const AuthSession({
    required this.userId,
    required this.displayName,
    this.email,
    this.avatarUrl,
  });
}

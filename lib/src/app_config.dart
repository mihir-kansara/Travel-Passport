class AppConfig {
  static const appName = String.fromEnvironment(
    'APP_NAME',
    defaultValue: 'Travel Passport',
  );

  static const inviteBaseUrl = String.fromEnvironment(
    'INVITE_BASE_URL',
    defaultValue: 'https://travelpassport.app/invite',
  );

  static String inviteLink(String token) {
    return '$inviteBaseUrl/$token';
  }

  static const supportEmail = String.fromEnvironment(
    'SUPPORT_EMAIL',
    defaultValue: 'support@travelpassport.app',
  );
}

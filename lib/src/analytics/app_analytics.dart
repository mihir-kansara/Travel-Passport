import 'package:firebase_analytics/firebase_analytics.dart';

class AppAnalytics {
  AppAnalytics(this._analytics);

  final FirebaseAnalytics _analytics;

  Future<void> logInviteDeepLink({required String token}) {
    return _analytics.logEvent(
      name: 'invite_deep_link',
      parameters: {'token': token},
    );
  }

  Future<void> logCreateTrip({
    required String tripId,
    required String visibility,
  }) {
    return _analytics.logEvent(
      name: 'create_trip',
      parameters: {'trip_id': tripId, 'visibility': visibility},
    );
  }

  Future<void> logInviteCreated({
    required String tripId,
    required String role,
    required String source,
  }) {
    return _analytics.logEvent(
      name: 'invite_created',
      parameters: {'trip_id': tripId, 'role': role, 'source': source},
    );
  }
}

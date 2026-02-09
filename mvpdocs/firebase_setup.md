# Firebase Setup (Travel Passport)

This doc starts the Firebase setup for Android + iOS (mobile-only). It captures the steps you need to finish in the Firebase Console and locally.

## 1) Choose app IDs (required)
- Android package name (applicationId): `com.travelpassport.app`
- iOS bundle identifier: `com.travelpassport.app`

Pick the final IDs you want and update them in:
- Android: android/app/build.gradle.kts -> `applicationId`
- iOS: ios/Runner.xcodeproj -> Bundle Identifier

## 2) Create Firebase project
1. Go to https://console.firebase.google.com
2. Create project: `travel-passport`
3. Add apps:
   - Android app with your final package name
   - iOS app with your final bundle identifier

## 3) Download config files
- Android: download `google-services.json`
  - place at: android/app/google-services.json
- iOS: download `GoogleService-Info.plist`
  - place at: ios/Runner/GoogleService-Info.plist

## 4) Enable Firebase Auth
- Enable Google and Apple sign-in providers
- For Apple: add Services ID + Key in Apple Developer console (Apple sign-in requires it)

## 5) Initialize Firebase in Flutter
Preferred (recommended): use FlutterFire CLI to generate `firebase_options.dart`

Commands (run from project root):
1. `dart pub global activate flutterfire_cli`
2. Install Firebase CLI (required by FlutterFire):
  - `npm install -g firebase-tools`
3. Sign in:
  - `firebase login`
4. `flutterfire configure`

This will create: lib/firebase_options.dart

## 6) Next steps to wire in code
- Enable firebase packages in pubspec.yaml:
  - firebase_core
  - firebase_auth
  - cloud_firestore
- Initialize Firebase in main.dart (after `firebase_options.dart` is generated)
- Replace demo auth in AuthFlow with Firebase Auth
- Switch repository provider to FirestoreTripRepository

## 7) Invite links
Once Firebase is live, we can add invite link creation using:
- Firestore collection: invites
- Dynamic Links (or App Links with a custom domain)
- Join request workflow: invite -> request -> approval -> member add

---
If you share your final app IDs, I can update the Android/iOS config files and wire Firebase init + auth flow immediately.

Getting started (Android-only MVP)

1) Install Flutter and Android SDK (ensure `flutter` is on PATH).

2) From project root run:

```bash
flutter pub get
flutter run -d emulator-5554
```

3) This scaffold uses a local mock repository for the feed. To integrate Firebase, run `flutterfire configure` and add the generated `google-services.json` under `android/app`.

Next steps I can take for you:
- Wire Firebase (Auth, Firestore, Storage, Analytics, FCM)
- Implement real upload flows and security rules
- Add tests and CI

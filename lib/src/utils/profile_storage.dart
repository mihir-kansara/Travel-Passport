import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

class ProfilePhotoUploadResult {
  final String? downloadUrl;
  final Object? error;

  const ProfilePhotoUploadResult({this.downloadUrl, this.error});

  bool get isSuccess => downloadUrl != null;
}

Future<ProfilePhotoUploadResult> uploadProfilePhoto({
  required String userId,
  required Uint8List bytes,
}) async {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final ref = FirebaseStorage.instance
      .ref()
      .child('users')
      .child(userId)
      .child('profile_$timestamp.jpg');
  try {
    final task = await ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    final url = await task.ref.getDownloadURL();
    return ProfilePhotoUploadResult(downloadUrl: url);
  } catch (e) {
    return ProfilePhotoUploadResult(error: e);
  }
}

import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

Future<String> uploadProfilePhoto({
  required String userId,
  required Uint8List bytes,
}) async {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final ref = FirebaseStorage.instance
      .ref()
      .child('users')
      .child(userId)
      .child('profile_$timestamp.jpg');
  final task = await ref.putData(
    bytes,
    SettableMetadata(contentType: 'image/jpeg'),
  );
  return task.ref.getDownloadURL();
}

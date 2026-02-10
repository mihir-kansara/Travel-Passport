import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_application_trial/src/providers.dart';
import 'package:flutter_application_trial/src/repositories/repository.dart';
import 'package:flutter_application_trial/src/utils/profile_storage.dart';
import 'package:flutter_application_trial/src/utils/profile_utils.dart';
import 'package:flutter_application_trial/src/widgets/app_scaffold.dart';
import 'package:flutter_application_trial/src/widgets/primary_button.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() =>
      _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _handleController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  Uint8List? _photoBytes;
  bool _isSaving = false;
  bool _removePhoto = false;
  String? _nameErrorText;
  String? _handleErrorText;
  String? _bioErrorText;
  String? _saveErrorText;
  String? _photoErrorText;
  bool _initialized = false;

  @override
  void dispose() {
    _nameController.dispose();
    _handleController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 640,
    );
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _photoBytes = bytes;
      _removePhoto = false;
      _photoErrorText = null;
    });
  }

  void _removeSelectedPhoto() {
    setState(() {
      _photoBytes = null;
      _removePhoto = true;
      _photoErrorText = null;
    });
  }

  void _previewPhoto(ImageProvider<Object> image) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: const EdgeInsets.all(12),
        content: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image(image: image),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveProfile() async {
    final session = ref.read(authSessionProvider).value;
    if (session == null) return;
    final nameError = displayNameError(_nameController.text);
    final handleErrorText = handleError(_handleController.text);
    final bioErrorText = bioError(_bioController.text);
    if (nameError != null || handleErrorText != null || bioErrorText != null) {
      setState(() {
        _nameErrorText = nameError;
        _handleErrorText = handleErrorText;
        _bioErrorText = bioErrorText;
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _saveErrorText = null;
      _photoErrorText = null;
    });

    try {
      final repo = ref.read(repositoryProvider);
      final existing = await repo.getUserProfile(session.userId);
      final now = DateTime.now();
      final normalizedHandle = normalizeHandle(_handleController.text);
      if (normalizedHandle.isNotEmpty) {
        final available = await repo.isHandleAvailable(
          normalizedHandle,
          excludeUserId: session.userId,
        );
        if (!available) {
          setState(() {
            _handleErrorText = 'This username is taken.';
            _isSaving = false;
          });
          return;
        }
      }
      var photoUrl = _removePhoto
          ? null
          : (existing?.photoUrl ?? session.avatarUrl);
      if (_photoBytes != null) {
        final upload = await uploadProfilePhoto(
          userId: session.userId,
          bytes: _photoBytes!,
        );
        if (upload.isSuccess) {
          photoUrl = upload.downloadUrl;
        } else {
          setState(() {
            _photoErrorText = _describePhotoError(upload.error);
          });
          debugPrint('Profile photo upload failed: ${upload.error}');
        }
      }
      final bio = _bioController.text.trim();

      final profile = UserProfile(
        userId: session.userId,
        displayName: _nameController.text.trim(),
        handle: normalizedHandle.isEmpty ? null : normalizedHandle,
        email: session.email,
        photoUrl: photoUrl,
        bio: bio.isEmpty ? null : bio,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );

      await _runSaveStep(
        'saving profile data',
        () => repo.updateUserProfile(profile),
      );
      // FirebaseAuth profile updates are skipped; Firestore is the source of truth.

      ref.invalidate(currentUserProfileProvider);
      ref.invalidate(userProfileProvider(session.userId));
    } catch (e) {
      final message = _describeSaveError(e);
      debugPrint('Profile setup failed: $e');
      setState(() => _saveErrorText = message);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _runSaveStep(
    String label,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e) {
      throw _ProfileSaveException(label, e);
    }
  }

  String _describeSaveError(Object error) {
    if (error is _ProfileSaveException) {
      final details = _describeSaveError(error.error);
      return 'Unable to save your profile while ${error.step}. $details';
    }
    if (error is FirebaseAuthException) {
      final details = error.message?.trim();
      return details == null || details.isEmpty
          ? 'Unable to save your profile.'
          : 'Unable to save your profile. $details';
    }
    if (error is FirebaseException) {
      final details = error.message?.trim();
      return details == null || details.isEmpty
          ? 'Unable to save your profile.'
          : 'Unable to save your profile. $details';
    }
    return 'Unable to save your profile. ${error.toString()}';
  }

  String _describePhotoError(Object? error) {
    if (error is FirebaseException) {
      if (error.code == 'object-not-found') {
        return 'We could not save your photo. You can retry or continue without it.';
      }
    }
    return 'We could not upload your photo. You can retry or continue without it.';
  }

  Future<void> _retryPhotoUpload() async {
    final session = ref.read(authSessionProvider).value;
    if (session == null || _photoBytes == null) return;
    setState(() {
      _isSaving = true;
      _photoErrorText = null;
    });
    try {
      final repo = ref.read(repositoryProvider);
      final upload = await uploadProfilePhoto(
        userId: session.userId,
        bytes: _photoBytes!,
      );
      if (!upload.isSuccess) {
        setState(() => _photoErrorText = _describePhotoError(upload.error));
        return;
      }
      final profile = await repo.getUserProfile(session.userId);
      if (profile != null) {
        await repo.updateUserProfile(
          profile.copyWith(
            photoUrl: upload.downloadUrl,
            updatedAt: DateTime.now(),
          ),
        );
      }
      ref.invalidate(currentUserProfileProvider);
      ref.invalidate(userProfileProvider(session.userId));
      setState(() {
        _photoBytes = null;
        _removePhoto = false;
      });
    } catch (e) {
      setState(() => _photoErrorText = _describePhotoError(e));
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authSessionProvider).value;
    final profileAsync = ref.watch(currentUserProfileProvider);
    final profile = profileAsync.value;
    ImageProvider<Object>? avatarImage;
    if (!_removePhoto) {
      if (_photoBytes != null) {
        avatarImage = MemoryImage(_photoBytes!);
      } else if (profile?.photoUrl != null) {
        avatarImage = NetworkImage(profile!.photoUrl!);
      } else if (session?.avatarUrl != null) {
        avatarImage = NetworkImage(session!.avatarUrl!);
      }
    }

    if (!_initialized && session != null) {
      _nameController.text =
          profile?.displayName ?? session.displayName;
      _handleController.text = profile?.handle ?? '';
      _bioController.text = profile?.bio ?? '';
      _initialized = true;
    }

    return AppScaffold(
      showAppBar: false,
      padding: EdgeInsets.zero,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          children: [
            Text(
              'Set up your profile',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a display name so your trips look consistent across devices.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  CircleAvatar(
                    radius: 42,
                    backgroundColor: const Color(0xFFE2E8F0),
                    backgroundImage: avatarImage,
                    child: avatarImage == null
                        ? Text(
                            _initials(_nameController.text.isEmpty
                                ? 'Traveler'
                                : _nameController.text),
                            style:
                                Theme.of(context).textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                          )
                        : null,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: IconButton(
                      onPressed: _isSaving ? null : _pickPhoto,
                      icon: const Icon(Icons.photo_camera),
                      color: const Color(0xFF0F172A),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: _isSaving || avatarImage == null
                      ? null
                      : () => _previewPhoto(avatarImage!),
                  child: const Text('Preview'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _isSaving ? null : _removeSelectedPhoto,
                  child: const Text('Remove photo'),
                ),
              ],
            ),
            if (_photoErrorText != null) ...[
              const SizedBox(height: 8),
              Text(
                _photoErrorText!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFDC2626),
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: _isSaving ? null : _retryPhotoUpload,
                    child: const Text('Retry upload'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _isSaving
                        ? null
                        : () {
                            setState(() {
                              _photoBytes = null;
                              _photoErrorText = null;
                            });
                          },
                    child: const Text('Continue without photo'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (_nameErrorText != null) {
                  setState(() => _nameErrorText = null);
                }
              },
              decoration: InputDecoration(
                labelText: 'Display name',
                hintText: 'e.g. Alex Carter',
                errorText: _nameErrorText,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '2-30 characters. Letters, numbers, spaces, and . _ - apostrophes.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF94A3B8),
                  ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _handleController,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (_handleErrorText != null) {
                  setState(() => _handleErrorText = null);
                }
              },
              decoration: InputDecoration(
                labelText: 'Username',
                hintText: 'yourname',
                prefixText: '@',
                errorText: _handleErrorText,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Optional. 3-20 lowercase letters, numbers, or underscores.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF94A3B8),
                  ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _bioController,
              textInputAction: TextInputAction.newline,
              maxLines: 3,
              maxLength: 160,
              onChanged: (_) {
                if (_bioErrorText != null) {
                  setState(() => _bioErrorText = null);
                }
              },
              decoration: InputDecoration(
                labelText: 'Bio (optional)',
                hintText: 'A short line about you',
                errorText: _bioErrorText,
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (_saveErrorText != null) ...[
              Text(
                _saveErrorText!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFDC2626),
                    ),
              ),
              const SizedBox(height: 12),
            ],
            PrimaryButton(
              label: _isSaving ? 'Saving...' : 'Continue',
              onPressed: _isSaving ? null : _saveProfile,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileSaveException implements Exception {
  final String step;
  final Object error;

  const _ProfileSaveException(this.step, this.error);

  @override
  String toString() => 'Profile save failed while $step: $error';
}

String _initials(String name) {
  final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return 'TP';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

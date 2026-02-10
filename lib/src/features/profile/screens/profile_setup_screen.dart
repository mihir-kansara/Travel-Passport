import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  Uint8List? _photoBytes;
  bool _isSaving = false;
  String? _errorText;
  bool _initialized = false;

  @override
  void dispose() {
    _nameController.dispose();
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
    setState(() => _photoBytes = bytes);
  }

  Future<void> _saveProfile() async {
    final session = ref.read(authSessionProvider).value;
    if (session == null) return;
    final error = displayNameError(_nameController.text);
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }

    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    try {
      final repo = ref.read(repositoryProvider);
      final existing = await repo.getUserProfile(session.userId);
      final now = DateTime.now();
      var photoUrl = existing?.photoUrl;
      if (_photoBytes != null) {
        photoUrl = await uploadProfilePhoto(
          userId: session.userId,
          bytes: _photoBytes!,
        );
      }

      final profile = UserProfile(
        userId: session.userId,
        displayName: _nameController.text.trim(),
        email: session.email,
        photoUrl: photoUrl,
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
      setState(() => _errorText = message);
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
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authSessionProvider).value;
    final profileAsync = ref.watch(currentUserProfileProvider);
    final profile = profileAsync.value;
    ImageProvider<Object>? avatarImage;
    if (_photoBytes != null) {
      avatarImage = MemoryImage(_photoBytes!);
    } else if (profile?.photoUrl != null) {
      avatarImage = NetworkImage(profile!.photoUrl!);
    } else if (session?.avatarUrl != null) {
      avatarImage = NetworkImage(session!.avatarUrl!);
    }

    if (!_initialized && session != null) {
        _nameController.text =
          profile?.displayName ?? session.displayName;
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
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (_errorText != null) {
                  setState(() => _errorText = null);
                }
              },
              decoration: InputDecoration(
                labelText: 'Display name',
                hintText: 'e.g. Alex Carter',
                errorText: _errorText,
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
            const SizedBox(height: 20),
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

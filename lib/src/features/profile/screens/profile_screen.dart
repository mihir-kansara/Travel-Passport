import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_application_trial/src/models/auth.dart';
import 'package:flutter_application_trial/src/providers.dart';
import 'package:flutter_application_trial/src/repositories/repository.dart';
import 'package:flutter_application_trial/src/utils/profile_storage.dart';
import 'package:flutter_application_trial/src/utils/profile_utils.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider).value;
    final profileAsync = ref.watch(currentUserProfileProvider);
    final profile = profileAsync.value;
    final tripsAsync = ref.watch(userTripsProvider);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _ProfileHeader(session: session, profile: profile),
        const SizedBox(height: 20),
        if (session != null &&
            (profile == null || !isValidDisplayName(profile.displayName)))
          _ProfileCompletionCard(
            onComplete: () {
              context.push('/profile/setup');
            },
          ),
        if (session != null) const SizedBox(height: 20),
        tripsAsync.when(
          data: (trips) {
            final sharedCount = trips
                .where((t) => t.story.publishToWall)
                .length;
            return _ProfileStats(
              tripsCount: trips.length,
              sharedCount: sharedCount,
            );
          },
          loading: () => const _StatsPlaceholder(),
          error: (error, stack) =>
              const _ProfileStats(tripsCount: 0, sharedCount: 0),
        ),
        const SizedBox(height: 20),
        if (session != null) _ProfileEditor(session: session, profile: profile),
        if (session != null) const SizedBox(height: 20),
        _SettingsSection(),
        const SizedBox(height: 20),
        if (session != null)
          ElevatedButton(
            onPressed: () => ref.read(firebaseAuthProvider).signOut(),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text('Sign out'),
          )
        else
          Text(
            'Sign in to manage your profile.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
          ),
      ],
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  final AuthSession? session;
  final UserProfile? profile;

  const _ProfileHeader({required this.session, required this.profile});

  @override
  Widget build(BuildContext context) {
    final displayName = profile?.displayName.isNotEmpty == true
        ? profile!.displayName
        : (session?.displayName ?? 'Traveler');
    final avatarUrl = profile?.photoUrl ?? session?.avatarUrl;
    final initials = _initials(displayName);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: const Color(0xFFE2E8F0),
            backgroundImage: avatarUrl != null
                ? CachedNetworkImageProvider(avatarUrl)
                : null,
            child: avatarUrl == null
                ? Text(
                    initials,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  session?.email ?? 'No email connected',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileStats extends StatelessWidget {
  final int tripsCount;
  final int sharedCount;

  const _ProfileStats({required this.tripsCount, required this.sharedCount});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(label: 'Trips', value: tripsCount.toString()),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(label: 'Shared', value: sharedCount.toString()),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;

  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}

class _StatsPlaceholder extends StatelessWidget {
  const _StatsPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(label: 'Trips', value: '...'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatCard(label: 'Shared', value: '...'),
        ),
      ],
    );
  }
}

class _ProfileCompletionCard extends StatelessWidget {
  final VoidCallback onComplete;

  const _ProfileCompletionCard({required this.onComplete});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, color: Color(0xFF4F46E5)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Complete your profile',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  'Add a display name so your trips stay consistent.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton(onPressed: onComplete, child: const Text('Finish')),
        ],
      ),
    );
  }
}

class _ProfileEditor extends ConsumerStatefulWidget {
  final AuthSession session;
  final UserProfile? profile;

  const _ProfileEditor({required this.session, required this.profile});

  @override
  ConsumerState<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends ConsumerState<_ProfileEditor> {
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
      final now = DateTime.now();
      final normalizedHandle = normalizeHandle(_handleController.text);
      if (normalizedHandle.isNotEmpty) {
        final available = await repo.isHandleAvailable(
          normalizedHandle,
          excludeUserId: widget.session.userId,
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
          : (widget.profile?.photoUrl ?? widget.session.avatarUrl);
      if (_photoBytes != null) {
        final upload = await uploadProfilePhoto(
          userId: widget.session.userId,
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
        userId: widget.session.userId,
        displayName: _nameController.text.trim(),
        handle: normalizedHandle.isEmpty ? null : normalizedHandle,
        email: widget.session.email,
        photoUrl: photoUrl,
        bio: bio.isEmpty ? null : bio,
        createdAt: widget.profile?.createdAt ?? now,
        updatedAt: now,
      );

      await _runSaveStep(
        'saving profile data',
        () => repo.updateUserProfile(profile),
      );
      // FirebaseAuth profile updates are skipped; Firestore is the source of truth.

      ref.invalidate(currentUserProfileProvider);
      ref.invalidate(userProfileProvider(widget.session.userId));
    } catch (e) {
      final message = _describeSaveError(e);
      debugPrint('Profile update failed: $e');
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
      return 'Unable to update profile while ${error.step}. $details';
    }
    if (error is FirebaseAuthException) {
      final details = error.message?.trim();
      return details == null || details.isEmpty
          ? 'Unable to update profile.'
          : 'Unable to update profile. $details';
    }
    if (error is FirebaseException) {
      final details = error.message?.trim();
      return details == null || details.isEmpty
          ? 'Unable to update profile.'
          : 'Unable to update profile. $details';
    }
    return 'Unable to update profile. ${error.toString()}';
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
    if (_photoBytes == null) return;
    setState(() {
      _isSaving = true;
      _photoErrorText = null;
    });
    try {
      final repo = ref.read(repositoryProvider);
      final upload = await uploadProfilePhoto(
        userId: widget.session.userId,
        bytes: _photoBytes!,
      );
      if (!upload.isSuccess) {
        setState(() => _photoErrorText = _describePhotoError(upload.error));
        return;
      }
      final profile = await repo.getUserProfile(widget.session.userId);
      if (profile != null) {
        await repo.updateUserProfile(
          profile.copyWith(
            photoUrl: upload.downloadUrl,
            updatedAt: DateTime.now(),
          ),
        );
      }
      ref.invalidate(currentUserProfileProvider);
      ref.invalidate(userProfileProvider(widget.session.userId));
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
    final displayName = widget.profile?.displayName.isNotEmpty == true
        ? widget.profile!.displayName
        : widget.session.displayName;
    final avatarUrl = widget.profile?.photoUrl ?? widget.session.avatarUrl;
    if (!_initialized) {
      _nameController.text = displayName;
      _handleController.text = widget.profile?.handle ?? '';
      _bioController.text = widget.profile?.bio ?? '';
      _initialized = true;
    }
    ImageProvider<Object>? avatarImage;
    if (!_removePhoto) {
      if (_photoBytes != null) {
        avatarImage = MemoryImage(_photoBytes!);
      } else if (avatarUrl != null) {
        avatarImage = CachedNetworkImageProvider(avatarUrl);
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Profile',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(0xFFE2E8F0),
                backgroundImage: avatarImage,
                child: avatarImage == null
                    ? Text(
                        _initials(displayName),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Update your name, username, bio, and photo.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ),
              TextButton(
                onPressed: _isSaving ? null : _pickPhoto,
                child: const Text('Change photo'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
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
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFFDC2626)),
            ),
            const SizedBox(height: 6),
            Row(
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
          const SizedBox(height: 12),
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
              errorText: _nameErrorText,
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
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
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF94A3B8)),
          ),
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
          if (_saveErrorText != null) ...[
            Text(
              _saveErrorText!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFFDC2626)),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _saveProfile,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: Text(_isSaving ? 'Saving...' : 'Save changes'),
            ),
          ),
        ],
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

class _SettingsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Settings',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        _SettingsTile(title: 'Notifications', subtitle: 'Coming soon'),
        _SettingsTile(title: 'Privacy', subtitle: 'Coming soon'),
        _SettingsTile(title: 'Blocked users', subtitle: 'Coming soon'),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SettingsTile({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: Color(0xFF94A3B8)),
        ],
      ),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return 'TP';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

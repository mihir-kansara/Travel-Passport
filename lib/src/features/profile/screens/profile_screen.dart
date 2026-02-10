import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_application_trial/src/models/auth.dart';
import 'package:flutter_application_trial/src/providers.dart';
import 'package:flutter_application_trial/src/repositories/repository.dart';
import 'package:flutter_application_trial/src/utils/profile_storage.dart';
import 'package:flutter_application_trial/src/utils/profile_utils.dart';
import 'package:flutter_application_trial/src/features/profile/screens/profile_setup_screen.dart';

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
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ProfileSetupScreen()),
              );
            },
          ),
        if (session != null) const SizedBox(height: 20),
        tripsAsync.when(
          data: (trips) {
            final sharedCount =
                trips.where((t) => t.story.publishToWall).length;
            return _ProfileStats(
              tripsCount: trips.length,
              sharedCount: sharedCount,
            );
          },
          loading: () => const _StatsPlaceholder(),
          error: (error, stack) => const _ProfileStats(
            tripsCount: 0,
            sharedCount: 0,
          ),
        ),
        const SizedBox(height: 20),
        if (session != null)
          _ProfileEditor(
            session: session,
            profile: profile,
          ),
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
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
            ),
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
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
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
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
            ),
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
        Expanded(child: _StatCard(label: 'Trips', value: '...')),
        const SizedBox(width: 12),
        Expanded(child: _StatCard(label: 'Shared', value: '...')),
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
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
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
          TextButton(
            onPressed: onComplete,
            child: const Text('Finish'),
          ),
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
      final now = DateTime.now();
      var photoUrl = widget.profile?.photoUrl ?? widget.session.avatarUrl;
      if (_photoBytes != null) {
        photoUrl = await uploadProfilePhoto(
          userId: widget.session.userId,
          bytes: _photoBytes!,
        );
      }

      final profile = UserProfile(
        userId: widget.session.userId,
        displayName: _nameController.text.trim(),
        email: widget.session.email,
        photoUrl: photoUrl,
        createdAt: widget.profile?.createdAt ?? now,
        updatedAt: now,
      );

      await repo.updateUserProfile(profile);
      await FirebaseAuth.instance.currentUser
          ?.updateDisplayName(profile.displayName);
      if (profile.photoUrl != null) {
        await FirebaseAuth.instance.currentUser
            ?.updatePhotoURL(profile.photoUrl);
      }

      ref.invalidate(currentUserProfileProvider);
      ref.invalidate(userProfileProvider(widget.session.userId));
    } catch (e) {
      setState(() => _errorText = 'Unable to update profile.');
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
      _initialized = true;
    }
    ImageProvider<Object>? avatarImage;
    if (_photoBytes != null) {
      avatarImage = MemoryImage(_photoBytes!);
    } else if (avatarUrl != null) {
      avatarImage = CachedNetworkImageProvider(avatarUrl);
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
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
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
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Update your display name and photo.',
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
          const SizedBox(height: 12),
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
              errorText: _errorText,
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
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

class _SettingsSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Settings',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
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
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
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

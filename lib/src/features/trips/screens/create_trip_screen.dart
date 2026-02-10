import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_trial/src/app_theme.dart';
import 'package:flutter_application_trial/src/models/trip.dart';
import 'package:flutter_application_trial/src/providers.dart';
import 'package:flutter_application_trial/src/utils/async_guard.dart';
import 'package:flutter_application_trial/src/widgets/app_scaffold.dart';
import 'package:flutter_application_trial/src/widgets/primary_button.dart';
import 'package:flutter_application_trial/src/widgets/secondary_button.dart';
import 'package:flutter_application_trial/src/widgets/section_header.dart';

class CreateTripScreen extends ConsumerStatefulWidget {
  const CreateTripScreen({super.key});

  @override
  ConsumerState<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends ConsumerState<CreateTripScreen> {
  static const _recentKey = 'recent_destinations';
  static const List<LinearGradient> _coverGradients = [
    LinearGradient(colors: [Color(0xFF0EA5E9), Color(0xFF6366F1)]),
    LinearGradient(colors: [Color(0xFF22C55E), Color(0xFF14B8A6)]),
    LinearGradient(colors: [Color(0xFFF97316), Color(0xFFEF4444)]),
    LinearGradient(colors: [Color(0xFFA855F7), Color(0xFFEC4899)]),
    LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFF84CC16)]),
  ];
  final _destinationController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _heroController = TextEditingController();
  DateTimeRange? _dateRange;
  TripVisibility _visibility = TripVisibility.inviteOnly;
  bool _isSaving = false;
  int _stepIndex = 0;
  List<String> _cities = [];
  List<String> _recentDestinations = [];
  int? _selectedGradientId;
  bool _showValidation = false;

  bool get _isDateRangeValid {
    if (_dateRange == null) return false;
    return _dateRange!.end.isAfter(_dateRange!.start);
  }

  bool get _isBasicsValid {
    return _destinationController.text.trim().isNotEmpty && _isDateRangeValid;
  }

  @override
  void initState() {
    super.initState();
    _loadCities();
    _loadRecentDestinations();
  }

  Future<void> _loadCities() async {
    final data = await rootBundle.loadString('assets/cities.json');
    final decoded = jsonDecode(data) as List<dynamic>;
    if (!mounted) return;
    setState(() {
      _cities = decoded.map((e) => e.toString()).toList();
    });
  }

  Future<void> _loadRecentDestinations() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_recentKey) ?? [];
    if (!mounted) return;
    setState(() => _recentDestinations = stored);
  }

  Future<void> _saveRecentDestination(String destination) async {
    final normalized = destination.trim();
    if (normalized.isEmpty) return;
    final updated = [
      normalized,
      ..._recentDestinations.where((d) => d != normalized),
    ].take(5).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentKey, updated);
    if (!mounted) return;
    setState(() => _recentDestinations = updated);
  }

  @override
  void dispose() {
    _destinationController.dispose();
    _descriptionController.dispose();
    _heroController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Create Trip',
      onHome: () => context.go('/home'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StepHeader(stepIndex: _stepIndex),
          const SizedBox(height: AppSpacing.xl),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _stepIndex == 0
                  ? _buildBasicsStep(context)
                  : _buildStoryStep(),
            ),
          ),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildBasicsStep(BuildContext context) {
    final dateLabel = _dateRange == null
        ? 'Pick dates'
        : '${DateFormat('MMM d').format(_dateRange!.start)} - '
              '${DateFormat('MMM d').format(_dateRange!.end)}';
    final destinationError =
        _showValidation && _destinationController.text.trim().isEmpty
        ? 'Destination is required.'
        : null;
    String? dateError;
    if (_showValidation) {
      if (_dateRange == null) {
        dateError = 'Dates are required.';
      } else if (!_isDateRangeValid) {
        dateError = 'End date must be after start date.';
      }
    }

    return ListView(
      key: const ValueKey('step-1'),
      children: [
        const SectionHeader(
          title: 'Trip basics',
          subtitle: 'Choose the place, dates, and audience.',
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_recentDestinations.isNotEmpty) ...[
          Text(
            'Recent destinations',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.subtleText,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: _recentDestinations
                .map(
                  (city) => ActionChip(
                    label: Text(city),
                    onPressed: () {
                      _destinationController.text = city;
                      _saveRecentDestination(city);
                      setState(() {});
                    },
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        TypeAheadField<String>(
          controller: _destinationController,
          suggestionsCallback: (pattern) {
            if (pattern.isEmpty) return _cities.take(8).toList();
            return _cities
                .where(
                  (city) => city.toLowerCase().contains(pattern.toLowerCase()),
                )
                .take(8)
                .toList();
          },
          itemBuilder: (context, suggestion) {
            return ListTile(title: Text(suggestion));
          },
          onSelected: (suggestion) {
            _destinationController.text = suggestion;
            _saveRecentDestination(suggestion);
            setState(() {});
          },
          emptyBuilder: (context) => const ListTile(title: Text('No matches')),
          builder: (context, controller, focusNode) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: (_) {
                setState(() => _showValidation = true);
              },
              decoration: InputDecoration(
                labelText: 'Destination',
                hintText: 'Search a city',
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                errorText: destinationError,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  borderSide: BorderSide.none,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        InkWell(
          onTap: _isSaving ? null : _pickDates,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.lg,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined, size: 18),
                const SizedBox(width: AppSpacing.sm),
                Text(dateLabel),
              ],
            ),
          ),
        ),
        if (dateError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            dateError,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFFDC2626)),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<TripVisibility>(
              value: _visibility,
              onChanged: _isSaving
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() => _visibility = value);
                    },
              items: TripVisibility.values
                  .map(
                    (visibility) => DropdownMenuItem(
                      value: visibility,
                      child: Text(_visibilityLabel(visibility)),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _heroController,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: 'Cover photo URL (optional)',
            hintText: 'https://',
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'Choose cover gradient',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: AppColors.subtleText,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _coverGradients.length,
            separatorBuilder: (context, index) =>
                const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, index) {
              final isSelected = _selectedGradientId == index;
              return GestureDetector(
                onTap: () => setState(() => _selectedGradientId = index),
                child: Container(
                  width: 72,
                  decoration: BoxDecoration(
                    gradient: _coverGradients[index],
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(
                      color: isSelected ? AppColors.text : AppColors.border,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, color: Colors.white)
                      : null,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  Widget _buildStoryStep() {
    return ListView(
      key: const ValueKey('step-2'),
      children: [
        const SectionHeader(
          title: 'Story and collaborators',
          subtitle:
              'Add a short description and invite friends after creation.',
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _descriptionController,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Trip description',
            hintText: 'What is the vibe for this trip?',
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.group_add_outlined, color: AppColors.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'You can invite friends once the trip is created.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.mutedText),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    final canProceed = _isBasicsValid && !_isSaving;

    return Column(
      children: [
        Row(
          children: [
            if (_stepIndex == 1)
              Expanded(
                child: SecondaryButton(
                  label: 'Back',
                  onPressed: _isSaving
                      ? null
                      : () => setState(() => _stepIndex = 0),
                ),
              )
            else
              Expanded(
                child: SecondaryButton(
                  label: 'Cancel',
                  onPressed: _isSaving
                      ? null
                      : () => Navigator.of(context).pop(),
                ),
              ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: PrimaryButton(
                label: _stepIndex == 0 ? 'Continue' : 'Create trip',
                isLoading: _isSaving,
                onPressed: !canProceed
                    ? null
                    : () {
                        if (_stepIndex == 0) {
                          if (!_isBasicsValid) {
                            setState(() => _showValidation = true);
                            return;
                          }
                          setState(() => _stepIndex = 1);
                        } else {
                          _handleCreate();
                        }
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    );
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final initialRange = DateTimeRange(
      start: _dateRange?.start ?? now.add(const Duration(days: 7)),
      end: _dateRange?.end ?? now.add(const Duration(days: 10)),
    );
    final range = await showDateRangePicker(
      context: context,
      initialDateRange: initialRange,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (range == null) return;
    setState(() {
      _dateRange = range;
      _showValidation = true;
    });
  }

  Future<void> _handleCreate() async {
    final destination = _destinationController.text.trim();
    final description = _descriptionController.text.trim();
    final heroUrl = _heroController.text.trim();

    if (destination.isEmpty) {
      setState(() => _showValidation = true);
      return;
    }
    if (!_isDateRangeValid) {
      setState(() => _showValidation = true);
      return;
    }

    if (_isSaving) return;
    setState(() => _isSaving = true);
    final allowed = await ensureSignedIn(
      context,
      ref,
      message: 'Sign in to create a trip.',
    );
    if (!mounted) return;
    if (!allowed) {
      if (mounted) setState(() => _isSaving = false);
      return;
    }
    final success = await runGuarded(
      context,
      () async {
        final repo = ref.read(repositoryProvider);
        final trip = await repo.createTrip(
          destination: destination,
          startDate: _dateRange!.start,
          endDate: _dateRange!.end,
          description: description,
          heroImageUrl: heroUrl.isEmpty ? null : heroUrl,
          coverGradientId: _selectedGradientId,
          visibility: _visibility,
        );
        if (!mounted) return;
        await ref
            .read(appAnalyticsProvider)
            .logCreateTrip(tripId: trip.id, visibility: _visibility.name);
        await _saveRecentDestination(destination);
        if (!mounted) return;
        showGuardedSnackBar(context, 'Trip created 🎉');
        context.go('/trips/${trip.id}?tab=planner');
        ref.invalidate(userTripsProvider);
      },
      operation: 'create_trip',
      errorMessage: 'Unable to create trip.',
    );
    if (mounted) {
      setState(() => _isSaving = false);
    }
    if (!success) return;
  }
}

class _StepHeader extends StatelessWidget {
  final int stepIndex;

  const _StepHeader({required this.stepIndex});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StepPill(label: 'Basics', isActive: stepIndex == 0),
        const SizedBox(width: AppSpacing.sm),
        _StepPill(label: 'Story', isActive: stepIndex == 1),
      ],
    );
  }
}

class _StepPill extends StatelessWidget {
  final String label;
  final bool isActive;

  const _StepPill({required this.label, required this.isActive});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFE0E7FF) : Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: isActive ? AppColors.text : AppColors.mutedText,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

String _visibilityLabel(TripVisibility visibility) {
  switch (visibility) {
    case TripVisibility.inviteOnly:
      return 'Private';
    case TripVisibility.friendsOnly:
      return 'Friends';
    case TripVisibility.public:
      return 'Public';
  }
}

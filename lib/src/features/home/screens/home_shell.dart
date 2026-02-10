import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_application_trial/src/providers.dart';
import 'package:flutter_application_trial/src/widgets/app_scaffold.dart';

class HomeShell extends ConsumerWidget {
  final Widget child;
  final String location;

  const HomeShell({super.key, required this.child, required this.location});

  int _indexForLocation(String location) {
    final path = Uri.parse(location).path;
    if (path.startsWith('/trips')) return 1;
    if (path.startsWith('/friends')) return 2;
    if (path.startsWith('/profile')) return 3;
    return 0;
  }

  String _titleForLocation(String location) {
    final path = Uri.parse(location).path;
    if (path.startsWith('/trips')) return 'Trips';
    if (path.startsWith('/friends')) return 'Friends';
    if (path.startsWith('/profile')) return 'Profile';
    return 'Home';
  }

  void _onTap(BuildContext context, int index) {
    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        context.go('/trips');
        break;
      case 2:
        context.go('/friends');
        break;
      case 3:
        context.go('/profile');
        break;
    }
  }

  List<Widget> _actionsForLocation(WidgetRef ref, String location) {
    final path = Uri.parse(location).path;
    if (path.startsWith('/friends')) {
      return [
        IconButton(
          tooltip: 'Refresh',
          icon: const Icon(Icons.refresh_outlined),
          onPressed: () {
            ref.invalidate(friendsProvider);
            ref.invalidate(incomingFriendRequestsProvider);
            ref.invalidate(outgoingFriendRequestsProvider);
          },
        ),
      ];
    }
    return const [];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = _indexForLocation(location);
    return AppScaffold(
      showBack: false,
      showAppBar: true,
      title: _titleForLocation(location),
      actions: _actionsForLocation(ref, location),
      padding: EdgeInsets.zero,
      bottomNavigationBar: SafeArea(
        top: false,
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.black,
              boxShadow: [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 16,
                  offset: Offset(0, -6),
                ),
              ],
            ),
            child: BottomNavigationBar(
              backgroundColor: Colors.black,
              selectedItemColor: Colors.white,
              unselectedItemColor: const Color(0xFFB0B0B0),
              type: BottomNavigationBarType.fixed,
              currentIndex: currentIndex,
              onTap: (index) => _onTap(context, index),
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.luggage_outlined),
                  label: 'Trips',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.group_outlined),
                  label: 'Friends',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      ),
      body: child,
    );
  }
}

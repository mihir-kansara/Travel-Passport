import 'package:flutter/material.dart';
import 'package:flutter_application_trial/src/features/feed/screens/feed_screen.dart';
import 'package:flutter_application_trial/src/features/profile/screens/profile_screen.dart';
import 'package:flutter_application_trial/src/widgets/app_scaffold.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      showBack: false,
      showAppBar: false,
      padding: EdgeInsets.zero,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
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
            icon: Icon(Icons.person_outline),
            label: 'Profile',
          ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          FeedScreen(initialTab: HomeTab.wall),
          FeedScreen(initialTab: HomeTab.trips),
          ProfileScreen(),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_application_trial/src/features/feed/screens/feed_screen.dart';
import 'package:flutter_application_trial/src/features/friends/screens/friends_screen.dart';
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
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          FeedScreen(initialTab: HomeTab.wall),
          FeedScreen(initialTab: HomeTab.trips),
          FriendsScreen(),
          ProfileScreen(),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'map_screen.dart';
import 'history_screen.dart';
import 'walks_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final GlobalKey<MapScreenState> _mapKey = GlobalKey<MapScreenState>();

  void _onPinSelected(LatLng location) {
    setState(() {
      _currentIndex = 0;
    });
    Future.delayed(const Duration(milliseconds: 300), () {
      _mapKey.currentState?.animateToLocation(location);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          MapScreen(key: _mapKey),
          HistoryScreen(onPinSelected: _onPinSelected),
          const WalksScreen(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'),
          BottomNavigationBarItem(
            icon: Icon(Icons.photo_library),
            label: 'Gallery',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.directions_walk),
            label: 'Walks',
          ),
        ],
      ),
    );
  }
}

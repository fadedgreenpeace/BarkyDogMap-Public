import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'services/pin_provider.dart';

void main() {
  runApp(const BarkyDogMapApp());
}

class BarkyDogMapApp extends StatelessWidget {
  const BarkyDogMapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PinProvider()..loadPins()),
      ],
      child: MaterialApp(
        title: 'BarkyDogMap',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

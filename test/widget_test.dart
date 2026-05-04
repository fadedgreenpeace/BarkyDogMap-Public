import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:barkydogmap/main.dart';
import 'package:barkydogmap/screens/map_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // Initialize FFI for testing SQLite on desktop
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('BarkyDogMap app smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const BarkyDogMapApp());

    // Verify that the MapScreen is present
    expect(find.byType(MapScreen), findsOneWidget);

    // Verify that the "Start Walk" FAB is present
    expect(find.text('Start Walk'), findsOneWidget);

    // Verify that the "Mark Hazard" FAB is present by checking for the pets icon
    expect(find.byIcon(Icons.pets), findsOneWidget);
  });
}

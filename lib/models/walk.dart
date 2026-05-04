import 'dart:convert';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class Walk {
  final String? id;
  final DateTime startTime;
  final DateTime endTime;
  final double distanceMeters;
  final String routeJson;

  Walk({
    this.id,
    required this.startTime,
    required this.endTime,
    required this.distanceMeters,
    required this.routeJson,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'distanceMeters': distanceMeters,
      'routeJson': routeJson,
    };
  }

  factory Walk.fromMap(Map<String, dynamic> map) {
    return Walk(
      id: map['id'],
      startTime: DateTime.parse(map['startTime']),
      endTime: DateTime.parse(map['endTime']),
      distanceMeters: map['distanceMeters'],
      routeJson: map['routeJson'],
    );
  }

  /// Helper to convert LatLng list to a JSON string for SQLite storage
  static String encodeRoute(List<LatLng> route) {
    final list = route
        .map((latlng) => {'lat': latlng.latitude, 'lng': latlng.longitude})
        .toList();
    return jsonEncode(list);
  }

  /// Helper to decode JSON string back to a list of LatLng
  List<LatLng> get decodedRoute {
    try {
      final List<dynamic> list = jsonDecode(routeJson);
      return list
          .map((item) => LatLng(item['lat'] as double, item['lng'] as double))
          .toList();
    } catch (e) {
      return [];
    }
  }
}

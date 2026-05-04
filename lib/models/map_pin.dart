class MapPin {
  final String? id;
  final String type;
  final String title;
  final String description;
  final String imagePath;
  final double latitude;
  final double longitude;
  final DateTime timestamp;

  MapPin({
    this.id,
    required this.type,
    this.title = '',
    this.description = '',
    this.imagePath = '',
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'description': description,
      'image_path': imagePath,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory MapPin.fromMap(Map<String, dynamic> map) {
    return MapPin(
      id: map['id'],
      type: map['type'] ?? 'hazard',
      title: map['title'] ?? '',
      description: map['description'] ?? '',
      imagePath: map['image_path'] ?? '',
      latitude: map['latitude'],
      longitude: map['longitude'],
      timestamp: DateTime.parse(map['timestamp']),
    );
  }
}

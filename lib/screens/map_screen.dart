import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import '../models/map_pin.dart';
import '../models/walk.dart';
import '../services/database.dart';
import '../services/pin_provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../services/foreground_task_handler.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => MapScreenState();
}

class MapScreenState extends State<MapScreen> {
  GoogleMapController? _mapController;

  bool _isWalking = false;
  final List<LatLng> _routePoints = [];
  double _totalDistanceMeters = 0.0;
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;

  DateTime? _walkStartTime;
  Timer? _timer;
  Duration _duration = Duration.zero;

  // Lawrence, Kansas coordinates
  static const CameraPosition _initialPosition = CameraPosition(
    target: LatLng(38.9716, -95.2353),
    zoom: 14.0,
  );

  @override
  void initState() {
    super.initState();
    _initForegroundTask();
  }

  void _initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'barkydogmap_foreground_service',
        channelName: 'Walk Tracking',
        channelDescription: 'Keeps GPS tracking active over locked screens.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  void animateToLocation(LatLng coords) {
    if (_mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLngZoom(coords, 18.0));
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionStream?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  // _loadPins removed as PinProvider handles it

  void _showPinDetailsModal(MapPin pin) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pin.title.isNotEmpty
                    ? pin.title
                    : (pin.type == 'poi' ? 'Pup POI' : 'Bark Hazard'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (pin.description.isNotEmpty) ...[
                Text(pin.description, style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 16),
              ],
              if (pin.imagePath.isNotEmpty) ...[
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: Image.file(
                      File(pin.imagePath),
                      fit: BoxFit.cover,
                      height: 250,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<bool> _handleLocationPermission() async {
    PermissionStatus status = await Permission.locationWhenInUse.status;

    if (status.isDenied) {
      status = await Permission.locationWhenInUse.request();
      if (status.isDenied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Location permission is needed to track your walk.',
              ),
            ),
          );
        }
        return false;
      }
    }

    if (status.isPermanentlyDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location permission permanently denied. Please enable it in Settings.',
            ),
          ),
        );
      }
      return false;
    }

    return true;
  }

  void _onReceiveTaskData(dynamic data) {
    if (data is Map && data.containsKey('latitude') && data.containsKey('longitude')) {
      if (mounted) {
        setState(() {
          double lat = data['latitude'];
          double lng = data['longitude'];
          final newPoint = LatLng(lat, lng);
          _currentPosition = Position(
            latitude: lat,
            longitude: lng,
            timestamp: DateTime.now(),
            accuracy: 0.0,
            altitude: 0.0,
            altitudeAccuracy: 0.0,
            heading: 0.0,
            headingAccuracy: 0.0,
            speed: 0.0,
            speedAccuracy: 0.0,
            isMocked: false,
          );

          if (_routePoints.isNotEmpty) {
            final lastPoint = _routePoints.last;
            final distance = Geolocator.distanceBetween(
              lastPoint.latitude,
              lastPoint.longitude,
              newPoint.latitude,
              newPoint.longitude,
            );
            _totalDistanceMeters += distance;
          }

          _routePoints.add(newPoint);

          if (_mapController != null) {
            _mapController!.animateCamera(CameraUpdate.newLatLng(newPoint));
          }
        });
      }
    }
  }

  Future<void> _toggleWalk() async {
    if (_isWalking) {
      _timer?.cancel();
      
      FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
      FlutterForegroundTask.stopService();

      if (_walkStartTime != null && _routePoints.isNotEmpty) {
        final walk = Walk(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          startTime: _walkStartTime!,
          endTime: DateTime.now(),
          distanceMeters: _totalDistanceMeters,
          routeJson: Walk.encodeRoute(_routePoints),
        );
        await DatabaseService.instance.insertWalk(walk);

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Walk saved locally!')));
        }
      }

      setState(() {
        _isWalking = false;
        _routePoints.clear();
        _totalDistanceMeters = 0.0;
        _currentPosition = null;
        _duration = Duration.zero;
        _walkStartTime = null;
      });
      return;
    }

    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location services are disabled. Please enable them.',
            ),
          ),
        );
      }
      return;
    }

    setState(() {
      _isWalking = true;
      _routePoints.clear();
      _totalDistanceMeters = 0.0;
      _walkStartTime = DateTime.now();
      _duration = Duration.zero;
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _duration = DateTime.now().difference(_walkStartTime!);
        });
      }
    });

    if (!await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.startService(
        serviceId: 500,
        notificationTitle: 'BarkyDogMap',
        notificationText: 'Tracking your walk...',
        callback: startCallback,
      );
      FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
    }
  }

  Future<void> _addPin(String type) async {
    LatLng center;

    if (_currentPosition != null) {
      center = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    } else if (_mapController != null) {
      LatLngBounds bounds = await _mapController!.getVisibleRegion();
      center = LatLng(
        (bounds.northeast.latitude + bounds.southwest.latitude) / 2,
        (bounds.northeast.longitude + bounds.southwest.longitude) / 2,
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location not available to mark pin.')),
        );
      }
      return;
    }

    if (!mounted) return;

    String title = '';
    String description = '';
    String? imagePath;

    final Map<String, dynamic>? details =
        await showModalBottomSheet<Map<String, dynamic>>(
          context: context,
          isScrollControlled: true,
          builder: (BuildContext context) {
            return StatefulBuilder(
              builder: (BuildContext context, StateSetter setModalState) {
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                    left: 16,
                    right: 16,
                    top: 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Pin Details',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextField(
                        autofocus: true,
                        maxLength: 50,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Title (Optional)',
                        ),
                        onChanged: (val) => title = val,
                      ),
                      TextField(
                        maxLength: 200,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Description (Optional)',
                        ),
                        onChanged: (val) => description = val,
                      ),
                      const SizedBox(height: 16),
                      if (imagePath != null) ...[
                        Image.file(
                          File(imagePath!),
                          height: 100,
                          width: 100,
                          fit: BoxFit.cover,
                        ),
                        const SizedBox(height: 8),
                      ] else ...[
                        IconButton(
                          icon: const Icon(
                            Icons.camera_alt,
                            size: 40,
                            color: Colors.blue,
                          ),
                          onPressed: () async {
                            final ImagePicker picker = ImagePicker();
                            final XFile? image = await picker.pickImage(
                              source: ImageSource.camera,
                            );
                            if (image != null) {
                              setModalState(() => imagePath = image.path);
                            }
                          },
                        ),
                        const Text(
                          'Snap Photo',
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                      ],
                      ElevatedButton(
                        onPressed: () {
                          if (!context.mounted) return;
                          Navigator.pop(context, {
                            'title': title,
                            'description': description,
                            'imagePath': imagePath,
                          });
                        },
                        child: const Text('Save Pin'),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                );
              },
            );
          },
        );

    if (details == null) return; // dismissed without saving
    if (!mounted) return;

    final id = DateTime.now().millisecondsSinceEpoch.toString();

    String finalImagePath = '';
    if (details.containsKey('imagePath') && details['imagePath'] != null) {
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
        final savedImage = await File(
          details['imagePath'],
        ).copy('${appDir.path}/$fileName');
        finalImagePath = savedImage.path;
      } catch (e) {
        debugPrint('Failed to save image: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save image: $e')),
          );
        }
      }
    }

    final pin = MapPin(
      id: id,
      type: type,
      title: details['title'] ?? '',
      description: details['description'] ?? '',
      imagePath: finalImagePath,
      latitude: center.latitude,
      longitude: center.longitude,
      timestamp: DateTime.now(),
    );

    if (mounted) {
      context.read<PinProvider>().addPin(pin);
    }
  }

  String get _formattedDistance {
    final miles = _totalDistanceMeters * 0.000621371;
    return '${miles.toStringAsFixed(2)} mi';
  }

  String get _formattedDuration {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(_duration.inMinutes.remainder(60));
    final seconds = twoDigits(_duration.inSeconds.remainder(60));
    if (_duration.inHours > 0) {
      return '${_duration.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final pins = context.watch<PinProvider>().pins;
    final Set<Marker> markers = pins.map((p) => Marker(
      markerId: MarkerId(p.id ?? ''),
      position: LatLng(p.latitude, p.longitude),
      onTap: () => _showPinDetailsModal(p),
      icon: BitmapDescriptor.defaultMarkerWithHue(
        p.type == 'poi' ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
      ),
    )).toSet();

    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: _initialPosition,
            markers: markers,
            polylines: {
              if (_isWalking && _routePoints.isNotEmpty)
                Polyline(
                  polylineId: const PolylineId('route'),
                  points: _routePoints,
                  color: Colors.blue,
                  width: 5,
                ),
            },
            onMapCreated: (controller) {
              _mapController = controller;
            },
            myLocationEnabled: _isWalking,
            myLocationButtonEnabled: false,
          ),
          if (_isWalking)
            Positioned(
              top: 60,
              left: 16,
              right: 16,
              child: Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 12.0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          const Text(
                            'Time',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                          Text(
                            _formattedDuration,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          const Text(
                            'Distance',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                          Text(
                            _formattedDistance,
                            style: const TextStyle(
                              fontSize: 20,
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FloatingActionButton.extended(
                  onPressed: _toggleWalk,
                  label: Text(_isWalking ? 'Stop Walk' : 'Start Walk'),
                  icon: Icon(_isWalking ? Icons.stop : Icons.directions_walk),
                  backgroundColor: _isWalking ? Colors.orange : null,
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 32,
            right: 16,
            child: SpeedDial(
              icon: Icons.add,
              overlayColor: Colors.black,
              overlayOpacity: 0.4,
              children: [
                SpeedDialChild(
                  child: const Icon(Icons.pets, color: Colors.white),
                  backgroundColor: Colors.red,
                  label: 'Bark Hazard',
                  onTap: () => _addPin('hazard'),
                ),
                SpeedDialChild(
                  child: const Icon(Icons.star, color: Colors.white),
                  backgroundColor: Colors.green,
                  label: 'Pup POI',
                  onTap: () => _addPin('poi'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../models/map_pin.dart';
import '../services/database.dart';
import '../services/pin_provider.dart';

import 'package:google_maps_flutter/google_maps_flutter.dart';

class HistoryScreen extends StatefulWidget {
  final Function(LatLng)? onPinSelected;

  const HistoryScreen({super.key, this.onPinSelected});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

void _createZipArchive(Map<String, String> payload) {
  try {
    final dbPath = payload['dbPath']!;
    final appDirPath = payload['appDirPath']!;
    final zipFilePath = payload['zipFilePath']!;

    final archive = Archive();

    // Add Database
    final dbFile = File(dbPath);
    if (dbFile.existsSync()) {
      final dbBytes = dbFile.readAsBytesSync();
      archive.addFile(ArchiveFile('bark_hazards.db', dbBytes.length, dbBytes));
    }

    // Add Images
    final appDir = Directory(appDirPath);
    if (appDir.existsSync()) {
      final files = appDir.listSync();
      for (var file in files) {
        if (file is File && file.path.endsWith('.jpg')) {
          final filename = p.basename(file.path);
          final bytes = file.readAsBytesSync();
          archive.addFile(ArchiveFile('images/$filename', bytes.length, bytes));
        }
      }
    }

    final zipEncoder = ZipEncoder();
    final encodedZip = zipEncoder.encode(archive);
    if (encodedZip != null) {
      File(zipFilePath).writeAsBytesSync(encodedZip);
    } else {
      throw Exception('Zip encoding failed.');
    }
  } catch (e) {
    debugPrint('Error creating ZIP archive: $e');
    throw Exception('Error creating ZIP archive: $e');
  }
}

void _extractZipArchive(Map<String, String> payload) {
  try {
    final zipFilePath = payload['zipFilePath']!;
    final dbPath = payload['dbPath']!;
    final appDirPath = payload['appDirPath']!;

    final appDir = Directory(appDirPath);
    if (appDir.existsSync()) {
      final files = appDir.listSync();
      for (var file in files) {
        if (file is File && file.path.endsWith('.jpg')) {
          file.deleteSync();
        }
      }
    }

    final dbFile = File(dbPath);
    if (dbFile.existsSync()) {
      dbFile.deleteSync();
    }

    final bytes = File(zipFilePath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      if (file.isFile) {
        final name = file.name;
        final fileBytes = file.content as List<int>;

        if (name == 'bark_hazards.db') {
          File(dbPath).writeAsBytesSync(fileBytes);
        } else if (name.startsWith('images/')) {
          final filename = p.basename(name);
          final outPath = p.join(appDirPath, filename);
          File(outPath).writeAsBytesSync(fileBytes);
        }
      }
    }
  } catch (e) {
    debugPrint('Error extracting ZIP archive: $e');
    throw Exception('Error extracting ZIP archive: $e');
  }
}

class _HistoryScreenState extends State<HistoryScreen> {

  Future<void> _deletePin(String id) async {
    if (mounted) {
      context.read<PinProvider>().deletePin(id);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pin deleted')));
    }
  }

  Future<void> _exportData() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Dialog(
          child: Padding(
            padding: EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text('Generating Backup...'),
              ],
            ),
          ),
        );
      },
    );

    try {
      final dbPath = await getDatabasesPath();
      final databasePath = p.join(dbPath, 'bark_hazards.db');
      final appDir = await getApplicationDocumentsDirectory();
      final tempDir = await getTemporaryDirectory();

      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '')
          .replaceAll('-', '')
          .split('.')[0];
      final zipFileName = 'barkydogmap_backup_$timestamp.zip';
      final zipFilePath = p.join(tempDir.path, zipFileName);

      final exportPayload = {
        'dbPath': databasePath,
        'appDirPath': appDir.path,
        'zipFilePath': zipFilePath,
      };

      await compute(_createZipArchive, exportPayload);

      if (mounted) Navigator.pop(context); // Close dialog

      if (!File(zipFilePath).existsSync()) {
        throw Exception('Failed to generate archive.');
      }

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(zipFilePath)],
          subject: 'BarkyDogMap Backup',
        ),
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error creating backup: $e')));
      }
    }
  }

  Future<void> _importData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Backup'),
        content: const Text(
          'Importing a backup will completely overwrite your current map pins and photos. Are you sure you want to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Proceed', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result == null || result.files.single.path == null) return;
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const Dialog(
          child: Padding(
            padding: EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text('Restoring Backup...'),
              ],
            ),
          ),
        );
      },
    );

    try {
      await DatabaseService.instance.close();

      final zipFilePath = result.files.single.path!;
      final dbPath = await getDatabasesPath();
      final databasePath = p.join(dbPath, 'bark_hazards.db');
      final appDir = await getApplicationDocumentsDirectory();

      final payload = {
        'zipFilePath': zipFilePath,
        'dbPath': databasePath,
        'appDirPath': appDir.path,
      };

      await compute(_extractZipArchive, payload);

      if (mounted) Navigator.pop(context);

      if (mounted) {
        context.read<PinProvider>().loadPins();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup restored successfully!')),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to restore backup: $e')));
      }
      if (mounted) {
        context.read<PinProvider>().loadPins();
      }
    }
  }

  Future<void> _editPin(MapPin pin) async {
    String title = pin.title;
    String description = pin.description;
    String? imagePath = pin.imagePath.isNotEmpty ? pin.imagePath : null;

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
                        'Edit Pin Details',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      TextField(
                        autofocus: true,
                        maxLength: 50,
                        controller: TextEditingController(text: title),
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Title (Optional)',
                        ),
                        onChanged: (val) => title = val,
                      ),
                      TextField(
                        maxLength: 200,
                        maxLines: 3,
                        controller: TextEditingController(text: description),
                        decoration: const InputDecoration(
                          labelText: 'Description (Optional)',
                        ),
                        onChanged: (val) => description = val,
                      ),
                      const SizedBox(height: 16),
                      if (imagePath != null) ...[
                        Stack(
                          alignment: Alignment.topRight,
                          children: [
                            Image.file(
                              File(imagePath!),
                              height: 100,
                              width: 100,
                              fit: BoxFit.cover,
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () =>
                                  setModalState(() => imagePath = null),
                            ),
                          ],
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
                          Navigator.pop(context, {
                            'title': title,
                            'description': description,
                            'imagePath': imagePath,
                          });
                        },
                        child: const Text('Save Changes'),
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

    String finalImagePath = '';
    if (details.containsKey('imagePath') && details['imagePath'] != null) {
      if (details['imagePath'] == pin.imagePath) {
        finalImagePath = pin.imagePath; // Unchanged
      } else {
        final appDir = await getApplicationDocumentsDirectory();
        final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
        final savedImage = await File(
          details['imagePath'],
        ).copy('${appDir.path}/$fileName');
        finalImagePath = savedImage.path;
      }
    }

    final updatedPin = MapPin(
      id: pin.id,
      type: pin.type,
      title: details['title'] ?? '',
      description: details['description'] ?? '',
      imagePath: finalImagePath,
      latitude: pin.latitude,
      longitude: pin.longitude,
      timestamp: pin.timestamp,
    );

    if (mounted) {
      context.read<PinProvider>().updatePin(updatedPin);
    }

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pin updated successfully')));
    }
  }

  void _viewImage(String imagePath) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: Image.file(File(imagePath), fit: BoxFit.contain),
        ),
      ),
    );
  }

  Widget _buildGallery(List<MapPin> pins) {
    if (pins.isEmpty) {
      return RefreshIndicator(
        color: Theme.of(context).colorScheme.primary,
        onRefresh: () => context.read<PinProvider>().loadPins(),
        child: LayoutBuilder(
          builder: (context, constraints) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Container(
                height: constraints.maxHeight,
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('No recorded pins.'),
                    const SizedBox(height: 8),
                    Text(
                      '↓ Pull down to refresh and see recently saved pins.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      color: Theme.of(context).colorScheme.primary,
      onRefresh: () => context.read<PinProvider>().loadPins(),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(8.0),
        itemCount: pins.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Center(
                child: Text(
                  '↓ Pull down to refresh recent pins',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ),
            );
          }

          final pin = pins[index - 1];
          final isPoi = pin.type == 'poi';
          final displayTitle = pin.title.isNotEmpty
              ? pin.title
              : (isPoi ? 'Pup POI' : 'Bark Hazard');

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
            elevation: 4,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: InkWell(
              onTap: () {
                if (widget.onPinSelected != null) {
                  widget.onPinSelected!(LatLng(pin.latitude, pin.longitude));
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (pin.imagePath.isNotEmpty)
                    GestureDetector(
                      onTap: () => _viewImage(pin.imagePath),
                      child: Image.file(
                        File(pin.imagePath),
                        height: 250,
                        fit: BoxFit.cover,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isPoi ? Icons.star : Icons.pets,
                              color: isPoi ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                displayTitle,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () => _editPin(pin),
                            ),
                            const SizedBox(width: 16),
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: const Icon(
                                Icons.delete,
                                color: Colors.grey,
                              ),
                              onPressed: () => _deletePin(pin.id!),
                            ),
                          ],
                        ),
                        if (pin.description.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            pin.description,
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Text(
                          'Mapped on ${pin.timestamp.toString().split('.')[0]}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History Gallery'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export Backup',
            onPressed: _exportData,
          ),
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: 'Import Backup',
            onPressed: _importData,
          ),
        ],
      ),
      body: Consumer<PinProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return _buildGallery(provider.pins);
        },
      ),
    );
  }
}

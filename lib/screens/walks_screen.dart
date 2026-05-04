import 'package:flutter/material.dart';
import '../models/walk.dart';
import '../services/database.dart';

class WalksScreen extends StatefulWidget {
  const WalksScreen({super.key});

  @override
  State<WalksScreen> createState() => _WalksScreenState();
}

class _WalksScreenState extends State<WalksScreen> {
  List<Walk> _walks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadWalks();
  }

  Future<void> _loadWalks() async {
    setState(() => _isLoading = true);
    final walks = await DatabaseService.instance.getAllWalks();
    setState(() {
      _walks = walks;
      _isLoading = false;
    });
  }

  Future<void> _deleteWalk(String id) async {
    await DatabaseService.instance.deleteWalk(id);
    _loadWalks();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Walk deleted')),
      );
    }
  }

  String _formatDistance(double meters) {
    final miles = meters * 0.000621371;
    return '${miles.toStringAsFixed(2)} mi';
  }

  String _formatDuration(DateTime start, DateTime end) {
    final duration = end.difference(start);
    if (duration.inHours > 0) {
      final mins = duration.inMinutes.remainder(60);
      return '${duration.inHours} hr $mins min';
    } else {
      return '${duration.inMinutes} min';
    }
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day}/${date.year} at ${date.hour > 12 ? date.hour - 12 : (date.hour == 0 ? 12 : date.hour)}:${date.minute.toString().padLeft(2, '0')} ${date.hour >= 12 ? 'PM' : 'AM'}';
  }

  Widget _buildWalksList() {
    if (_walks.isEmpty) {
      return RefreshIndicator(
        color: Theme.of(context).colorScheme.primary,
        onRefresh: _loadWalks,
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
                    const Text('No walks recorded yet. Hit the trails!'),
                    const SizedBox(height: 8),
                    Text(
                      '↓ Pull down to refresh recent walks',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
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
      onRefresh: _loadWalks,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(8.0),
        itemCount: _walks.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              child: Center(
                child: Text(
                  '↓ Pull down to refresh recent walks',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
                ),
              ),
            );
          }

          final walk = _walks[index - 1];

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16.0),
              leading: const CircleAvatar(
                backgroundColor: Colors.blueAccent,
                child: Icon(Icons.directions_walk, color: Colors.white),
              ),
              title: Text(
                _formatDate(walk.startTime),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  children: [
                    const Icon(Icons.timer, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(_formatDuration(walk.startTime, walk.endTime)),
                    const SizedBox(width: 16),
                    const Icon(Icons.straighten, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(_formatDistance(walk.distanceMeters)),
                  ],
                ),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.grey),
                onPressed: () => _deleteWalk(walk.id!),
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
        title: const Text('Walk History'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildWalksList(),
    );
  }
}

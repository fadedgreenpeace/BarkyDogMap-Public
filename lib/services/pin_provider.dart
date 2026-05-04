import 'package:flutter/foundation.dart';
import '../models/map_pin.dart';
import '../services/database.dart';

class PinProvider with ChangeNotifier {
  List<MapPin> _pins = [];
  bool _isLoading = false;

  List<MapPin> get pins => _pins;
  bool get isLoading => _isLoading;

  Future<void> loadPins() async {
    _isLoading = true;
    notifyListeners();

    // To prevent heavy UI block on main isolate, this should ideally be in compute,
    // but for now we fetch it asynchronously. DatabaseService query is async.
    final fetchedPins = await DatabaseService.instance.getAllPins();
    
    _pins = fetchedPins;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> addPin(MapPin pin) async {
    await DatabaseService.instance.insertPin(pin);
    _pins.insert(0, pin); // Add to the top of the list locally
    notifyListeners();
  }

  Future<void> updatePin(MapPin pin) async {
    await DatabaseService.instance.updatePin(pin);
    final index = _pins.indexWhere((p) => p.id == pin.id);
    if (index != -1) {
      _pins[index] = pin;
      notifyListeners();
    }
  }

  Future<void> deletePin(String id) async {
    await DatabaseService.instance.deletePin(id);
    _pins.removeWhere((p) => p.id == id);
    notifyListeners();
  }
}

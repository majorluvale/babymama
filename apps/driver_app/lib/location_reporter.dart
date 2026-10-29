import 'dart:async';

import 'package:babymama_core/babymama_core.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Sends the rider's position every 30 s while online, so customers can follow their delivery.
class LocationReporter extends ChangeNotifier {
  LocationReporter(this.api);

  final ApiClient api;
  Timer? _timer;
  String? error;

  bool get running => _timer?.isActive ?? false;

  Future<bool> start() async {
    error = null;
    if (!await Geolocator.isLocationServiceEnabled()) {
      error = 'location_disabled';
      notifyListeners();
      return false;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      error = 'location_denied';
      notifyListeners();
      return false;
    }
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _report());
    _report();
    notifyListeners();
    return true;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  Future<void> _report() async {
    try {
      final pos = await Geolocator.getCurrentPosition();
      await api.post('/driver/location', {'lat': pos.latitude, 'lng': pos.longitude});
    } catch (_) {
      // Network or GPS hiccup: try again on the next tick.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

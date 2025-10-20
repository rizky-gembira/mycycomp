import 'dart:async';
import 'dart:math' show sqrt, cos, asin;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class RideScreen extends StatefulWidget {
  const RideScreen({super.key});

  @override
  State<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends State<RideScreen> {
  double _speed = 0.0; // km/h
  double _elevation = 0.0;
  double _distance = 0.0;
  Position? _lastPosition;
  DateTime? _lastMoveTime;

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  bool _movementDetected = false;
  double _motionLevel = 0.0;
  List<LatLng> _path = [];
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _initSensors();
    _initGPS();
  }

  // --- Accelerometer logic ---
  void _initSensors() {
    _accelSub = accelerometerEvents.listen((AccelerometerEvent event) {
      final magnitude =
          sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      final deviation = (magnitude - 9.8).abs();

      _motionLevel = 0.8 * _motionLevel + 0.2 * deviation;

      if (_motionLevel > 0.25) {
        if (!_movementDetected) {
          debugPrint("📱 Motion spike detected — start reading GPS");
        }
        _movementDetected = true;
        _lastMoveTime = DateTime.now();
      }
    });
  }

  // --- GPS logic ---
  void _initGPS() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint("⚠️ Location service not enabled");
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    _positionSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
      ),
    ).listen((Position position) {
      final now = DateTime.now();

      // --- check no GPS position change for 5s ---
      if (_lastPosition != null) {
        final dist = _calculateDistance(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          position.latitude,
          position.longitude,
        );

        if (dist < 0.002 && now.difference(_lastMoveTime ?? now).inSeconds > 5) {
          if (_movementDetected) debugPrint("🕒 No GPS movement for 5s → stop");
          _movementDetected = false;
          setState(() => _speed = 0.0);
          return;
        } else if (dist >= 0.002) {
          _lastMoveTime = now;
        }
      }

      if (!_movementDetected) return;

      // --- calculate filtered GPS speed ---
      final rawSpeed = position.speed * 3.6; // m/s → km/h
      double jitterDistance = 0.0;
      if (_lastPosition != null) {
        jitterDistance = _calculateDistance(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          position.latitude,
          position.longitude,
        ) * 1000; // meters
      }

      // Ignore GPS noise (movement <2m and low speed)
      if (jitterDistance < 2 && rawSpeed < 1.0) {
        debugPrint("🚫 GPS noise filtered out");
        return;
      }

      setState(() {
        _speed = rawSpeed < 0.8 ? 0.0 : rawSpeed;
        _elevation = position.altitude;

        if (_lastPosition != null) {
          _distance += _calculateDistance(
            _lastPosition!.latitude,
            _lastPosition!.longitude,
            position.latitude,
            position.longitude,
          );
        }

        _lastPosition = position;

        final latLng = LatLng(position.latitude, position.longitude);
        _path.add(latLng);
        if (_path.length > 1) {
          _mapController.move(latLng, _mapController.camera.zoom);
        }
      });

      debugPrint("📍 Speed: ${_speed.toStringAsFixed(2)} km/h | "
          "Elevation: ${_elevation.toStringAsFixed(1)} m | "
          "Distance: ${_distance.toStringAsFixed(3)} km");
    });
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // kilometers
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _accelSub?.cancel();
    super.dispose();
  }

  void _resetTrip() {
    setState(() {
      _speed = 0;
      _elevation = 0;
      _distance = 0;
      _lastPosition = null;
      _path.clear();
    });
    debugPrint("🔁 Trip reset");
  }

  // --- UI ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // --- Stats section ---
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16),
              child: Column(
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: _speed),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOut,
                    builder: (context, value, _) {
                      return Text(
                        value.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 80,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      );
                    },
                  ),
                  const Text("km/h", style: TextStyle(fontSize: 22)),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _infoCard("Elevation", _elevation, "m", Icons.terrain),
                      _infoCard("Distance", _distance, "km", Icons.route),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _resetTrip,
                    icon: const Icon(Icons.refresh),
                    label: const Text("Reset Trip"),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // --- Map section ---
            Expanded(
              child: _path.isEmpty
                  ? const Center(child: Text("Waiting for GPS..."))
                  : FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _path.last,
                        initialZoom: 17,
                        keepAlive: true,
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                          subdomains: const ['a', 'b', 'c'],
                        ),
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _path,
                              color: Colors.red,
                              strokeWidth: 4,
                            ),
                          ],
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: _path.last,
                              width: 40,
                              height: 40,
                              child: const Icon(
                                Icons.my_location,
                                color: Colors.blue,
                                size: 36,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(String title, double value, String unit, IconData icon) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text("${value.toStringAsFixed(1)} $unit"),
          ],
        ),
      ),
    );
  }
}

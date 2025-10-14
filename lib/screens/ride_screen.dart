import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'dart:async';
import 'dart:math' show sqrt, cos, asin;

class RideScreen extends StatefulWidget {
  const RideScreen({super.key});

  @override
  State<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends State<RideScreen> {
  double _speed = 0.0;       // km/h
  double _elevation = 0.0;   // meters
  double _distance = 0.0;    // kilometers
  Position? _lastPosition;

  StreamSubscription<Position>? _positionSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  bool _movementDetected = false;
  double _motionLevel = 0.0; // how much device shakes/moves

  @override
  void initState() {
    super.initState();
    _initSensors();
    _initGPS();
  }

  void _initSensors() {
    _accelSub = accelerometerEvents.listen((AccelerometerEvent event) {
      final magnitude = sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
      final deviation = (magnitude - 9.8).abs();

      // Low-pass filter to smooth accelerometer noise
      _motionLevel = 0.8 * _motionLevel + 0.2 * deviation;

      // If significant movement, consider user moving
      if (_motionLevel > 0.25) {
        _movementDetected = true;
      } else {
        // Immediately mark stopped when below motion threshold
        if (_movementDetected) {
          _movementDetected = false;
          setState(() => _speed = 0.0); // Immediately drop to zero
        }
      }
    });
  }

  void _initGPS() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

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
      if (!_movementDetected) {
        setState(() => _speed = 0.0);
        return;
      }

      setState(() {
        final speed = position.speed * 3.6; // m/s → km/h
        _speed = speed < 0.5 ? 0.0 : speed;
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
      });
    });
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295; // pi / 180
    final a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) *
            (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // 2 * R * asin...
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _accelSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Smooth animated speed
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: _speed),
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Text(
                    value.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 100,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  );
                },
              ),
              const Text("km/h", style: TextStyle(fontSize: 24)),
              const SizedBox(height: 40),

              // Info cards
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _animatedInfoCard("Elevation", _elevation, "m", Icons.terrain),
                  _animatedInfoCard("Distance", _distance, "km", Icons.route),
                ],
              ),
              const SizedBox(height: 40),

              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _speed = 0;
                    _elevation = 0;
                    _distance = 0;
                    _lastPosition = null;
                  });
                },
                icon: const Icon(Icons.refresh),
                label: const Text("Reset Trip"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _animatedInfoCard(String title, double value, String unit, IconData icon) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 6),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: value),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOut,
              builder: (context, val, child) => Text(
                "${val.toStringAsFixed(value < 10 ? 2 : 1)} $unit",
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

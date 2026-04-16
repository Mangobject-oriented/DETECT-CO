import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  final mapController = MapController();
  LatLng? currentPosition;

  // Calamba bounding box
  final LatLng swCorner = LatLng(14.13466576727542, 121.00698800147504);
  final LatLng neCorner = LatLng(14.242176187772285, 121.20972008423361);

  late final LatLng calambaCenter = LatLng(
      (swCorner.latitude + neCorner.latitude) / 2,
      (swCorner.longitude + neCorner.longitude) / 2);

  late final LatLngBounds calambaBounds = LatLngBounds(swCorner, neCorner);

  final LatLng evacSite = LatLng(14.23707209551028, 121.17340069445697);

  /// -------------------------------
  /// LOCATION HANDLING
  /// -------------------------------
  Future<void> _locateMe() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showLocationDialog(
          'Location Services Disabled',
          'Please turn on location services to use this feature.',
          openSettings: true);
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showLocationDialog(
            'Permission Denied',
            'Location permission is required to show your current position.');
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showLocationDialog(
          'Permission Permanently Denied',
          'Please enable location permission from app settings to continue.',
          openSettings: true);
      return;
    }

    try {
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final latLng = LatLng(pos.latitude, pos.longitude);

      // Clamp to Calamba bounds
      double lat = latLng.latitude.clamp(swCorner.latitude, neCorner.latitude);
      double lng = latLng.longitude.clamp(swCorner.longitude, neCorner.longitude);

      setState(() {
        currentPosition = LatLng(lat, lng);
      });

      // Move AND zoom in to user location (zoom level 16)
      mapController.move(LatLng(lat, lng), 16.0);
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showLocationDialog(String title, String message,
      {bool openSettings = false}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          if (openSettings)
            TextButton(
              onPressed: () {
                Geolocator.openAppSettings();
                Navigator.pop(context);
              },
              child: const Text('Open Settings'),
            ),
        ],
      ),
    );
  }

  void _locateEvac() {
    if (currentPosition != null) {
      // Move AND zoom to evacuation site (zoom level 16)
      mapController.move(evacSite, 16.0);
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Locate your position first')));
    }
  }

  /// -------------------------------
  /// UI BUILD
  /// -------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Flood Monitoring Map',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
        ),
        centerTitle: true,
        backgroundColor: const Color.fromARGB(255, 255, 255, 255),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              center: calambaCenter,
              zoom: 13.5,
              minZoom: 12.0,
              maxZoom: 18.0,
              interactiveFlags: InteractiveFlag.all,
              bounds: calambaBounds,
              boundsOptions: const FitBoundsOptions(padding: EdgeInsets.all(12.0)),
              onPositionChanged: (pos, _) {
                final center = pos.center;
                if (center == null) return;

                double lat = center.latitude.clamp(swCorner.latitude, neCorner.latitude);
                double lng = center.longitude.clamp(swCorner.longitude, neCorner.longitude);

                if (lat != center.latitude || lng != center.longitude) {
                  mapController.move(LatLng(lat, lng), pos.zoom ?? 13.5);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.detectco',
              ),
              PolygonLayer(
                polygons: [
                  // Black border
                  Polygon(
                    points: [
                      swCorner,
                      LatLng(swCorner.latitude, neCorner.longitude),
                      neCorner,
                      LatLng(neCorner.latitude, swCorner.longitude),
                      swCorner,
                    ],
                    color: Colors.transparent,
                    borderColor: Colors.black,
                    borderStrokeWidth: 3,
                  ),
                  // Dim outside (4 polygons)
                  Polygon(
                    points: [LatLng(neCorner.latitude, -180), LatLng(90, -180), LatLng(90, 180), LatLng(neCorner.latitude, 180)],
                    color: Colors.black.withOpacity(0.4),
                  ),
                  Polygon(
                    points: [LatLng(-90, -180), LatLng(swCorner.latitude, -180), LatLng(swCorner.latitude, 180), LatLng(-90, 180)],
                    color: Colors.black.withOpacity(0.4),
                  ),
                  Polygon(
                    points: [LatLng(swCorner.latitude, -180), LatLng(neCorner.latitude, -180), LatLng(neCorner.latitude, swCorner.longitude), LatLng(swCorner.latitude, swCorner.longitude)],
                    color: Colors.black.withOpacity(0.4),
                  ),
                  Polygon(
                    points: [LatLng(swCorner.latitude, neCorner.longitude), LatLng(neCorner.latitude, neCorner.longitude), LatLng(neCorner.latitude, 180), LatLng(swCorner.latitude, 180)],
                    color: Colors.black.withOpacity(0.4),
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  if (currentPosition != null)
                    Marker(
                      point: currentPosition!,
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.my_location, color: Colors.blue, size: 36),
                    ),
                  Marker(
                    point: evacSite,
                    width: 40,
                    height: 40,
                    child: const Icon(Icons.local_hospital, color: Colors.red, size: 36),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 16,
            right: 16,
            child: Column(
              children: [
                FloatingActionButton(
                  mini: true,
                  onPressed: _locateMe,
                  heroTag: 'locateMe',
                  backgroundColor: const Color(0xFF0353A4),
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(height: 8),
                FloatingActionButton(
                  mini: true,
                  onPressed: _locateEvac,
                  heroTag: 'locateEvac',
                  backgroundColor: Colors.redAccent,
                  child: const Icon(Icons.local_hospital),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
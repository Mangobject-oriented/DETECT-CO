import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class MapTab extends StatefulWidget {
  const MapTab({super.key});

  @override
  State<MapTab> createState() => _MapTabState();
}

class EvacSite {
  final String name;
  final String description;
  final String image;
  final LatLng location;

  EvacSite({
    required this.name,
    required this.description,
    required this.image,
    required this.location,
  });
}

class _MapTabState extends State<MapTab> {
  final mapController = MapController();
  LatLng? currentPosition;

  List<LatLng> routePoints = [];
  EvacSite? selectedSite;

  final LatLng swCorner = LatLng(14.13466576727542, 121.00698800147504);
  final LatLng neCorner = LatLng(14.242176187772285, 121.20972008423361);

  late final LatLng calambaCenter = LatLng(
    (swCorner.latitude + neCorner.latitude) / 2,
    (swCorner.longitude + neCorner.longitude) / 2,
  );

  final List<EvacSite> evacSites = [
    EvacSite(
      name: "Uwisan Brgy Hall Evacuation Site",
      description: "65PF+RC8, Looc Road, Calamba",
      image: "assets/images/evac1.png",
      location: LatLng(14.23707209551028, 121.17340069445697),
    ),
    EvacSite(
      name: "Lingga Elementary School",
      description: "Calamba Laguna",
      image: "assets/images/evac2.png",
      location: LatLng(14.215765305050551, 121.18228271136698),
    ),
    EvacSite(
      name: "Palingon Elementary School",
      description: "Real, Calamba",
      image: "assets/images/evac3.png",
      location: LatLng(14.215617735789499, 121.1861596967596),
    ),
  ];

  bool followMe = false;
  StreamSubscription<Position>? _positionStream;

  Future<void> getRoute(LatLng start, LatLng end) async {
    final url =
        'https://router.project-osrm.org/route/v1/driving/'
        '${start.longitude},${start.latitude};'
        '${end.longitude},${end.latitude}'
        '?overview=full&geometries=geojson';

    final response = await http.get(Uri.parse(url));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      final coords = data['routes'][0]['geometry']['coordinates'];

      setState(() {
        routePoints = coords.map<LatLng>((c) => LatLng(c[1], c[0])).toList();
      });
    }
  }

  void _goToNearestEvac() {
    if (currentPosition == null) return;

    final Distance d = Distance();

    EvacSite nearest = evacSites[0];
    double minDist = double.infinity;

    for (final site in evacSites) {
      final dist = d.as(LengthUnit.Meter, currentPosition!, site.location);

      if (dist < minDist) {
        minDist = dist;
        nearest = site;
      }
    }

    setState(() {
      selectedSite = nearest;
    });

    mapController.move(nearest.location, 16);
    getRoute(currentPosition!, nearest.location);

    _showEvacPanel(nearest);
  }

  /// =========================================================
  /// SIDE PANEL (UNCHANGED UI, 40% HEIGHT)
  /// =========================================================
  void _showEvacPanel(EvacSite site) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.40,
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
                child: Image.asset(
                  site.image,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        site.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(site.description),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (currentPosition != null) {
                              getRoute(currentPosition!, site.location);
                            }
                            mapController.move(site.location, 16);
                            Navigator.pop(context);
                          },
                          icon: const Icon(Icons.directions),
                          label: const Text("Go to Location"),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _locateMe() async {
    final pos = await Geolocator.getCurrentPosition();

    final clamped = LatLng(pos.latitude, pos.longitude);

    setState(() {
      currentPosition = clamped;
      followMe = true;
    });

    mapController.move(clamped, 16);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Flood Map")),
      body: Stack(
        children: [
          FlutterMap(
            mapController: mapController,
            options: MapOptions(
              center: calambaCenter,
              zoom: 13.5,

              // 🔒 THIS IS THE IMPORTANT FIX (HARD BOUNDARY LOCK)
              cameraConstraint: CameraConstraint.contain(
                bounds: LatLngBounds(
                  swCorner,
                  neCorner,
                ),
              ),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://cartodb-basemaps-a.global.ssl.fastly.net/light_all/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
              ),

              PolylineLayer(
                polylines: [
                  Polyline(points: routePoints, strokeWidth: 4),
                ],
              ),

              MarkerLayer(
                markers: [
                  if (currentPosition != null)
                    Marker(
                      point: currentPosition!,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.my_location,
                        color: Colors.blue,
                      ),
                    ),

                  for (final site in evacSites)
                    Marker(
                      point: site.location,
                      width: 45,
                      height: 45,
                      child: GestureDetector(
                        onTap: () => _showEvacPanel(site),
                        child: Image.asset('assets/icon/evacsite.png'),
                      ),
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
                  heroTag: 'gps',
                  mini: true,
                  onPressed: _locateMe,
                  child: const Icon(Icons.my_location),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  heroTag: 'nearest',
                  mini: true,
                  backgroundColor: Colors.green,
                  onPressed: _goToNearestEvac,
                  child: const Icon(Icons.place),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
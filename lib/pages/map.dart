import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapTab extends StatelessWidget {
  const MapTab({super.key});

  @override
  Widget build(BuildContext context) {


    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Flood Monitoring Map',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0353A4),
      ),


      body: FlutterMap(
        options: const MapOptions(
          initialCenter: LatLng(14.212476601491387, 121.18696199978602),
          initialZoom: 18.0,
          minZoom: 14.0,
          maxZoom: 18.0,
          
          
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.detectco',
          ),
        ],
      ),
    );
  }
}
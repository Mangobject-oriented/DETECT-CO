import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final dbRef = FirebaseDatabase.instance.ref();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'DETECT:CO',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF0353A4),
        leading: Container(
          decoration: const BoxDecoration(color: Colors.white),
          child: Image.asset("assets/icon/placeholder.webp"),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: StreamBuilder<DatabaseEvent>(
          stream: dbRef.child('flood').onValue,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                  child: Text('Error loading data',
                      style: TextStyle(fontSize: 16, color: Colors.red)));
            }

            if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
              return const Center(child: CircularProgressIndicator());
            }

            final rawData = snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
            final data = rawData.map((key, value) => MapEntry(key.toString(), value));

            // ⚡ Use 'distance' as water level
            final dynamic distanceRaw = data['distance'];
            final double waterLevel = distanceRaw is num
                ? distanceRaw.toDouble()
                : double.tryParse(distanceRaw.toString()) ?? 0;

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SensorCard(
                    title: 'Temperature',
                    value: data['temperature']?.toString() ?? '--',
                    unit: '°C',
                  ),
                  const SizedBox(height: 12),
                  SensorCard(
                    title: 'Water Level',
                    value: waterLevel.toString(),
                    unit: 'cm',
                    waterLevel: waterLevel,
                  ),
                  const SizedBox(height: 12),
                  SensorCard(
                    title: 'Humidity',
                    value: data['humidity']?.toString() ?? '--',
                    unit: '%',
                  ),
                  const SizedBox(height: 12),
                  WarningCard(
                    waterLevel: waterLevel,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Sensor Card
class SensorCard extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final double? waterLevel;

  const SensorCard({
    super.key,
    required this.title,
    required this.value,
    this.unit = '',
    this.waterLevel,
  });

  Color _getCardColor() {
    final level = waterLevel ?? 0;
    if (level > 30) return Colors.green.shade100;
    if (level > 20) return Colors.orange.shade100;
    return Colors.red.shade100;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _getCardColor(),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text(
            '$value $unit',
            style: const TextStyle(
                fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black),
          ),
        ],
      ),
    );
  }
}

/// Warning Card (dynamic)
class WarningCard extends StatelessWidget {
  final double waterLevel;

  const WarningCard({super.key, required this.waterLevel});

  String get statusText {
    if (waterLevel > 30) return 'No Flood / Safe';
    if (waterLevel > 21) return 'Medium Flood Risk';
    return 'Flood is Happening!';
  }

  Color get statusColor {
    if (waterLevel > 30) return Colors.green;
    if (waterLevel > 20) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: statusColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.5),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Flood Risk Status',
              style: TextStyle(fontSize: 16, color: Colors.black)),
          const SizedBox(height: 8),
          Text(
            '${statusText} (${waterLevel.toStringAsFixed(1)}cm)',
            style: const TextStyle(
                fontSize: 28, fontWeight: FontWeight.bold, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
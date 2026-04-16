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
          'DETECT-CO',
          style: TextStyle(fontWeight: FontWeight.bold, color: Color.fromARGB(255, 0, 0, 0)),
        ),
        centerTitle: true,
        backgroundColor: const Color.fromARGB(255, 255, 255, 255),
        leading: Container(
          decoration: const BoxDecoration(color: Colors.white),
          child: Image.asset("assets/icon/logo.png"),
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

            final dynamic distanceRaw = data['distance'];
            final double waterLevel = distanceRaw is num
                ? distanceRaw.toDouble()
                : double.tryParse(distanceRaw.toString()) ?? 0;

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row of 2 cards (Temperature and Humidity)
                  Row(
                    children: [
                      Expanded(
                        child: SensorCard(
                          title: 'Temperature',
                          value: data['temperature']?.toString() ?? '--',
                          unit: '°C',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SensorCard(
                          title: 'Humidity',
                          value: data['humidity']?.toString() ?? '--',
                          unit: '%',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Water Level card 
                  SensorCard(
                    title: 'Water Level',
                    value: waterLevel.toString(),
                    unit: 'cm',
                    waterLevel: waterLevel,
                  ),
                  const SizedBox(height: 12),
                  // Warning card
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

///Sensor Card (Box style)
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
    if (waterLevel == null) return Colors.white;
    final level = waterLevel ?? 0;
    if (level > 30) return Colors.green.shade100;
    if (level > 20) return Colors.orange.shade100;
    return Colors.red.shade100;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8), // Smaller padding
      decoration: BoxDecoration(
        color: _getCardColor(),
        borderRadius: BorderRadius.circular(12), // Rounded corners like boxes
        border: Border.all(color: Colors.grey.shade300, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center, // Centered content
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12, 
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24, 
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                unit,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Warning Card 
class WarningCard extends StatelessWidget {
  final double waterLevel;

  const WarningCard({super.key, required this.waterLevel});

  String get statusText {
    if (waterLevel > 30) return 'Safe';
    if (waterLevel > 20) return 'Medium Risk';
    return 'Flooding!';
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
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: statusColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Flood Risk Status label
          const Text(
            'Flood Risk Status',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white70,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          
          Text(
            statusText,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
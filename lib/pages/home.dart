import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key});

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  bool isDarkMode = false;

  @override
  void initState() {
    super.initState();
    loadTheme();
  }

  void loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isDarkMode = prefs.getBool('darkMode') ?? false;
    });
  }

  void toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      isDarkMode = !isDarkMode;
    });
    prefs.setBool('darkMode', isDarkMode);
  }

  @override
  Widget build(BuildContext context) {
    final dbRef = FirebaseDatabase.instance.ref();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      color: isDarkMode ? const Color(0xFF212121) : Colors.white,
      child: Scaffold(
        backgroundColor:
            isDarkMode ? const Color(0xFF212121) : Colors.white,

        appBar: AppBar(
          title: Text(
            'DETECT-CO',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.black,
            ),
          ),
          centerTitle: true,
          backgroundColor:
              isDarkMode ? const Color(0xFF1A1A1A) : Colors.white,

          leading: GestureDetector(
            onDoubleTap: toggleTheme,
            child: Container(
              color: isDarkMode
                  ? const Color(0xFF1A1A1A)
                  : Colors.white,
              child: Image.asset("assets/icon/logo.png"),
            ),
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
                      style: TextStyle(fontSize: 16, color: Colors.red)),
                );
              }

              if (!snapshot.hasData ||
                  snapshot.data!.snapshot.value == null) {
                return const Center(child: CircularProgressIndicator());
              }

              final rawData =
                  snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
              final data = rawData
                  .map((key, value) => MapEntry(key.toString(), value));

              final dynamic distanceRaw = data['distance'];
              final double waterLevel = distanceRaw is num
                  ? distanceRaw.toDouble()
                  : double.tryParse(distanceRaw.toString()) ?? 0;

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: SensorCard(
                            title: 'Temperature',
                            value:
                                data['temperature']?.toString() ?? '--',
                            unit: '°C',
                            isDark: isDarkMode,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SensorCard(
                            title: 'Humidity',
                            value:
                                data['humidity']?.toString() ?? '--',
                            unit: '%',
                            isDark: isDarkMode,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    SensorCard(
                      title: 'Water Level',
                      value: waterLevel.toString(),
                      unit: 'cm',
                      waterLevel: waterLevel,
                      isDark: isDarkMode,
                    ),

                    const SizedBox(height: 12),

                    WarningCard(
                      waterLevel: waterLevel,
                      isDark: isDarkMode,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}



class SensorCard extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final double? waterLevel;
  final bool isDark;

  const SensorCard({
    super.key,
    required this.title,
    required this.value,
    this.unit = '',
    this.waterLevel,
    required this.isDark,
  });

  Color _getCardColor() {
    if (waterLevel == null) {
      return isDark ? const Color(0xFF2C2C2C) : Colors.white;
    }

    final level = waterLevel!;
    if (level > 30) return Colors.green.shade700;
    if (level > 20) return Colors.orange.shade700;
    return Colors.red.shade700;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),

      decoration: BoxDecoration(
        color: _getCardColor(),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.grey[300] : Colors.grey,
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
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                unit,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[300] : Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}



class WarningCard extends StatelessWidget {
  final double waterLevel;
  final bool isDark;

  const WarningCard({
    super.key,
    required this.waterLevel,
    required this.isDark,
  });

  String get statusText {
    if (waterLevel > 30) return 'Safe';
    if (waterLevel > 20) return 'Medium Risk';
    return 'Flooding!';
  }

  Color get statusColor {
    if (waterLevel > 30) return const Color.fromRGBO(76, 175, 80, 1);
    if (waterLevel > 20) return Colors.orange;
    return const Color.fromRGBO(244, 67, 54, 1);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),

      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2C) : statusColor,
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
          const Text(
            'Flood Risk Status',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            statusText,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

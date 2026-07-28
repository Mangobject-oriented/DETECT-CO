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
        backgroundColor: isDarkMode ? const Color(0xFF212121) : Colors.white,

        endDrawer: Drawer(
          backgroundColor:
              isDarkMode ? const Color(0xFF1A1A1A) : Colors.white,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(
                  color: isDarkMode
                      ? const Color(0xFF1A1A1A)
                      : Colors.blue,
                ),
                child: const Text(
                  'Menu',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),

      //AppBar with a title and a theme toggle button

        body: StreamBuilder<DatabaseEvent>(
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

              final double screenHeight = MediaQuery.of(context).size.height;
              final double topHeight = screenHeight * 0.40;

              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: topHeight,
                      width: double.infinity,
                      alignment: Alignment.topCenter,
                      color: isDarkMode
                          ? const Color(0xFF212121)
                          : const Color.fromARGB(255, 72, 119, 247),
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  GestureDetector(
                                    onDoubleTap: toggleTheme,
                                    child: SizedBox(
                                      width: 50,
                                      height: 50,
                                      child: Image.asset("assets/icon/logo.png"),
                                    ),
                                  ),
                                  const Text(
                                    'DETECT-CO',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    icon: const Icon(Icons.notifications_none_rounded,
                                        color: Colors.white, size: 26),
                                    onPressed: () {},
                                  ),
                                  Builder(
                                    builder: (context) => IconButton(
                                      icon: const Icon(Icons.menu_rounded,
                                          color: Colors.white, size: 26),
                                      onPressed: () {
                                        Scaffold.of(context).openEndDrawer();
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Hello, Mike!',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.location_on, color: Colors.white70, size: 16),
                                  const SizedBox(width: 4),
                                  const Text('Barangay Biringan',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.white70,
                                      )),
                                  const Spacer(),
                                  const Text('Time Check haydol',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.white70,
                                      )),
                                ],
                              )
                            ],
                          ),
                        ),
                      ),
                    ),
                    Transform.translate(
                      offset: const Offset(0, -50),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: isDarkMode
                                ? const Color(0xFF2C2C2C)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(isDarkMode ? 0.25 : 0.08),
                                blurRadius: 6,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Current Temperature:',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                              color: isDarkMode ? Colors.white : Colors.black,
                                            )),
                                        const SizedBox(height: 4),
                                        Text('${data['temperature']?.toString() ?? '--'}°C',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: isDarkMode ? Colors.white : Colors.black,
                                            )),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text('Humidity:',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                              color: isDarkMode ? Colors.white : Colors.black,
                                            )),
                                        const SizedBox(height: 4),
                                        Text('${data['humidity']?.toString() ?? '--'}%',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: isDarkMode ? Colors.white : Colors.black,
                                            )),
                                        
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
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
    if (level > 40) return Colors.green.shade700;
    if (level > 30) return Colors.orange.shade700;
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
    if (waterLevel > 40) return 'Safe';
    if (waterLevel > 30) return 'Medium Risk';
    return 'Flooding!';
  }

  Color get statusColor {
    if (waterLevel > 40) return const Color.fromRGBO(76, 175, 80, 1);
    if (waterLevel > 30) return Colors.orange;
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
import 'dart:math' as math;

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

  // =====================================================
  // LOAD THEME
  // =====================================================

  void loadTheme() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      isDarkMode = prefs.getBool('darkMode') ?? false;
    });
  }

  // =====================================================
  // TOGGLE THEME
  // =====================================================

  void toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();

    setState(() {
      isDarkMode = !isDarkMode;
    });

    await prefs.setBool('darkMode', isDarkMode);
  }

  // =====================================================
  // FLOATING BURGER MENU
  // =====================================================

  void _showMenu(BuildContext menuContext) {
    final RenderBox button =
        menuContext.findRenderObject() as RenderBox;

    final RenderBox overlay =
        Overlay.of(menuContext)
            .context
            .findRenderObject() as RenderBox;

    final Offset position = button.localToGlobal(
      Offset.zero,
      ancestor: overlay,
    );

    showMenu<String>(
      context: menuContext,

      // Position menu underneath burger button
      position: RelativeRect.fromLTRB(
        position.dx - 155,
        position.dy + 48,
        overlay.size.width -
            position.dx -
            button.size.width,
        0,
      ),

      color: isDarkMode
          ? const Color(0xFF303030)
          : Colors.white,

      elevation: 8,

      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),

      items: [
        // =================================================
        // HOW TO USE
        // =================================================

        PopupMenuItem<String>(
          value: 'how_to_use',
          height: 52,
          child: Row(
            children: [
              Icon(
                Icons.help,
                color: isDarkMode
                    ? Colors.white
                    : const Color(0xFF1D2B4A),
                size: 22,
              ),
              const SizedBox(width: 12),
              Text(
                'How to Use',
                style: TextStyle(
                  color: isDarkMode
                      ? Colors.white
                      : const Color(0xFF1D2B4A),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),

        // =================================================
        // TERMS OF SERVICE
        // =================================================

        PopupMenuItem<String>(
          value: 'terms',
          height: 52,
          child: Row(
            children: [
              Icon(
                Icons.description,
                color: isDarkMode
                    ? Colors.white
                    : const Color(0xFF1D2B4A),
                size: 22,
              ),
              const SizedBox(width: 12),
              Text(
                'Terms of Service',
                style: TextStyle(
                  color: isDarkMode
                      ? Colors.white
                      : const Color(0xFF1D2B4A),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),

        // =================================================
        // ABOUT APP
        // =================================================

        PopupMenuItem<String>(
          value: 'about',
          height: 52,
          child: Row(
            children: [
              Icon(
                Icons.info,
                color: isDarkMode
                    ? Colors.white
                    : const Color(0xFF1D2B4A),
                size: 22,
              ),
              const SizedBox(width: 12),
              Text(
                'About app',
                style: TextStyle(
                  color: isDarkMode
                      ? Colors.white
                      : const Color(0xFF1D2B4A),
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (!mounted) return;

      switch (value) {
        case 'how_to_use':
          // TODO:
          // Navigator.push(
          //   context,
          //   MaterialPageRoute(
          //     builder: (_) => const HowToUsePage(),
          //   ),
          // );
          break;

        case 'terms':
          // TODO:
          // Navigator.push(
          //   context,
          //   MaterialPageRoute(
          //     builder: (_) => const TermsPage(),
          //   ),
          // );
          break;

        case 'about':
          // TODO:
          // Navigator.push(
          //   context,
          //   MaterialPageRoute(
          //     builder: (_) => const AboutPage(),
          //   ),
          // );
          break;
      }
    });
  }

  // =====================================================
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {
    final dbRef = FirebaseDatabase.instance.ref();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      color: isDarkMode
          ? const Color(0xFF212121)
          : Colors.white,
      child: Scaffold(
        backgroundColor: isDarkMode
            ? const Color(0xFF212121)
            : Colors.white,

        // =================================================
        // NO END DRAWER
        // =================================================

        body: StreamBuilder<DatabaseEvent>(
          stream: dbRef.child('flood').onValue,
          builder: (context, snapshot) {
            // =================================================
            // ERROR
            // =================================================

            if (snapshot.hasError) {
              return const Center(
                child: Text(
                  'Error loading data',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.red,
                  ),
                ),
              );
            }

            // =================================================
            // LOADING
            // =================================================

            if (!snapshot.hasData ||
                snapshot.data!.snapshot.value == null) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            }

            // =================================================
            // FIREBASE DATA
            // =================================================

            final rawValue =
                snapshot.data!.snapshot.value;

            if (rawValue is! Map) {
              return const Center(
                child: Text(
                  'Invalid data format',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.red,
                  ),
                ),
              );
            }

            final rawData =
                rawValue as Map<dynamic, dynamic>;

            final data = rawData.map(
              (key, value) => MapEntry(
                key.toString(),
                value,
              ),
            );

            // =================================================
            // WATER LEVEL
            // =================================================

            final dynamic distanceRaw =
                data['distance'];

            final double waterLevel =
                distanceRaw is num
                    ? distanceRaw.toDouble()
                    : double.tryParse(
                          distanceRaw?.toString() ?? '',
                        ) ??
                        0;

            // =================================================
            // HUMIDITY
            // =================================================

            final dynamic humidityRaw =
                data['humidity'];

            final double humidity =
                humidityRaw is num
                    ? humidityRaw.toDouble()
                    : double.tryParse(
                          humidityRaw?.toString() ?? '',
                        ) ??
                        0;

            // =================================================
            // SCREEN SIZE
            // =================================================

            final double screenHeight =
                MediaQuery.of(context).size.height;

            final double topHeight =
                screenHeight * 0.40;

            // =================================================
            // MAIN CONTENT
            // =================================================

            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  // =================================================
                  // HEADER
                  // =================================================

                  Container(
                    height: topHeight,
                    width: double.infinity,
                    alignment: Alignment.topCenter,
                    color: isDarkMode
                        ? const Color(0xFF212121)
                        : const Color.fromARGB(
                            255,
                            72,
                            119,
                            247,
                          ),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding:
                            const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            // =================================================
                            // HEADER ROW
                            // =================================================

                            Row(
                              children: [
                                // =================================================
                                // LOGO
                                // =================================================

                                GestureDetector(
                                  onDoubleTap:
                                      toggleTheme,
                                  child: SizedBox(
                                    width: 50,
                                    height: 50,
                                    child: Image.asset(
                                      "assets/icon/detect-co_logo.png",
                                    ),
                                  ),
                                ),

                                const SizedBox(
                                  width: 8,
                                ),

                                // =================================================
                                // APP NAME
                                // =================================================

                                const Text(
                                  'DETECT-CO',
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight:
                                        FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),

                                const Spacer(),

                                // =================================================
                                // NOTIFICATION
                                // =================================================

                                IconButton(
                                  icon: const Icon(
                                    Icons
                                        .notifications_none_rounded,
                                    color:
                                        Colors.white,
                                    size: 26,
                                  ),
                                  onPressed: () {},
                                ),

                                // =================================================
                                // BURGER MENU
                                // =================================================

                                Builder(
                                  builder:
                                      (menuContext) {
                                    return IconButton(
                                      icon:
                                          const Icon(
                                        Icons
                                            .menu_rounded,
                                        color:
                                            Colors.white,
                                        size: 26,
                                      ),
                                      onPressed: () {
                                        _showMenu(
                                          menuContext,
                                        );
                                      },
                                    );
                                  },
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // =================================================
                            // GREETING
                            // =================================================

                            const Text(
                              'Hello, Mike!',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight:
                                    FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),

                            const SizedBox(height: 4),

                            // =================================================
                            // LOCATION + TIME
                            // =================================================

                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on,
                                  color:
                                      Colors.white70,
                                  size: 16,
                                ),

                                const SizedBox(width: 4),

                                const Text(
                                  'Barangay Biringan',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color:
                                        Colors.white70,
                                  ),
                                ),

                                const Spacer(),

                                const Text(
                                  'Time Check haydol',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color:
                                        Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // =================================================
                  // SENSOR CARD
                  // =================================================

                  Transform.translate(
                    offset: const Offset(0, -100),
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 20,
                      ),
                      child: Container(
                        padding:
                            const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? const Color(0xFF2C2C2C)
                              : Colors.white,
                          borderRadius:
                              BorderRadius.circular(
                            20,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black
                                  .withOpacity(
                                isDarkMode
                                    ? 0.25
                                    : 0.08,
                              ),
                              blurRadius: 6,
                              offset:
                                  const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment
                                  .start,
                          children: [
                            // =================================================
                            // TEMPERATURE + HUMIDITY
                            // =================================================

                            Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                              children: [
                                // =================================================
                                // TEMPERATURE
                                // =================================================

                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment
                                            .start,
                                    children: [
                                      Text(
                                        'Current Temperature:',
                                        style:
                                            TextStyle(
                                          fontSize:
                                              14,
                                          fontWeight:
                                              FontWeight
                                                  .w500,
                                          color: isDarkMode
                                              ? Colors
                                                  .white
                                              : Colors
                                                  .black,
                                        ),
                                      ),

                                      const SizedBox(
                                        height: 6,
                                      ),

                                      Row(
                                        children: [
                                          Image.asset(
                                            'assets/icon/thermometer.png',
                                            width: 50,
                                            height: 80,
                                          ),

                                          const SizedBox(
                                            width: 8,
                                          ),

                                          Flexible(
                                            child:
                                                Text(
                                              '${data['temperature']?.toString() ?? '--'}°C',
                                              style:
                                                  TextStyle(
                                                fontSize:
                                                    30,
                                                fontWeight:
                                                    FontWeight
                                                        .bold,
                                                color: isDarkMode
                                                    ? Colors
                                                        .white
                                                    : Colors
                                                        .black,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // =================================================
                                // HUMIDITY
                                // =================================================

                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment
                                            .end,
                                    children: [
                                      Image.asset(
                                        'assets/icon/house.png',
                                        width: 120,
                                        height: 100,
                                      ),

                                      const SizedBox(
                                        height: 4,
                                      ),

                                      Align(
                                        alignment:
                                            Alignment
                                                .center,
                                        child: Text(
                                          'Humidity:',
                                          style:
                                              TextStyle(
                                            fontSize:
                                                14,
                                            fontWeight:
                                                FontWeight
                                                    .w500,
                                            color: isDarkMode
                                                ? Colors
                                                    .white
                                                : Colors
                                                    .black,
                                          ),
                                        ),
                                      ),

                                      const SizedBox(
                                        height: 8,
                                      ),

                                      Align(
                                        alignment:
                                            Alignment
                                                .center,
                                        child:
                                            CustomPaint(
                                          size:
                                              const Size(
                                            150,
                                            90,
                                          ),
                                          painter:
                                              _HumidityGaugePainter(
                                            percent:
                                                (humidity /
                                                        100)
                                                    .clamp(
                                                      0,
                                                      1,
                                                    )
                                                    .toDouble(),
                                            isDark:
                                                isDarkMode,
                                          ),
                                          child:
                                              SizedBox(
                                            width: 150,
                                            height: 90,
                                            child:
                                                Padding(
                                              padding:
                                                  const EdgeInsets
                                                      .only(
                                                top: 26,
                                              ),
                                              child:
                                                  Center(
                                                child:
                                                    Text(
                                                  '${humidity.toStringAsFixed(0)}%',
                                                  style:
                                                      TextStyle(
                                                    fontSize:
                                                        24,
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    color: isDarkMode
                                                        ? Colors
                                                            .white
                                                        : Colors
                                                            .black,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            // =================================================
                            // WATER LEVEL + FLOOD STATUS
                            // =================================================

                            Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment
                                      .center,
                              children: [
                                // =================================================
                                // WATER LEVEL
                                // =================================================

                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment
                                            .center,
                                    children: [
                                      Text(
                                        'Water Level:',
                                        style:
                                            TextStyle(
                                          fontSize:
                                              14,
                                          fontWeight:
                                              FontWeight
                                                  .w500,
                                          color: isDarkMode
                                              ? Colors
                                                  .white
                                              : Colors
                                                  .black,
                                        ),
                                      ),

                                      const SizedBox(
                                        height: 8,
                                      ),

                                      SizedBox(
                                        height: 210,
                                        child:
                                            LayoutBuilder(
                                          builder:
                                              (
                                            context,
                                            constraints,
                                          ) {
                                            final double
                                                tubeCanvasWidth =
                                                constraints
                                                        .maxWidth *
                                                    0.7;

                                            return Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .start,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment
                                                      .start,
                                              children: [
                                                Padding(
                                                  padding:
                                                      const EdgeInsets
                                                          .only(
                                                    left:
                                                        12,
                                                  ),
                                                  child:
                                                      Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .center,
                                                    children: [
                                                      Text(
                                                        '${waterLevel.toStringAsFixed(1)} cm',
                                                        style:
                                                            TextStyle(
                                                          fontSize:
                                                              20,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: isDarkMode
                                                              ? Colors
                                                                  .white
                                                              : Colors
                                                                  .black,
                                                        ),
                                                      ),

                                                      const SizedBox(
                                                        height:
                                                            4,
                                                      ),

                                                      CustomPaint(
                                                        size:
                                                            Size(
                                                          tubeCanvasWidth,
                                                          180,
                                                        ),
                                                        painter:
                                                            _WaterBucketPainter(
                                                          level:
                                                              waterLevel,
                                                          maxLevel:
                                                              80,
                                                          isDark:
                                                              isDarkMode,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),

                                                // =================================================
                                                // WATER LEVEL MARKERS
                                                // =================================================

                                                Expanded(
                                                  child:
                                                      Padding(
                                                    padding:
                                                        const EdgeInsets
                                                            .only(
                                                      top:
                                                          34,
                                                    ),
                                                    child:
                                                        SizedBox(
                                                      height:
                                                          180,
                                                      child:
                                                          Column(
                                                        mainAxisAlignment:
                                                            MainAxisAlignment.spaceBetween,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            '100 cm',
                                                            style:
                                                                TextStyle(
                                                              color:
                                                                  Colors.red.shade400,
                                                              fontWeight:
                                                                  FontWeight.bold,
                                                              fontSize:
                                                                  11,
                                                            ),
                                                          ),

                                                          Text(
                                                            '50 cm',
                                                            style:
                                                                TextStyle(
                                                              color:
                                                                  Colors.orange.shade700,
                                                              fontWeight:
                                                                  FontWeight.bold,
                                                              fontSize:
                                                                  11,
                                                            ),
                                                          ),

                                                          Text(
                                                            '0 cm',
                                                            style:
                                                                TextStyle(
                                                              color:
                                                                  Colors.orange.shade300,
                                                              fontWeight:
                                                                  FontWeight.bold,
                                                              fontSize:
                                                                  11,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // =================================================
                                // FLOOD RISK STATUS
                                // =================================================

                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment
                                            .center,
                                    children: [
                                      Text(
                                        'Flood Risk Status',
                                        style:
                                            TextStyle(
                                          fontSize:
                                              14,
                                          fontWeight:
                                              FontWeight
                                                  .w500,
                                          color: isDarkMode
                                              ? Colors
                                                  .white
                                              : Colors
                                                  .black,
                                        ),
                                      ),

                                      const SizedBox(
                                        height: 4,
                                      ),

                                      Container(
                                        padding:
                                            const EdgeInsets
                                                .symmetric(
                                          vertical: 4,
                                          horizontal: 8,
                                        ),
                                        decoration:
                                            BoxDecoration(
                                          color: waterLevel >
                                                  40
                                              ? Colors
                                                  .green
                                                  .shade700
                                              : waterLevel >
                                                      30
                                                  ? Colors
                                                      .orange
                                                      .shade700
                                                  : Colors
                                                      .red
                                                      .shade700,
                                          borderRadius:
                                              BorderRadius
                                                  .circular(
                                            12,
                                          ),
                                        ),
                                        child: Text(
                                          waterLevel > 40
                                              ? 'Safe'
                                              : waterLevel >
                                                      30
                                                  ? 'Medium Risk'
                                                  : 'Flooding!',
                                          style:
                                              const TextStyle(
                                            fontSize: 20,
                                            fontWeight:
                                                FontWeight
                                                    .bold,
                                            color: Colors
                                                .white,
                                          ),
                                        ),
                                      ),
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

                  // =================================================
                  // FLOOD PREPARATION GUIDES
                  // =================================================

                  const SizedBox(height: 20),

                  Transform.translate(
                    offset: const Offset(0, -100),
                    child: Padding(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 20,
                      ),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment
                                .spaceBetween,
                        children: [
                          Text(
                            "Flood Preparation Guides",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight:
                                  FontWeight.bold,
                              color: isDarkMode
                                  ? Colors.white
                                  : Colors.black,
                            ),
                          ),

                          Text(
                            "See All >",
                            style: TextStyle(
                              fontSize: 14,
                              color: isDarkMode
                                  ? const Color
                                      .fromARGB(
                                      255,
                                      166,
                                      185,
                                      201,
                                    )
                                  : const Color
                                      .fromARGB(
                                      255,
                                      112,
                                      123,
                                      133,
                                    ),
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
        ),
      ),
    );
  }
}

// =====================================================
// SENSOR CARD
// =====================================================

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
      return isDark
          ? const Color(0xFF2C2C2C)
          : Colors.white;
    }

    final level = waterLevel!;

    if (level > 40) {
      return Colors.green.shade700;
    }

    if (level > 30) {
      return Colors.orange.shade700;
    }

    return Colors.red.shade700;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration:
          const Duration(milliseconds: 400),
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(
        vertical: 12,
        horizontal: 8,
      ),
      decoration: BoxDecoration(
        color: _getCardColor(),
        borderRadius:
            BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.grey.shade800
              : Colors.grey.shade300,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              isDark ? 0.25 : 0.08,
            ),
            blurRadius: 6,
            offset:
                const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight:
                  FontWeight.w500,
              color: isDark
                  ? Colors.grey[300]
                  : Colors.grey,
            ),
          ),

          const SizedBox(height: 6),

          Row(
            mainAxisAlignment:
                MainAxisAlignment.center,
            crossAxisAlignment:
                CrossAxisAlignment.baseline,
            textBaseline:
                TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight:
                      FontWeight.bold,
                  color: isDark
                      ? Colors.white
                      : Colors.black,
                ),
              ),

              const SizedBox(width: 2),

              Text(
                unit,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? Colors.grey[300]
                      : Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// =====================================================
// WARNING CARD
// =====================================================

class WarningCard extends StatelessWidget {
  final double waterLevel;
  final bool isDark;

  const WarningCard({
    super.key,
    required this.waterLevel,
    required this.isDark,
  });

  String get statusText {
    if (waterLevel > 40) {
      return 'Safe';
    }

    if (waterLevel > 30) {
      return 'Medium Risk';
    }

    return 'Flooding!';
  }

  Color get statusColor {
    if (waterLevel > 40) {
      return const Color.fromRGBO(
        76,
        175,
        80,
        1,
      );
    }

    if (waterLevel > 30) {
      return Colors.orange;
    }

    return const Color.fromRGBO(
      244,
      67,
      54,
      1,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration:
          const Duration(milliseconds: 400),
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(
        vertical: 16,
        horizontal: 12,
      ),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF2C2C2C)
            : statusColor,
        borderRadius:
            BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color:
                statusColor.withOpacity(0.3),
            blurRadius: 4,
            offset:
                const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.center,
        children: [
          const Text(
            'Flood Risk Status',
            style: TextStyle(
              fontSize: 14,
              fontWeight:
                  FontWeight.w500,
              color: Colors.white70,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            statusText,
            style: const TextStyle(
              fontSize: 28,
              fontWeight:
                  FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================
// WATER BUCKET PAINTER
// =====================================================

class _WaterBucketPainter
    extends CustomPainter {
  final double level;
  final double maxLevel;
  final bool isDark;

  _WaterBucketPainter({
    required this.level,
    required this.maxLevel,
    required this.isDark,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    // =================================================
    // TUBE DIMENSIONS
    // =================================================

    final double tubeWidth =
        size.width * 0.9;

    final double left =
        (size.width - tubeWidth) / 2;

    final double right =
        left + tubeWidth;

    final double top = 4;

    final double bottom =
        size.height - 4;

    final double cornerRadius = 14;

    // =================================================
    // OUTLINE
    // =================================================

    final outlinePaint = Paint()
      ..color = Colors.blue.shade600
      ..style =
          PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap =
          StrokeCap.round;

    // =================================================
    // TUBE PATH
    // =================================================

    final tubePath = Path()
      ..moveTo(left, top)
      ..lineTo(
        left,
        bottom - cornerRadius,
      )
      ..quadraticBezierTo(
        left,
        bottom,
        left + cornerRadius,
        bottom,
      )
      ..lineTo(
        right - cornerRadius,
        bottom,
      )
      ..quadraticBezierTo(
        right,
        bottom,
        right,
        bottom - cornerRadius,
      )
      ..lineTo(
        right,
        top,
      );

    // =================================================
    // WATER LEVEL
    // =================================================

    final double percent =
        (level / maxLevel)
            .clamp(0, 1)
            .toDouble();

    final double fillHeight =
        (bottom - top) * percent;

    final double fillTop =
        bottom - fillHeight;

    final fillPaint = Paint()
      ..color = isDark
          ? Colors.blue.shade900
              .withOpacity(0.6)
          : Colors.blue.shade100;

    // =================================================
    // CLIP WATER INSIDE TUBE
    // =================================================

    canvas.save();

    canvas.clipPath(
      Path()
        ..moveTo(left, top)
        ..lineTo(
          left,
          bottom - cornerRadius,
        )
        ..quadraticBezierTo(
          left,
          bottom,
          left + cornerRadius,
          bottom,
        )
        ..lineTo(
          right - cornerRadius,
          bottom,
        )
        ..quadraticBezierTo(
          right,
          bottom,
          right,
          bottom - cornerRadius,
        )
        ..lineTo(
          right,
          top,
        )
        ..close(),
    );

    canvas.drawRect(
      Rect.fromLTRB(
        left,
        fillTop,
        right,
        bottom,
      ),
      fillPaint,
    );

    canvas.restore();

    // =================================================
    // DRAW OUTLINE
    // =================================================

    canvas.drawPath(
      tubePath,
      outlinePaint,
    );
  }

  @override
  bool shouldRepaint(
    covariant _WaterBucketPainter
        oldDelegate,
  ) {
    return oldDelegate.level != level ||
        oldDelegate.isDark != isDark;
  }
}

// =====================================================
// HUMIDITY GAUGE PAINTER
// =====================================================

class _HumidityGaugePainter
    extends CustomPainter {
  final double percent;
  final bool isDark;

  _HumidityGaugePainter({
    required this.percent,
    required this.isDark,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    // =================================================
    // GAUGE SETTINGS
    // =================================================

    final double strokeWidth = 14;

    final Rect rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.width - strokeWidth,
    );

    // =================================================
    // BACKGROUND ARC
    // =================================================

    final bgPaint = Paint()
      ..color = isDark
          ? Colors.blue.shade900
              .withOpacity(0.5)
          : Colors.blue.shade100
      ..style =
          PaintingStyle.stroke
      ..strokeWidth =
          strokeWidth
      ..strokeCap =
          StrokeCap.round;

    // =================================================
    // FOREGROUND ARC
    // =================================================

    final fgPaint = Paint()
      ..color =
          Colors.blue.shade600
      ..style =
          PaintingStyle.stroke
      ..strokeWidth =
          strokeWidth
      ..strokeCap =
          StrokeCap.round;

    // =================================================
    // FULL BACKGROUND HALF CIRCLE
    // =================================================

    canvas.drawArc(
      rect,
      math.pi,
      math.pi,
      false,
      bgPaint,
    );

    // =================================================
    // HUMIDITY ARC
    // =================================================

    canvas.drawArc(
      rect,
      math.pi,
      math.pi * percent,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(
    covariant _HumidityGaugePainter
        oldDelegate,
  ) {
    return oldDelegate.percent !=
            percent ||
        oldDelegate.isDark != isDark;
  }
}
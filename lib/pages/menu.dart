
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:detectco/main.dart';
import 'package:detectco/pages/local_ai_test.dart';
import 'package:detectco/pages/home.dart'; // change to your actual home file name (the file that contains setHomeRefreshRate)

// =====================================================
// HOME BACKGROUND CHOICE (DEMO SELECTOR)
// =====================================================
//
// Shared between the Menu tab (where the user picks it) and the
// Home tab (which reads it to decide which background to show).
//
// auto  = default: the background follows the live weather API.
// others = forced background, for demo purposes only.

enum HomeBgChoice {
  auto,
  storm,
  rain,
  cloudy,
  sunny,
}

// Global notifier so both tabs stay in sync without touching
// any other part of the app.
final ValueNotifier<HomeBgChoice> homeBgChoice =
    ValueNotifier<HomeBgChoice>(HomeBgChoice.auto);

// =====================================================
// HOME BACKGROUND QUALITY (HIGH / LOW-END)
// =====================================================
//
// high = the original detailed backgrounds.
// low  = lightweight backgrounds for low-end devices
//        (fewer rain particles, no blur filters, static layers).
//
// This only changes WHICH VERSION of the chosen background is
// drawn. The weather choice above still decides the weather.

enum HomeBgQuality {
  high,
  low,
}

final ValueNotifier<HomeBgQuality> homeBgQuality =
    ValueNotifier<HomeBgQuality>(HomeBgQuality.high);

// =====================================================
// MENU SETTINGS STORAGE
// =====================================================
//
// These keys are used only for saving the Display Settings choices.
// They allow the settings to survive a complete app close/reopen.

const String _homeBgChoiceKey = 'detect_co_home_bg_choice';
const String _homeBgQualityKey = 'detect_co_home_bg_quality';
const String _homeRefreshRateKey = 'detect_co_home_refresh_rate';
const String _homeWaterLiteKey = 'detect_co_home_water_lite';
const String _homePerformanceModeKey =
    'detect_co_home_performance_mode';

// MenuTab is now a StatefulWidget so the Display Settings card
// can remember whether it is expanded or collapsed.
class MenuTab extends StatefulWidget {
  const MenuTab({super.key});

  @override
  State<MenuTab> createState() => _MenuTabState();
}

class _MenuTabState extends State<MenuTab> {
  // Whether the Display Settings card is expanded.
  bool _displaySettingsExpanded = false;

  // Whether the Home Background section inside Display Settings
  // is expanded.
  bool _bgExpanded = false;

  // Whether the Dashboard Refresh Rate section inside
  // Display Settings is expanded.
  bool _refreshExpanded = false;

  @override
  void initState() {
    super.initState();

    // Restore the user's saved Display Settings.
    _loadSavedDisplaySettings();
  }

  // =====================================================
  // LOAD SAVED DISPLAY SETTINGS
  // =====================================================

  Future<void> _loadSavedDisplaySettings() async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    // -----------------------------------------------------
    // HOME BACKGROUND
    // -----------------------------------------------------

    final int? savedBgChoice =
        prefs.getInt(_homeBgChoiceKey);

    if (savedBgChoice != null &&
        savedBgChoice >= 0 &&
        savedBgChoice < HomeBgChoice.values.length) {
      homeBgChoice.value =
          HomeBgChoice.values[savedBgChoice];
    }

    // -----------------------------------------------------
    // HOME BACKGROUND QUALITY
    // -----------------------------------------------------

    final int? savedBgQuality =
        prefs.getInt(_homeBgQualityKey);

    if (savedBgQuality != null &&
        savedBgQuality >= 0 &&
        savedBgQuality < HomeBgQuality.values.length) {
      homeBgQuality.value =
          HomeBgQuality.values[savedBgQuality];
    }

    // -----------------------------------------------------
    // DASHBOARD REFRESH RATE
    // -----------------------------------------------------

    final int? savedRefreshRate =
        prefs.getInt(_homeRefreshRateKey);

    if (savedRefreshRate != null) {
      final Duration savedInterval =
          Duration(milliseconds: savedRefreshRate);

      setHomeRefreshRate(savedInterval);
    }

    // -----------------------------------------------------
    // WATER LITE MODE
    // -----------------------------------------------------

    final bool? savedWaterLite =
        prefs.getBool(_homeWaterLiteKey);

    if (savedWaterLite != null) {
      setHomeWaterLiteMode(savedWaterLite);
    }

    // -----------------------------------------------------
    // LOW-END PERFORMANCE MODE
    // -----------------------------------------------------

    final bool? savedPerformanceMode =
        prefs.getBool(_homePerformanceModeKey);

    if (savedPerformanceMode != null) {
      setHomePerformanceMode(savedPerformanceMode);
    }
  }

  // =====================================================
  // SAVE HOME BACKGROUND
  // =====================================================

  Future<void> _saveHomeBgChoice(
    HomeBgChoice value,
  ) async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    await prefs.setInt(
      _homeBgChoiceKey,
      value.index,
    );
  }

  // =====================================================
  // SAVE HOME BACKGROUND QUALITY
  // =====================================================

  Future<void> _saveHomeBgQuality(
    HomeBgQuality value,
  ) async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    await prefs.setInt(
      _homeBgQualityKey,
      value.index,
    );
  }

  // =====================================================
  // SAVE DASHBOARD REFRESH RATE
  // =====================================================

  Future<void> _saveRefreshRate(
    Duration value,
  ) async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    await prefs.setInt(
      _homeRefreshRateKey,
      value.inMilliseconds,
    );
  }

  // =====================================================
  // SAVE WATER LITE MODE
  // =====================================================

  Future<void> _saveWaterLiteMode(
    bool value,
  ) async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    await prefs.setBool(
      _homeWaterLiteKey,
      value,
    );
  }

  // =====================================================
  // SAVE LOW-END PERFORMANCE MODE
  // =====================================================

  Future<void> _savePerformanceMode(
    bool value,
  ) async {
    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    await prefs.setBool(
      _homePerformanceModeKey,
      value,
    );
  }

  @override
  Widget build(BuildContext context) {
    const bool isDarkMode = true;

    final Color backgroundColor =
        const Color(0xFF212121);

    final Color headerColor =
        const Color(0xFF212121);

    final Color cardColor =
        const Color(0xFF2C2C2C);

    final Color textColor =
        Colors.white;

    final Color secondaryColor =
        Colors.white70;

    return Scaffold(
      backgroundColor: backgroundColor,

      body: SafeArea(
        bottom: false,

        child: Column(
          children: [

            // =====================================================
            // HEADER
            // =====================================================

            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              color: headerColor,

              child: Row(
                children: [

                  // =================================================
                  // LOGO
                  // =================================================

                  SizedBox(
                    width: 50,
                    height: 50,

                    child: Image.asset(
                      'assets/icon/detect-co_logo.png',
                    ),
                  ),

                  const SizedBox(width: 8),

                  // =================================================
                  // PAGE NAME
                  // =================================================

                  const Text(
                    'Menu',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),

            // =====================================================
            // CONTENT
            // =====================================================

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  20,
                  24,
                  20,
                  30,
                ),

                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,

                  children: [

                    // =================================================
                    // TITLE
                    // =================================================

                    Text(
                      'Menu',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Text(
                      'Manage and learn more about DETECT-CO',
                      style: TextStyle(
                        fontSize: 14,
                        color: secondaryColor,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // =================================================
                    // HOW TO USE
                    // =================================================

                    _buildMenuCard(
                      context: context,
                      isDarkMode: isDarkMode,
                      cardColor: cardColor,
                      textColor: textColor,
                      icon: Icons.help_outline_rounded,
                      title: 'How to Use',
                      subtitle:
                          'Learn how to use DETECT-CO',
                      onTap: () {
                        // Open How to Use page
                      },
                    ),

                    const SizedBox(height: 14),

                    // =================================================
                    // TERMS OF SERVICE
                    // =================================================

                    _buildMenuCard(
                      context: context,
                      isDarkMode: isDarkMode,
                      cardColor: cardColor,
                      textColor: textColor,
                      icon: Icons.description_outlined,
                      title: 'Terms of Service',
                      subtitle:
                          'Read the terms and conditions',
                      onTap: () {
                        // Open Terms of Service page
                      },
                    ),

                    const SizedBox(height: 14),

                    // =================================================
                    // ABOUT APP
                    // =================================================

                    _buildMenuCard(
                      context: context,
                      isDarkMode: isDarkMode,
                      cardColor: cardColor,
                      textColor: textColor,
                      icon: Icons.info_outline_rounded,
                      title: 'About App',
                      subtitle:
                          'Learn more about DETECT-CO',
                      onTap: () {
                        // Open About App page
                      },
                    ),

                    const SizedBox(height: 14),

                    // =================================================
                    // LOCAL AI
                    // =================================================

                    _buildMenuCard(
                      context: context,
                      isDarkMode: isDarkMode,
                      cardColor: cardColor,
                      textColor: textColor,
                      icon: Icons.smart_toy_outlined,
                      title: 'Local AI',
                      subtitle:
                          'Test the DETECT-CO local AI assistant',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const LocalAiTestPage(),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 14),

                    // =================================================
                    // DISPLAY SETTINGS
                    // =================================================

                    _buildDisplaySettingsCard(
                      isDarkMode: isDarkMode,
                      cardColor: cardColor,
                      textColor: textColor,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // MENU CARD
  // =====================================================

  Widget _buildMenuCard({
    required BuildContext context,
    required bool isDarkMode,
    required Color cardColor,
    required Color textColor,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,

      child: InkWell(
        borderRadius: BorderRadius.circular(20),

        onTap: onTap,

        child: AnimatedContainer(
          duration:
              const Duration(milliseconds: 250),

          width: double.infinity,

          padding: const EdgeInsets.symmetric(
            horizontal: 18,
            vertical: 18,
          ),

          decoration: BoxDecoration(
            color: cardColor,

            borderRadius:
                BorderRadius.circular(20),

            border: Border.all(
              color: isDarkMode
                  ? Colors.grey.shade800
                  : Colors.grey.shade200,
            ),

            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(
                  isDarkMode
                      ? 0.25
                      : 0.08,
                ),

                blurRadius: 6,

                offset: const Offset(
                  0,
                  4,
                ),
              ),
            ],
          ),

          child: Row(
            children: [

              // =================================================
              // ICON CONTAINER
              // =================================================

              Container(
                width: 52,
                height: 52,

                decoration: BoxDecoration(
                  color: isDarkMode
                      ? const Color(0xFF383838)
                      : const Color(0xFFEAF0FF),

                  borderRadius:
                      BorderRadius.circular(16),
                ),

                child: Icon(
                  icon,
                  size: 27,

                  color: isDarkMode
                      ? Colors.white
                      : const Color(0xFF4877F7),
                ),
              ),

              const SizedBox(width: 16),

              // =================================================
              // TEXT
              // =================================================

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,

                  children: [

                    Text(
                      title,

                      style: TextStyle(
                        fontSize: 17,
                        fontWeight:
                            FontWeight.w600,
                        color: textColor,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      subtitle,

                      style: TextStyle(
                        fontSize: 13,
                        color: isDarkMode
                            ? Colors.white60
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),

              // =================================================
              // ARROW
              // =================================================

              Icon(
                Icons.chevron_right_rounded,

                size: 28,

                color: isDarkMode
                    ? Colors.white54
                    : Colors.grey.shade500,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================
  // DISPLAY SETTINGS CARD
  // =====================================================

  Widget _buildDisplaySettingsCard({
    required bool isDarkMode,
    required Color cardColor,
    required Color textColor,
  }) {
    return Container(
      width: double.infinity,

      decoration: BoxDecoration(
        color: cardColor,

        borderRadius:
            BorderRadius.circular(20),

        border: Border.all(
          color: isDarkMode
              ? Colors.grey.shade800
              : Colors.grey.shade200,
        ),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(
              isDarkMode
                  ? 0.25
                  : 0.08,
            ),

            blurRadius: 6,

            offset: const Offset(
              0,
              4,
            ),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [

          // =================================================
          // DISPLAY SETTINGS HEADER
          // =================================================

          Material(
            color: Colors.transparent,

            child: InkWell(
              borderRadius:
                  BorderRadius.circular(20),

              onTap: () {
                setState(() {
                  _displaySettingsExpanded =
                      !_displaySettingsExpanded;
                });
              },

              child: Padding(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 18,
                ),

                child: Row(
                  children: [

                    Container(
                      width: 52,
                      height: 52,

                      decoration: BoxDecoration(
                        color: isDarkMode
                            ? const Color(0xFF383838)
                            : const Color(0xFFEAF0FF),

                        borderRadius:
                            BorderRadius.circular(16),
                      ),

                      child: Icon(
                        Icons.display_settings_rounded,
                        size: 27,

                        color: isDarkMode
                            ? Colors.white
                            : const Color(0xFF4877F7),
                      ),
                    ),

                    const SizedBox(width: 16),

                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,

                        children: [

                          Text(
                            'Display Settings',

                            style: TextStyle(
                              fontSize: 17,
                              fontWeight:
                                  FontWeight.w600,
                              color: textColor,
                            ),
                          ),

                          const SizedBox(height: 4),

                          Text(
                            'Customize the Home display and performance',

                            style: TextStyle(
                              fontSize: 13,
                              color: isDarkMode
                                  ? Colors.white60
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // =========================================
                    // ARROW
                    // =========================================

                    AnimatedRotation(
                      turns:
                          _displaySettingsExpanded
                              ? 0.25
                              : 0.0,

                      duration:
                          const Duration(milliseconds: 250),

                      child: Icon(
                        Icons.chevron_right_rounded,

                        size: 28,

                        color: isDarkMode
                            ? Colors.white54
                            : Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // =================================================
          // DISPLAY SETTINGS CONTENT
          // =================================================

          AnimatedSize(
            duration:
                const Duration(milliseconds: 250),

            curve: Curves.easeInOut,

            alignment: Alignment.topCenter,

            child: _displaySettingsExpanded
                ? Padding(
                    padding:
                        const EdgeInsets.fromLTRB(
                      18,
                      0,
                      18,
                      18,
                    ),

                    child: Column(
                      children: [

                        // =================================================
                        // HOME BACKGROUND
                        // =================================================

                        _buildBackgroundSelectorSection(
                          isDarkMode: isDarkMode,
                          textColor: textColor,
                        ),

                        const SizedBox(height: 12),

                        // =================================================
                        // DASHBOARD REFRESH RATE
                        // =================================================

                        _buildRefreshRateSection(
                          isDarkMode: isDarkMode,
                          textColor: textColor,
                        ),

                        const SizedBox(height: 12),

                        // =================================================
                        // WATER LITE MODE
                        // =================================================

                        _buildWaterLiteSection(
                          isDarkMode: isDarkMode,
                          textColor: textColor,
                        ),

                        const SizedBox(height: 12),

                        // =================================================
                        // LOW-END PERFORMANCE MODE
                        // =================================================

                        _buildPerformanceModeSection(
                          isDarkMode: isDarkMode,
                          textColor: textColor,
                        ),
                      ],
                    ),
                  )
                : const SizedBox(
                    width: double.infinity,
                  ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // HOME BACKGROUND SECTION
  // =====================================================

  Widget _buildBackgroundSelectorSection({
    required bool isDarkMode,
    required Color textColor,
  }) {
    return Container(
      width: double.infinity,

      decoration: BoxDecoration(
        color: const Color(0xFF383838),

        borderRadius:
            BorderRadius.circular(16),

        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ),

      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [

          // =================================================
          // HEADER
          // =================================================

          Material(
            color: Colors.transparent,

            child: InkWell(
              borderRadius:
                  BorderRadius.circular(16),

              onTap: () {
                setState(() {
                  _bgExpanded = !_bgExpanded;
                });
              },

              child: Padding(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),

                child: Row(
                  children: [

                    Container(
                      width: 44,
                      height: 44,

                      decoration: BoxDecoration(
                        color: const Color(0xFF444444),

                        borderRadius:
                            BorderRadius.circular(13),
                      ),

                      child: const Icon(
                        Icons.wallpaper_rounded,
                        size: 23,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(width: 13),

                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,

                        children: [

                          Text(
                            'Home Background',

                            style: TextStyle(
                              fontSize: 16,
                              fontWeight:
                                  FontWeight.w600,
                              color: textColor,
                            ),
                          ),

                          const SizedBox(height: 3),

                          Text(
                            'Choose the weather shown on Home',

                            style: TextStyle(
                              fontSize: 12,
                              color: isDarkMode
                                  ? Colors.white60
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    AnimatedRotation(
                      turns:
                          _bgExpanded
                              ? 0.25
                              : 0.0,

                      duration:
                          const Duration(milliseconds: 250),

                      child: const Icon(
                        Icons.chevron_right_rounded,
                        size: 26,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // =================================================
          // BACKGROUND OPTIONS
          // =================================================

          AnimatedSize(
            duration:
                const Duration(milliseconds: 250),

            curve: Curves.easeInOut,

            alignment: Alignment.topCenter,

            child: _bgExpanded
                ? Padding(
                    padding:
                        const EdgeInsets.fromLTRB(
                      14,
                      0,
                      14,
                      14,
                    ),

                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,

                      children: [

                        // =================================================
                        // BACKGROUND DROPDOWN
                        // =================================================

                        ValueListenableBuilder<HomeBgChoice>(
                          valueListenable: homeBgChoice,

                          builder: (context, choice, _) {
                            return Container(
                              width: double.infinity,

                              padding:
                                  const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 4,
                              ),

                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFF303030),

                                borderRadius:
                                    BorderRadius.circular(14),

                                border: Border.all(
                                  color: Colors.white
                                      .withOpacity(0.12),
                                ),
                              ),

                              child:
                                  DropdownButtonHideUnderline(
                                child:
                                    DropdownButton<HomeBgChoice>(
                                  value: choice,
                                  isExpanded: true,

                                  borderRadius:
                                      BorderRadius.circular(14),

                                  dropdownColor:
                                      const Color(0xFF303030),

                                  icon: const Icon(
                                    Icons
                                        .keyboard_arrow_down_rounded,
                                    color: Colors.white70,
                                  ),

                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: Colors.white,
                                    fontWeight:
                                        FontWeight.w500,
                                  ),

                                  items: [
                                    _bgItem(
                                      HomeBgChoice.auto,
                                      Icons.cloud_sync_rounded,
                                      'Default (Live weather from API)',
                                    ),
                                    _bgItem(
                                      HomeBgChoice.storm,
                                      Icons.thunderstorm_rounded,
                                      'Storm',
                                    ),
                                    _bgItem(
                                      HomeBgChoice.rain,
                                      Icons.water_drop_rounded,
                                      'Rain',
                                    ),
                                    _bgItem(
                                      HomeBgChoice.cloudy,
                                      Icons.cloud_rounded,
                                      'Cloudy',
                                    ),
                                    _bgItem(
                                      HomeBgChoice.sunny,
                                      Icons.wb_sunny_rounded,
                                      'Sunny',
                                    ),
                                  ],

                                  onChanged: (value) {
                                    if (value == null) return;

                                    homeBgChoice.value =
                                        value;

                                    // Save the selection so it
                                    // survives a full app restart.
                                    _saveHomeBgChoice(value);
                                  },
                                ),
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 14),

                        // =================================================
                        // QUALITY LABEL
                        // =================================================

                        Text(
                          'Background Quality',

                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                FontWeight.w600,
                            color: textColor,
                          ),
                        ),

                        const SizedBox(height: 4),

                        Text(
                          'Choose Low for smoother performance on low-end devices',

                          style: TextStyle(
                            fontSize: 12,
                            color: isDarkMode
                                ? Colors.white60
                                : Colors.grey.shade600,
                          ),
                        ),

                        const SizedBox(height: 10),

                        // =================================================
                        // QUALITY DROPDOWN
                        // =================================================

                        ValueListenableBuilder<HomeBgQuality>(
                          valueListenable:
                              homeBgQuality,

                          builder:
                              (context, quality, _) {
                            return Container(
                              width: double.infinity,

                              padding:
                                  const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 4,
                              ),

                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFF303030),

                                borderRadius:
                                    BorderRadius.circular(14),

                                border: Border.all(
                                  color: Colors.white
                                      .withOpacity(0.12),
                                ),
                              ),

                              child:
                                  DropdownButtonHideUnderline(
                                child:
                                    DropdownButton<
                                        HomeBgQuality>(
                                  value: quality,
                                  isExpanded: true,

                                  borderRadius:
                                      BorderRadius.circular(14),

                                  dropdownColor:
                                      const Color(0xFF303030),

                                  icon: const Icon(
                                    Icons
                                        .keyboard_arrow_down_rounded,
                                    color: Colors.white70,
                                  ),

                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: Colors.white,
                                    fontWeight:
                                        FontWeight.w500,
                                  ),

                                  items: [
                                    _qualityItem(
                                      HomeBgQuality.high,
                                      Icons
                                          .high_quality_rounded,
                                      'High (Detailed animations)',
                                    ),
                                    _qualityItem(
                                      HomeBgQuality.low,
                                      Icons.speed_rounded,
                                      'Low (Low-end device friendly)',
                                    ),
                                  ],

                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }

                                    homeBgQuality.value =
                                        value;

                                    // Save the selection so it
                                    // survives a full app restart.
                                    _saveHomeBgQuality(value);
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  )
                : const SizedBox(
                    width: double.infinity,
                  ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // DASHBOARD REFRESH RATE SECTION
  // =====================================================

  Widget _buildRefreshRateSection({
    required bool isDarkMode,
    required Color textColor,
  }) {
    return Container(
      width: double.infinity,

      decoration: BoxDecoration(
        color: const Color(0xFF383838),

        borderRadius:
            BorderRadius.circular(16),

        border: Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ),

      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [

          // =================================================
          // HEADER
          // =================================================

          Material(
            color: Colors.transparent,

            child: InkWell(
              borderRadius:
                  BorderRadius.circular(16),

              onTap: () {
                setState(() {
                  _refreshExpanded =
                      !_refreshExpanded;
                });
              },

              child: Padding(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),

                child: Row(
                  children: [

                    Container(
                      width: 44,
                      height: 44,

                      decoration: BoxDecoration(
                        color: const Color(0xFF444444),

                        borderRadius:
                            BorderRadius.circular(13),
                      ),

                      child: const Icon(
                        Icons.update_rounded,
                        size: 23,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(width: 13),

                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,

                        children: [

                          Text(
                            'Dashboard Refresh Rate',

                            style: TextStyle(
                              fontSize: 16,
                              fontWeight:
                                  FontWeight.w600,
                              color: textColor,
                            ),
                          ),

                          const SizedBox(height: 3),

                          Text(
                            'Choose how often Home info updates',

                            style: TextStyle(
                              fontSize: 12,
                              color: isDarkMode
                                  ? Colors.white60
                                  : Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    AnimatedRotation(
                      turns:
                          _refreshExpanded
                              ? 0.25
                              : 0.0,

                      duration:
                          const Duration(milliseconds: 250),

                      child: const Icon(
                        Icons.chevron_right_rounded,
                        size: 26,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // =================================================
          // REFRESH RATE OPTIONS
          // =================================================

          AnimatedSize(
            duration:
                const Duration(milliseconds: 250),

            curve: Curves.easeInOut,

            alignment: Alignment.topCenter,

            child: _refreshExpanded
                ? Padding(
                    padding:
                        const EdgeInsets.fromLTRB(
                      14,
                      0,
                      14,
                      14,
                    ),

                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,

                      children: [

                        Text(
                          'Lower the refresh rate to reduce how often the dashboard changes',

                          style: TextStyle(
                            fontSize: 12,
                            color: isDarkMode
                                ? Colors.white60
                                : Colors.grey.shade600,
                          ),
                        ),

                        const SizedBox(height: 10),

                        ValueListenableBuilder<Duration>(
                          valueListenable:
                              homeRefreshInterval,

                          builder:
                              (context, interval, _) {
                            return Container(
                              width: double.infinity,

                              padding:
                                  const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 4,
                              ),

                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFF303030),

                                borderRadius:
                                    BorderRadius.circular(14),

                                border: Border.all(
                                  color: Colors.white
                                      .withOpacity(0.12),
                                ),
                              ),

                              child:
                                  DropdownButtonHideUnderline(
                                child:
                                    DropdownButton<Duration>(
                                  value: interval,
                                  isExpanded: true,

                                  borderRadius:
                                      BorderRadius.circular(14),

                                  dropdownColor:
                                      const Color(0xFF303030),

                                  icon: const Icon(
                                    Icons
                                        .keyboard_arrow_down_rounded,
                                    color: Colors.white70,
                                  ),

                                  style: const TextStyle(
                                    fontSize: 15,
                                    color: Colors.white,
                                    fontWeight:
                                        FontWeight.w500,
                                  ),

                                  items: [
                                    _refreshItem(
                                      Duration.zero,
                                      Icons.bolt_rounded,
                                      'Real-time (Default)',
                                    ),
                                    _refreshItem(
                                      const Duration(
                                        seconds: 30,
                                      ),
                                      Icons.timer_outlined,
                                      'Every 30 seconds',
                                    ),
                                    _refreshItem(
                                      const Duration(
                                        minutes: 1,
                                      ),
                                      Icons.timer_outlined,
                                      'Every 1 minute',
                                    ),
                                    _refreshItem(
                                      const Duration(
                                        minutes: 5,
                                      ),
                                      Icons.timer_outlined,
                                      'Every 5 minutes',
                                    ),
                                  ],

                                  onChanged: (value) {
                                    if (value == null) {
                                      return;
                                    }

                                    setHomeRefreshRate(
                                      value,
                                    );

                                    // Save the selection so it
                                    // survives a full app restart.
                                    _saveRefreshRate(value);
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  )
                : const SizedBox(
                    width: double.infinity,
                  ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // WATER EFFECTS SECTION (LITE MODE SWITCH)
  // =====================================================

  Widget _buildWaterLiteSection({
    required bool isDarkMode,
    required Color textColor,
  }) {
    return ValueListenableBuilder<bool>(
      valueListenable: homeWaterLite,

      builder: (context, isLite, _) {
        return Material(
          color: Colors.transparent,

          child: InkWell(
            borderRadius:
                BorderRadius.circular(16),

            onTap: () {
              final bool newValue = !isLite;

              setHomeWaterLiteMode(
                newValue,
              );

              // Save the selection so it survives
              // a full app restart.
              _saveWaterLiteMode(newValue);
            },

            child: Container(
              width: double.infinity,

              padding:
                  const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),

              decoration: BoxDecoration(
                color: const Color(0xFF383838),

                borderRadius:
                    BorderRadius.circular(16),

                border: Border.all(
                  color: Colors.white
                      .withOpacity(0.08),
                ),
              ),

              child: Row(
                children: [

                  Container(
                    width: 44,
                    height: 44,

                    decoration: BoxDecoration(
                      color:
                          const Color(0xFF444444),

                      borderRadius:
                          BorderRadius.circular(13),
                    ),

                    child: const Icon(
                      Icons.waves_rounded,
                      size: 23,
                      color: Colors.white,
                    ),
                  ),

                  const SizedBox(width: 13),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,

                      children: [

                        Text(
                          'Water Lite Mode',

                          style: TextStyle(
                            fontSize: 16,
                            fontWeight:
                                FontWeight.w600,
                            color: textColor,
                          ),
                        ),

                        const SizedBox(height: 3),

                        Text(
                          'Straight water, no waves or rubber duck',

                          style: TextStyle(
                            fontSize: 12,
                            color: isDarkMode
                                ? Colors.white60
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  Switch(
                    value: isLite,

                    activeColor:
                        Colors.lightBlueAccent,

                    onChanged: (value) {
                      setHomeWaterLiteMode(
                        value,
                      );

                      // Save the selection so it survives
                      // a full app restart.
                      _saveWaterLiteMode(value);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // =====================================================
  // LOW-END PERFORMANCE MODE SECTION
  // =====================================================

  Widget _buildPerformanceModeSection({
    required bool isDarkMode,
    required Color textColor,
  }) {
    return ValueListenableBuilder<bool>(
      valueListenable:
          homePerformanceMode,

      builder: (context, isPerf, _) {
        return Material(
          color: Colors.transparent,

          child: InkWell(
            borderRadius:
                BorderRadius.circular(16),

            onTap: () {
              final bool newValue = !isPerf;

              setHomePerformanceMode(
                newValue,
              );

              // Save the selection so it survives
              // a full app restart.
              _savePerformanceMode(newValue);
            },

            child: Container(
              width: double.infinity,

              padding:
                  const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),

              decoration: BoxDecoration(
                color: const Color(0xFF383838),

                borderRadius:
                    BorderRadius.circular(16),

                border: Border.all(
                  color: Colors.white
                      .withOpacity(0.08),
                ),
              ),

              child: Row(
                children: [

                  Container(
                    width: 44,
                    height: 44,

                    decoration: BoxDecoration(
                      color:
                          const Color(0xFF444444),

                      borderRadius:
                          BorderRadius.circular(13),
                    ),

                    child: const Icon(
                      Icons.speed_rounded,
                      size: 23,
                      color: Colors.white,
                    ),
                  ),

                  const SizedBox(width: 13),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,

                      children: [

                        Text(
                          'Low-End Performance Mode',

                          style: TextStyle(
                            fontSize: 16,
                            fontWeight:
                                FontWeight.w600,
                            color: textColor,
                          ),
                        ),

                        const SizedBox(height: 3),

                        Text(
                          'Smoother Home page on low-end devices',

                          style: TextStyle(
                            fontSize: 12,
                            color: isDarkMode
                                ? Colors.white60
                                : Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  Switch(
                    value: isPerf,

                    activeColor:
                        Colors.lightBlueAccent,

                    onChanged: (value) {
                      setHomePerformanceMode(
                        value,
                      );

                      // Save the selection so it survives
                      // a full app restart.
                      _savePerformanceMode(value);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // =====================================================
  // DROPDOWN ITEM HELPER
  // =====================================================

  DropdownMenuItem<HomeBgChoice> _bgItem(
    HomeBgChoice value,
    IconData icon,
    String label,
  ) {
    return DropdownMenuItem<HomeBgChoice>(
      value: value,

      child: Row(
        children: [

          Icon(
            icon,
            size: 20,
            color: Colors.white70,
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // QUALITY DROPDOWN ITEM HELPER
  // =====================================================

  DropdownMenuItem<HomeBgQuality> _qualityItem(
    HomeBgQuality value,
    IconData icon,
    String label,
  ) {
    return DropdownMenuItem<HomeBgQuality>(
      value: value,

      child: Row(
        children: [

          Icon(
            icon,
            size: 20,
            color: Colors.white70,
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // REFRESH RATE DROPDOWN ITEM HELPER
  // =====================================================

  DropdownMenuItem<Duration> _refreshItem(
    Duration value,
    IconData icon,
    String label,
  ) {
    return DropdownMenuItem<Duration>(
      value: value,

      child: Row(
        children: [

          Icon(
            icon,
            size: 20,
            color: Colors.white70,
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

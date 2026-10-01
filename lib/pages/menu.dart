import 'package:flutter/material.dart';
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

// MenuTab is now a StatefulWidget so the Home Background card
// can remember whether it is expanded or collapsed.
class MenuTab extends StatefulWidget {
  const MenuTab({super.key});

  @override
  State<MenuTab> createState() => _MenuTabState();
}

class _MenuTabState extends State<MenuTab> {
  // Whether the Home Background card is expanded (dropdowns visible).
  bool _bgExpanded = false;

  // Whether the Dashboard Refresh Rate card is expanded.
  bool _refreshExpanded = false;

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
                    // HOME BACKGROUND (DEMO SELECTOR)
                    // =================================================

                    _buildBackgroundSelectorCard(
                      isDarkMode: isDarkMode,
                      cardColor: cardColor,
                      textColor: textColor,
                    ),

                    const SizedBox(height: 14),

                    // =================================================
                    // DASHBOARD REFRESH RATE
                    // =================================================

                    _buildRefreshRateCard(
                      isDarkMode: isDarkMode,
                      cardColor: cardColor,
                      textColor: textColor,
                    ),

                    const SizedBox(height: 14),

                    // =================================================
                    // WATER EFFECTS (LITE MODE SWITCH)
                    // =================================================

                    _buildWaterLiteCard(
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
  // HOME BACKGROUND SELECTOR CARD
  // =====================================================
  //
  // Same look as the other menu cards: icon, title, subtitle and
  // a ">" arrow on the right. Tapping the header expands the card
  // (the arrow rotates down) and reveals the dropdowns. Default =
  // live weather from the API; the other options force a
  // background for demo purposes.
  //
  // A second dropdown below it selects the background quality
  // (High / Low-end device).

  Widget _buildBackgroundSelectorCard({
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
          // HEADER (TAP TO EXPAND / COLLAPSE)
          // =================================================

          Material(
            color: Colors.transparent,

            child: InkWell(
              borderRadius:
                  BorderRadius.circular(20),

              onTap: () {
                setState(() {
                  _bgExpanded = !_bgExpanded;
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
                        Icons.wallpaper_rounded,
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
                            'Home Background',

                            style: TextStyle(
                              fontSize: 17,
                              fontWeight:
                                  FontWeight.w600,
                              color: textColor,
                            ),
                          ),

                          const SizedBox(height: 4),

                          Text(
                            'Choose the weather shown on Home',

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
                    // ARROW (ROTATES WHEN EXPANDED)
                    // =========================================

                    AnimatedRotation(
                      turns: _bgExpanded ? 0.25 : 0.0,

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
          // EXPANDABLE DROPDOWN AREA
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
                      18,
                      0,
                      18,
                      18,
                    ),

                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,

                      children: [

                        // =================================================
                        // DROPDOWN
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
                                    const Color(0xFF383838),

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
                                    fontWeight: FontWeight.w500,
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

                                    homeBgChoice.value = value;
                                  },
                                ),
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 18),

                        // =================================================
                        // QUALITY LABEL
                        // =================================================

                        Text(
                          'Background Quality',

                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
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
                          valueListenable: homeBgQuality,

                          builder: (context, quality, _) {
                            return Container(
                              width: double.infinity,

                              padding:
                                  const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 4,
                              ),

                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFF383838),

                                borderRadius:
                                    BorderRadius.circular(14),

                                border: Border.all(
                                  color: Colors.white
                                      .withOpacity(0.12),
                                ),
                              ),

                              child:
                                  DropdownButtonHideUnderline(
                                child: DropdownButton<
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
                                    fontWeight: FontWeight.w500,
                                  ),

                                  items: [
                                    _qualityItem(
                                      HomeBgQuality.high,
                                      Icons.high_quality_rounded,
                                      'High (Detailed animations)',
                                    ),
                                    _qualityItem(
                                      HomeBgQuality.low,
                                      Icons.speed_rounded,
                                      'Low (Low-end device friendly)',
                                    ),
                                  ],

                                  onChanged: (value) {
                                    if (value == null) return;

                                    homeBgQuality.value = value;
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
  // DASHBOARD REFRESH RATE CARD
  // =====================================================
  //
  // Same look as the Home Background card. Tapping the header
  // expands it and reveals a dropdown. The selected value is sent
  // to the Home tab through setHomeRefreshRate(), which controls
  // how often the dashboard info (temperature, humidity, water
  // level, flood risk status) changes on screen. The original
  // data refresh rate is not affected.
  //
  // Real-time = original behavior (no limit).

  Widget _buildRefreshRateCard({
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
          // HEADER (TAP TO EXPAND / COLLAPSE)
          // =================================================

          Material(
            color: Colors.transparent,

            child: InkWell(
              borderRadius:
                  BorderRadius.circular(20),

              onTap: () {
                setState(() {
                  _refreshExpanded = !_refreshExpanded;
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
                        Icons.update_rounded,
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
                            'Dashboard Refresh Rate',

                            style: TextStyle(
                              fontSize: 17,
                              fontWeight:
                                  FontWeight.w600,
                              color: textColor,
                            ),
                          ),

                          const SizedBox(height: 4),

                          Text(
                            'Choose how often Home info updates',

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
                    // ARROW (ROTATES WHEN EXPANDED)
                    // =========================================

                    AnimatedRotation(
                      turns: _refreshExpanded ? 0.25 : 0.0,

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
          // EXPANDABLE DROPDOWN AREA
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
                      18,
                      0,
                      18,
                      18,
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

                        // =================================================
                        // REFRESH RATE DROPDOWN
                        // =================================================

                        ValueListenableBuilder<Duration>(
                          valueListenable: homeRefreshInterval,

                          builder: (context, interval, _) {
                            return Container(
                              width: double.infinity,

                              padding:
                                  const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 4,
                              ),

                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFF383838),

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
                                    fontWeight: FontWeight.w500,
                                  ),

                                  items: [
                                    _refreshItem(
                                      Duration.zero,
                                      Icons.bolt_rounded,
                                      'Real-time (Default)',
                                    ),
                                    _refreshItem(
                                      const Duration(seconds: 30),
                                      Icons.timer_outlined,
                                      'Every 30 seconds',
                                    ),
                                    _refreshItem(
                                      const Duration(minutes: 1),
                                      Icons.timer_outlined,
                                      'Every 1 minute',
                                    ),
                                    _refreshItem(
                                      const Duration(minutes: 5),
                                      Icons.timer_outlined,
                                      'Every 5 minutes',
                                    ),
                                  ],

                                  onChanged: (value) {
                                    if (value == null) return;

                                    setHomeRefreshRate(value);
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
  // WATER EFFECTS CARD (LITE MODE SWITCH)
  // =====================================================
  //
  // Same look as the other menu cards, with a switch on the
  // right instead of an arrow. The switch is bound directly to
  // homeWaterLite (defined in home.dart):
  //
  //   OFF (default) = waving water + floating rubber duck.
  //   ON            = straight water surface, no waves, no duck
  //                   (stops the wave animation completely, so it
  //                   is much lighter on low-end devices).
  //
  // Tapping anywhere on the card toggles the switch.

  Widget _buildWaterLiteCard({
    required bool isDarkMode,
    required Color cardColor,
    required Color textColor,
  }) {
    return ValueListenableBuilder<bool>(
      valueListenable: homeWaterLite,

      builder: (context, isLite, _) {
        return Material(
          color: Colors.transparent,

          child: InkWell(
            borderRadius: BorderRadius.circular(20),

            onTap: () {
              setHomeWaterLiteMode(!isLite);
            },

            child: Container(
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
                      Icons.waves_rounded,
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
                          'Water Lite Mode',

                          style: TextStyle(
                            fontSize: 17,
                            fontWeight:
                                FontWeight.w600,
                            color: textColor,
                          ),
                        ),

                        const SizedBox(height: 4),

                        Text(
                          'Straight water, no waves or rubber duck',

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

                  const SizedBox(width: 8),

                  Switch(
                    value: isLite,

                    activeColor: Colors.lightBlueAccent,

                    onChanged: (value) {
                      setHomeWaterLiteMode(value);
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
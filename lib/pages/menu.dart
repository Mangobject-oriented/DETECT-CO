import 'package:flutter/material.dart';
import 'package:detectco/main.dart';

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

class MenuTab extends StatelessWidget {
  const MenuTab({super.key});

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
                    // HOME BACKGROUND (DEMO SELECTOR)
                    // =================================================

                    _buildBackgroundSelectorCard(
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
  // Same look as the other menu cards, but instead of an arrow
  // it contains a dropdown. Default = live weather from the API;
  // the other options force a background for demo purposes.

  Widget _buildBackgroundSelectorCard({
    required bool isDarkMode,
    required Color cardColor,
    required Color textColor,
  }) {
    return Container(
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

      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [

          // =================================================
          // ICON + TEXT
          // =================================================

          Row(
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
            ],
          ),

          const SizedBox(height: 16),

          // =================================================
          // DROPDOWN
          // =================================================

          ValueListenableBuilder<HomeBgChoice>(
            valueListenable: homeBgChoice,

            builder: (context, choice, _) {
              return Container(
                width: double.infinity,

                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),

                decoration: BoxDecoration(
                  color: const Color(0xFF383838),

                  borderRadius:
                      BorderRadius.circular(14),

                  border: Border.all(
                    color: Colors.white
                        .withOpacity(0.12),
                  ),
                ),

                child: DropdownButtonHideUnderline(
                  child: DropdownButton<HomeBgChoice>(
                    value: choice,
                    isExpanded: true,

                    borderRadius:
                        BorderRadius.circular(14),

                    dropdownColor:
                        const Color(0xFF303030),

                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
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
        ],
      ),
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
}
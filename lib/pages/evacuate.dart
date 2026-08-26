import 'package:flutter/material.dart';

import 'package:detectco/main.dart'; // for isDarkModeNotifier
import 'package:detectco/pages/survival_kit_prep.dart';
import 'package:detectco/pages/during_after_flood.dart';

class EvacuateTab extends StatelessWidget {
  const EvacuateTab({super.key});

  // =====================================================
  // FLOATING BURGER MENU
  // =====================================================

  void _showMenu(BuildContext menuContext, bool isDarkMode) {
    final RenderBox button =
        menuContext.findRenderObject() as RenderBox;

    final RenderBox overlay =
        Overlay.of(menuContext).context.findRenderObject() as RenderBox;

    final Offset position = button.localToGlobal(
      Offset.zero,
      ancestor: overlay,
    );

    showMenu<String>(
      context: menuContext,
      position: RelativeRect.fromLTRB(
        position.dx - 155,
        position.dy + 48,
        overlay.size.width - position.dx - button.size.width,
        0,
      ),
      color: isDarkMode ? const Color(0xFF303030) : Colors.white,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      items: [
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
      if (value == 'how_to_use') {
        // TODO
      }

      if (value == 'terms') {
        // TODO
      }

      if (value == 'about') {
        // TODO
      }
    });
  }

  // =====================================================
  // SECTION TITLE
  // =====================================================

  Widget _sectionTitle(
    String title,
    bool isDarkMode,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        top: 28,
        bottom: 18,
      ),
      child: Center(
        child: Text(
          title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: isDarkMode
                ? Colors.white
                : const Color(0xFF1D2B4A),
          ),
        ),
      ),
    );
  }

  // =====================================================
  // EVACUATION CENTER CARD
  // =====================================================

  Widget _evacuationCard(
    String name,
    String distance,
    bool isDarkMode,
  ) {
    return Container(
      height: 72,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF303030)
            : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 8,
            offset: const Offset(4, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          // GREEN LOCATION BOX
          Container(
            width: 50,
            height: double.infinity,
            color: Colors.green,
            child: const Icon(
              Icons.location_on,
              color: Colors.white,
              size: 30,
            ),
          ),

          const SizedBox(width: 14),

          // CENTER NAME
          Expanded(
            child: Text(
              name,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isDarkMode
                    ? Colors.white
                    : const Color(0xFF1D2B4A),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // DISTANCE
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(
              distance,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF8194BB),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // EMERGENCY NUMBER CARD
  // =====================================================

  Widget _emergencyCard(
    String number,
    String description,
    bool isDarkMode,
  ) {
    return Container(
      height: 72,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF303030)
            : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 8,
            offset: const Offset(4, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          // RED PHONE BOX
          Container(
            width: 50,
            height: double.infinity,
            color: const Color(0xFFFF3035),
            child: const Icon(
              Icons.phone,
              color: Colors.white,
              size: 30,
            ),
          ),

          const SizedBox(width: 14),

          // PHONE NUMBER
          Expanded(
            child: Text(
              number,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isDarkMode
                    ? Colors.white
                    : const Color(0xFF1D2B4A),
              ),
            ),
          ),

          // DESCRIPTION
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Text(
              description,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF8194BB),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // FLOOD PREPARATION CARD
  // =====================================================

  Widget _guideCard(
    String title,
    bool isDarkMode,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 72,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: isDarkMode
              ? const Color(0xFF303030)
              : Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.20),
              blurRadius: 8,
              offset: const Offset(4, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            // BLUE ICON BOX
            Container(
              width: 50,
              height: double.infinity,
              color: const Color(0xFF2867F5),
              child: const Icon(
                Icons.shield,
                color: Colors.white,
                size: 30,
              ),
            ),

            const SizedBox(width: 14),

            // TITLE
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode
                      ? Colors.white
                      : const Color(0xFF1D2B4A),
                ),
              ),
            ),

            // READ
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Text(
                'Read »',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF8194BB),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDarkModeNotifier,
      builder: (context, isDarkMode, child) {
        return Scaffold(
          backgroundColor:
              isDarkMode ? const Color(0xFF212121) : Colors.white,

          body: Column(
            children: [
              // =================================================
              // HEADER
              // =================================================

              Container(
                width: double.infinity,
                color: isDarkMode
                    ? const Color(0xFF212121)
                    : const Color.fromARGB(255, 72, 119, 247),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        // LOGO
                        GestureDetector(
                          onDoubleTap: () {
                            isDarkModeNotifier.value =
                                !isDarkModeNotifier.value;
                          },
                          child: SizedBox(
                            width: 50,
                            height: 50,
                            child: Image.asset(
                              "assets/icon/detect-co_logo.png",
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

                        // APP NAME
                        const Text(
                          'DETECT-CO',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),

                        const Spacer(),

                        // NOTIFICATION
                        IconButton(
                          icon: const Icon(
                            Icons.notifications_none,
                            color: Colors.white,
                            size: 26,
                          ),
                          onPressed: () {},
                        ),

                        // BURGER MENU
                        Builder(
                          builder: (menuContext) {
                            return IconButton(
                              icon: const Icon(
                                Icons.menu,
                                color: Colors.white,
                                size: 26,
                              ),
                              onPressed: () {
                                _showMenu(
                                  menuContext,
                                  isDarkMode,
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // =================================================
              // PAGE CONTENT
              // =================================================

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 8,
                  ),
                  child: Column(
                    children: [
                      // =================================================
                      // EVACUATION CENTERS
                      // =================================================

                      _sectionTitle(
                        'EVACUATION CENTERS',
                        isDarkMode,
                      ),

                      _evacuationCard(
                        'Lingga Elementary School',
                        '-- km',
                        isDarkMode,
                      ),

                      _evacuationCard(
                        'Uwisan Barangay Hall',
                        '-- km',
                        isDarkMode,
                      ),

                      _evacuationCard(
                        'Palingon Elementary School',
                        '-- km',
                        isDarkMode,
                      ),

                      // =================================================
                      // EMERGENCY NUMBERS
                      // =================================================

                      _sectionTitle(
                        'EMERGENCY NUMBERS',
                        isDarkMode,
                      ),

                      _emergencyCard(
                        '911',
                        'Emergency Hotline',
                        isDarkMode,
                      ),

                      _emergencyCard(
                        '09xx-xxx-xxxx',
                        'Calamba CDRRMO',
                        isDarkMode,
                      ),

                      _emergencyCard(
                        '09xx-xxx-xxxx',
                        'Uwisan Health Center',
                        isDarkMode,
                      ),

                      // =================================================
                      // FLOOD PREPARATION GUIDES
                      // =================================================

                      _sectionTitle(
                        'FLOOD PREPARATION GUIDES',
                        isDarkMode,
                      ),

                      // SURVIVAL KIT PREPARATION
                      _guideCard(
                        'Survival Kit Preparation',
                        isDarkMode,
                        () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const SurvivalKitPreparation(),
                            ),
                          );
                        },
                      ),

                      // DURING AND AFTER FLOOD
                      _guideCard(
                        'During and After Flood',
                        isDarkMode,
                        () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const DuringAfterFlood(),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 20),
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
}
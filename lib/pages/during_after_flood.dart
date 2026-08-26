import 'package:flutter/material.dart';

import 'package:detectco/main.dart'; // for isDarkModeNotifier

class DuringAfterFlood extends StatelessWidget {
  const DuringAfterFlood({super.key});

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
      child: Align(
        alignment: Alignment.centerLeft,
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
  // GUIDE ITEM
  // =====================================================

  Widget _guideItem(
    IconData icon,
    String text,
    bool isDarkMode,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: 18,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ICON
          SizedBox(
            width: 50,
            child: Icon(
              icon,
              color: const Color(0xFF4F7FF7),
              size: 25,
            ),
          ),

          const SizedBox(width: 10),

          // TEXT
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 17,
                height: 1.45,
                color: isDarkMode
                    ? Colors.white
                    : const Color(0xFF1D2B4A),
              ),
            ),
          ),
        ],
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
          backgroundColor: isDarkMode
              ? const Color(0xFF212121)
              : Colors.white,

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

                  child: SizedBox(
                    height: 70,

                    child: Row(
                      children: [
                        // BACK BUTTON
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_back_ios,
                            color: Colors.white,
                            size: 20,
                          ),

                          onPressed: () {
                            Navigator.pop(context);
                          },
                        ),

                        const SizedBox(width: 8),

                        // TITLE
                        const Expanded(
                          child: Text(
                            'During and After Flood',

                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),

                            overflow: TextOverflow.ellipsis,
                          ),
                        ),

                        const SizedBox(width: 16),
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
                    horizontal: 36,
                    vertical: 8,
                  ),

                  child: Column(
                    children: [
                      // =================================================
                      // ACTION
                      // =================================================

                      _sectionTitle(
                        'Action',
                        isDarkMode,
                      ),

                      _guideItem(
                        Icons.exit_to_app,
                        'Evacuate immediately',
                        isDarkMode,
                      ),

                      _guideItem(
                        Icons.water_damage,
                        'Refrain from walking through floodwaters barefoot',
                        isDarkMode,
                      ),

                      _guideItem(
                        Icons.directions_car,
                        'Avoid driving through moving water',
                        isDarkMode,
                      ),

                      _guideItem(
                        Icons.warning,
                        'Turn off electrical appliances, LPG tanks, and main power switch as necessary',
                        isDarkMode,
                      ),

                      // =================================================
                      // RECOVERY
                      // =================================================

                      _sectionTitle(
                        'Recovery',
                        isDarkMode,
                      ),

                      _guideItem(
                        Icons.home,
                        'Return home only when it’s safe according to local authorities',
                        isDarkMode,
                      ),

                      _guideItem(
                        Icons.search,
                        'Inspect for structural damage, gas leaks, and electrical systems while wearing protective clothing',
                        isDarkMode,
                      ),

                      _guideItem(
                        Icons.coronavirus,
                        'Avoid floodwater contact which can be contaminated with sewage, chemicals, and bacteria',
                        isDarkMode,
                      ),

                      _guideItem(
                        Icons.delete,
                        'Discard contaminated items such as food, medicines, or bottled water that may have come into contact with floodwater',
                        isDarkMode,
                      ),

                      const SizedBox(
                        height: 20,
                      ),
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
import 'package:flutter/material.dart';
import 'package:detectco/main.dart';

class SurvivalKitPreparation extends StatelessWidget {
  const SurvivalKitPreparation({super.key});

  // =====================================================
  // SURVIVAL KIT ITEM
  // =====================================================

  Widget _kitItem(
    String iconPath,
    String title,
    bool isDarkMode,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 50,
            child: Image.asset(
              iconPath,
              width: 40,
              height: 40,
              fit: BoxFit.contain,
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 17,
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

                // HEADER CHANGES WITH DARK MODE
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
                          icon: Icon(
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
                            'Survival Kit Preparation',

                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
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
              // CONTENT
              // =================================================

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 35,
                    vertical: 25,
                  ),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // PAGE TITLE
                      Text(
                        'What should your survival kit include?',

                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode
                              ? Colors.white
                              : const Color(0xFF1D2B4A),
                        ),
                      ),

                      const SizedBox(height: 25),

                      // =================================================
                      // ITEMS
                      // =================================================

                      _kitItem(
                        'assets/icon/water.png',
                        'Water, one gallon per person',
                        isDarkMode,
                      ),

                      _kitItem(
                        'assets/icon/food.png',
                        'Food, non-perishable, easy-to-prepare items',
                        isDarkMode,
                      ),

                      _kitItem(
                        'assets/icon/flashlight.png',
                        'Flashlights',
                        isDarkMode,
                      ),

                      _kitItem(
                        'assets/icon/first_aid.png',
                        'First aid kits',
                        isDarkMode,
                      ),

                      _kitItem(
                        'assets/icon/medic.png',
                        'Medications and medical items',
                        isDarkMode,
                      ),

                      _kitItem(
                        'assets/icon/sanitation.png',
                        'Sanitation and personal hygiene',
                        isDarkMode,
                      ),

                      _kitItem(
                        'assets/icon/docu.png',
                        'Personal documents',
                        isDarkMode,
                      ),

                      _kitItem(
                        'assets/icon/phone.png',
                        'Phone with chargers for communication',
                        isDarkMode,
                      ),

                      _kitItem(
                        'assets/icon/cash.png',
                        'Extra cash',
                        isDarkMode,
                      ),

                      _kitItem(
                        'assets/icon/blankets.png',
                        'Blankets and other comforts',
                        isDarkMode,
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
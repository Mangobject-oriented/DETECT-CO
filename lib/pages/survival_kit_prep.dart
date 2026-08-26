import 'package:flutter/material.dart';
import 'package:detectco/main.dart';

class SurvivalKitPreparation extends StatelessWidget {
  const SurvivalKitPreparation({super.key});

  // =====================================================
  // SURVIVAL KIT ITEM
  // =====================================================

  Widget _kitItem(
    IconData icon,
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
            child: Icon(
              icon,
              size: 25,
              color: const Color(0xFF4F7FF7),
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
                        Icons.water_drop,
                        'Water, one gallon per person',
                        isDarkMode,
                      ),

                      _kitItem(
                        Icons.shopping_basket,
                        'Food, non-perishable, easy-to-prepare items',
                        isDarkMode,
                      ),

                      _kitItem(
                        Icons.flashlight_on,
                        'Flashlights',
                        isDarkMode,
                      ),

                      _kitItem(
                        Icons.medical_services,
                        'First aid kits',
                        isDarkMode,
                      ),

                      _kitItem(
                        Icons.medication,
                        'Medications and medical items',
                        isDarkMode,
                      ),

                      _kitItem(
                        Icons.cleaning_services,
                        'Sanitation and personal hygiene',
                        isDarkMode,
                      ),

                      _kitItem(
                        Icons.description,
                        'Personal documents',
                        isDarkMode,
                      ),

                      _kitItem(
                        Icons.phone_android,
                        'Phone with chargers for communication',
                        isDarkMode,
                      ),

                      _kitItem(
                        Icons.account_balance_wallet,
                        'Extra cash',
                        isDarkMode,
                      ),

                      _kitItem(
                        Icons.bed,
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
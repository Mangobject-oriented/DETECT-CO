
import 'package:flutter/material.dart';
import 'package:detectco/main.dart';

class MenuTab extends StatelessWidget {
  const MenuTab({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDarkModeNotifier,
      builder: (context, isDarkMode, child) {
        final Color backgroundColor = isDarkMode
            ? const Color(0xFF212121)
            : Colors.white;

        final Color headerColor = isDarkMode
            ? const Color(0xFF212121)
            : const Color.fromARGB(
                255,
                72,
                119,
                247,
              );

        final Color cardColor = isDarkMode
            ? const Color(0xFF2C2C2C)
            : Colors.white;

        final Color textColor = isDarkMode
            ? Colors.white
            : const Color(0xFF1D2B4A);

        final Color secondaryColor = isDarkMode
            ? Colors.white70
            : Colors.grey.shade600;

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

                      GestureDetector(
                        onDoubleTap: () async {
                          // Toggle dark mode
                          isDarkModeNotifier.value =
                              !isDarkModeNotifier.value;
                        },

                        child: SizedBox(
                          width: 50,
                          height: 50,

                          child: Image.asset(
                            'assets/icon/detect-co_logo.png',
                          ),
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
                        // DARK MODE
                        // =================================================

                        Material(
                          color: Colors.transparent,

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
                                    isDarkMode
                                        ? Icons.dark_mode_rounded
                                        : Icons.light_mode_rounded,

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
                                        'Dark Mode',

                                        style: TextStyle(
                                          fontSize: 17,
                                          fontWeight:
                                              FontWeight.w600,
                                          color: textColor,
                                        ),
                                      ),

                                      const SizedBox(height: 4),

                                      Text(
                                        isDarkMode
                                            ? 'Dark appearance is enabled'
                                            : 'Use a darker appearance',

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
                                // TOGGLE
                                // =================================================

                                Switch(
                                  value: isDarkMode,

                                  onChanged: (value) {
                                    isDarkModeNotifier.value = value;
                                  },

                                  activeColor:
                                      const Color(0xFF4877F7),
                                ),
                              ],
                            ),
                          ),
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
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
}

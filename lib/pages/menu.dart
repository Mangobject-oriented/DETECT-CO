import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:detectco/pages/home.dart';
import 'package:detectco/services/ml_api_connection.dart';

// =====================================================
// HOME BACKGROUND CHOICE
// =====================================================

enum HomeBgChoice { auto, storm, rain, cloudy, sunny }

final ValueNotifier<HomeBgChoice> homeBgChoice = ValueNotifier<HomeBgChoice>(
  HomeBgChoice.auto,
);

// =====================================================
// HOME BACKGROUND QUALITY
// =====================================================

enum HomeBgQuality { high, low }

final ValueNotifier<HomeBgQuality> homeBgQuality = ValueNotifier<HomeBgQuality>(
  HomeBgQuality.high,
);

// =====================================================
// MENU SETTINGS STORAGE
// =====================================================

const String _homeBgChoiceKey = 'home_bg_choice';
const String _homeBgQualityKey = 'home_bg_quality';
const String _homeRefreshRateKey = 'home_refresh_rate';
const String _homeWaterLiteKey = 'home_water_lite';
const String _homePerformanceModeKey = 'home_performance_mode';

// =====================================================
// MENU TAB
// =====================================================

class MenuTab extends StatefulWidget {
  const MenuTab({super.key});

  @override
  State<MenuTab> createState() => _MenuTabState();
}

class _MenuTabState extends State<MenuTab> {
  bool _displaySettingsExpanded = false;
  bool _bgExpanded = false;
  bool _refreshExpanded = false;

  // Prevents multiple popup menus from being opened
  // at the same time.
  bool _isSelectMenuOpen = false;

  static const List<Duration> _refreshOptions = [
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(minutes: 1),
    Duration(minutes: 5),
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedDisplaySettings();
  }

  // ============================================================
  // LOAD SETTINGS
  // ============================================================

  Future<void> _loadSavedDisplaySettings() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) {
      return;
    }

    final savedBg = prefs.getString(_homeBgChoiceKey);
    final savedQuality = prefs.getString(_homeBgQualityKey);
    final savedRefreshRate = prefs.getInt(_homeRefreshRateKey);
    final savedWaterLite = prefs.getBool(_homeWaterLiteKey);
    final savedPerformanceMode = prefs.getBool(_homePerformanceModeKey);

    if (savedBg != null) {
      HomeBgChoice? bg;

      for (final value in HomeBgChoice.values) {
        if (value.name == savedBg) {
          bg = value;
          break;
        }
      }

      if (bg != null) {
        homeBgChoice.value = bg;
      }
    }

    if (savedQuality != null) {
      HomeBgQuality? quality;

      for (final value in HomeBgQuality.values) {
        if (value.name == savedQuality) {
          quality = value;
          break;
        }
      }

      if (quality != null) {
        homeBgQuality.value = quality;
      }
    }

    if (savedRefreshRate != null) {
      setHomeRefreshRate(Duration(seconds: savedRefreshRate));
    }

    if (savedWaterLite != null) {
      setHomeWaterLiteMode(savedWaterLite);
    }

    if (savedPerformanceMode != null) {
      setHomePerformanceMode(savedPerformanceMode);
    }

    if (mounted) {
      setState(() {});
    }
  }

  // ============================================================
  // SAVE SETTINGS
  // ============================================================

  Future<void> _saveHomeBgChoice(HomeBgChoice choice) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_homeBgChoiceKey, choice.name);
  }

  Future<void> _saveHomeBgQuality(HomeBgQuality quality) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(_homeBgQualityKey, quality.name);
  }

  Future<void> _saveRefreshRate(Duration duration) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt(_homeRefreshRateKey, duration.inSeconds);
  }

  Future<void> _saveWaterLite(bool value) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_homeWaterLiteKey, value);
  }

  Future<void> _savePerformanceMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_homePerformanceModeKey, value);
  }

  // ============================================================
  // LABELS AND ICONS
  // ============================================================

  String _bgLabel(HomeBgChoice choice) {
    switch (choice) {
      case HomeBgChoice.auto:
        return 'Default (Live weather from API)';

      case HomeBgChoice.storm:
        return 'Storm';

      case HomeBgChoice.rain:
        return 'Rain';

      case HomeBgChoice.cloudy:
        return 'Cloudy';

      case HomeBgChoice.sunny:
        return 'Sunny';
    }
  }

  IconData _bgIcon(HomeBgChoice choice) {
    switch (choice) {
      case HomeBgChoice.auto:
        return Icons.cloud_sync_rounded;

      case HomeBgChoice.storm:
        return Icons.thunderstorm_rounded;

      case HomeBgChoice.rain:
        return Icons.water_drop_rounded;

      case HomeBgChoice.cloudy:
        return Icons.cloud_rounded;

      case HomeBgChoice.sunny:
        return Icons.wb_sunny_rounded;
    }
  }

  String _qualityLabel(HomeBgQuality quality) {
    switch (quality) {
      case HomeBgQuality.high:
        return 'High (Detailed animations)';

      case HomeBgQuality.low:
        return 'Low (Low-end device friendly)';
    }
  }

  IconData _qualityIcon(HomeBgQuality quality) {
    switch (quality) {
      case HomeBgQuality.high:
        return Icons.high_quality_rounded;

      case HomeBgQuality.low:
        return Icons.speed_rounded;
    }
  }

  String _refreshLabel(Duration duration) {
    if (duration == Duration.zero) {
      return 'Real-time (Default)';
    }

    if (duration.inSeconds < 60) {
      return 'Every ${duration.inSeconds} seconds';
    }

    final minutes = duration.inMinutes;

    if (minutes == 1) {
      return 'Every 1 minute';
    }

    return 'Every $minutes minutes';
  }

  IconData _refreshIcon(Duration duration) {
    return duration == Duration.zero
        ? Icons.bolt_rounded
        : Icons.timer_outlined;
  }

  // ============================================================
  // GENERIC POPUP MENU
  //
  // SAFE VERSION
  //
  // The list order is NEVER changed.
  //
  // HomeBgChoice:
  // Auto
  // Storm
  // Rain
  // Cloudy
  // Sunny
  //
  // ============================================================

  Future<T?> _openSelectMenu<T>({
    required BuildContext fieldContext,
    required List<T> values,
    required T current,
    required IconData Function(T) iconOf,
    required String Function(T) labelOf,
  }) async {
    // ----------------------------------------------------------
    // Don't allow two menus to open at the same time.
    // ----------------------------------------------------------

    if (_isSelectMenuOpen) {
      return null;
    }

    if (!mounted) {
      return null;
    }

    _isSelectMenuOpen = true;

    try {
      // --------------------------------------------------------
      // Get the field RenderBox safely.
      // --------------------------------------------------------

      final RenderObject? fieldObject = fieldContext.findRenderObject();

      if (fieldObject == null || fieldObject is! RenderBox) {
        return null;
      }

      final RenderBox button = fieldObject;

      if (!button.hasSize) {
        return null;
      }

      // --------------------------------------------------------
      // Get the root overlay safely.
      // --------------------------------------------------------

      final OverlayState? overlayState = Overlay.maybeOf(
        fieldContext,
        rootOverlay: true,
      );

      if (overlayState == null) {
        return null;
      }

      final RenderObject? overlayObject = overlayState.context
          .findRenderObject();

      if (overlayObject == null || overlayObject is! RenderBox) {
        return null;
      }

      final RenderBox overlay = overlayObject;

      if (!overlay.hasSize) {
        return null;
      }

      // --------------------------------------------------------
      // Calculate position.
      // --------------------------------------------------------

      final Offset position = button.localToGlobal(
        Offset.zero,
        ancestor: overlay,
      );

      final double overlayWidth = overlay.size.width;

      final double overlayHeight = overlay.size.height;

      final double buttonWidth = button.size.width;

      final double buttonHeight = button.size.height;

      // --------------------------------------------------------
      // Make sure the position is valid.
      // --------------------------------------------------------

      if (!position.dx.isFinite ||
          !position.dy.isFinite ||
          !buttonWidth.isFinite ||
          !buttonHeight.isFinite) {
        return null;
      }

      // --------------------------------------------------------
      // Calculate horizontal position.
      // --------------------------------------------------------

      double left = position.dx;

      double right = overlayWidth - position.dx - buttonWidth;

      // Keep the popup inside the screen.
      if (left < 0) {
        left = 0;
      }

      if (right < 0) {
        right = 0;
      }

      // --------------------------------------------------------
      // Calculate vertical position.
      //
      // Normally it opens below the field.
      // --------------------------------------------------------

      double top = position.dy + buttonHeight + 4;

      if (top < 0) {
        top = 0;
      }

      if (top > overlayHeight) {
        top = overlayHeight - 10;
      }

      // --------------------------------------------------------
      // Open popup.
      // --------------------------------------------------------

      final T? selected = await showMenu<T>(
        context: fieldContext,
        useRootNavigator: true,
        color: const Color(0xFF303030),
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),

        // Keep popup the same width as the field.
        constraints: BoxConstraints(
          minWidth: buttonWidth,
          maxWidth: buttonWidth,
        ),

        position: RelativeRect.fromLTRB(left, top, right, 0),

        items: values.map((value) {
          return PopupMenuItem<T>(
            value: value,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(iconOf(value), size: 20, color: Colors.white70),

                const SizedBox(width: 10),

                Expanded(
                  child: Text(
                    labelOf(value),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                // --------------------------------------------
                // CHECK CURRENT ITEM
                // --------------------------------------------
                if (value == current)
                  const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
              ],
            ),
          );
        }).toList(),
      );

      return selected;
    } catch (error) {
      // --------------------------------------------------------
      // Prevent a popup/layout error from killing the app.
      // --------------------------------------------------------

      debugPrint('Menu dropdown error: $error');

      return null;
    } finally {
      // --------------------------------------------------------
      // Always unlock the dropdown.
      // --------------------------------------------------------

      _isSelectMenuOpen = false;
    }
  }

  // ============================================================
  // SELECT FIELD
  // ============================================================

  Widget _buildSelectField<T>({
    required T current,
    required List<T> values,
    required IconData Function(T) iconOf,
    required String Function(T) labelOf,
    required ValueChanged<T> onSelected,
  }) {
    return Builder(
      builder: (fieldContext) {
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF303030),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                if (_isSelectMenuOpen) {
                  return;
                }

                final T? selected = await _openSelectMenu<T>(
                  fieldContext: fieldContext,
                  values: values,
                  current: current,
                  iconOf: iconOf,
                  labelOf: labelOf,
                );

                if (!mounted) {
                  return;
                }

                if (selected != null) {
                  onSelected(selected);
                }
              },
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(iconOf(current), size: 20, color: Colors.white70),

                    const SizedBox(width: 10),

                    Expanded(
                      child: Text(
                        labelOf(current),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),

                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white70,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // =====================================================
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {
    const Color backgroundColor = Color(0xFF212121);

    const Color headerColor = Color(0xFF212121);

    const Color cardColor = Color(0xFF2C2C2C);

    const Color textColor = Colors.white;

    const Color secondaryColor = Colors.white70;

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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: headerColor,

              child: Row(
                children: [
                  SizedBox(
                    width: 50,
                    height: 50,
                    child: Image.asset('assets/icon/detect-co_logo.png'),
                  ),

                  const SizedBox(width: 8),

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
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),

                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    const Text(
                      'Menu',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),

                    const SizedBox(height: 6),

                    const Text(
                      'Manage and learn more about DETECT-CO',
                      style: TextStyle(fontSize: 14, color: secondaryColor),
                    ),

                    const SizedBox(height: 24),

                    // =================================================
                    // HOW TO USE
                    // =================================================
                    _buildMenuCard(
                      cardColor: cardColor,
                      icon: Icons.help_outline_rounded,
                      title: 'How to Use',
                      subtitle: 'Learn how to use DETECT-CO',
                      onTap: () {
                        // Open How to Use page
                      },
                    ),

                    const SizedBox(height: 14),

                    // =================================================
                    // TERMS OF SERVICE
                    // =================================================
                    _buildMenuCard(
                      cardColor: cardColor,
                      icon: Icons.description_outlined,
                      title: 'Terms of Service',
                      subtitle: 'Read the terms and conditions',
                      onTap: () {
                        // Open Terms of Service page
                      },
                    ),

                    const SizedBox(height: 14),

                    // =================================================
                    // ABOUT APP
                    // =================================================
                    _buildMenuCard(
                      cardColor: cardColor,
                      icon: Icons.info_outline_rounded,
                      title: 'About App',
                      subtitle: 'Learn more about DETECT-CO',
                      onTap: () {
                        // Open About App page
                      },
                    ),

                    const SizedBox(height: 14),

                    // =================================================
                    // DISPLAY SETTINGS
                    // =================================================
                    _buildDisplaySettingsCard(cardColor: cardColor),
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
    required Color cardColor,
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
          duration: const Duration(milliseconds: 250),

          width: double.infinity,

          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),

          decoration: BoxDecoration(
            color: cardColor,

            borderRadius: BorderRadius.circular(20),

            border: Border.all(color: Colors.grey.shade800),

            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 6,
                offset: const Offset(0, 4),
              ),
            ],
          ),

          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,

                decoration: BoxDecoration(
                  color: const Color(0xFF383838),
                  borderRadius: BorderRadius.circular(16),
                ),

                child: Icon(icon, size: 27, color: Colors.white),
              ),

              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),

              const Icon(
                Icons.chevron_right_rounded,
                size: 28,
                color: Colors.white54,
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

  Widget _buildDisplaySettingsCard({required Color cardColor}) {
    return Container(
      width: double.infinity,

      decoration: BoxDecoration(
        color: cardColor,

        borderRadius: BorderRadius.circular(20),

        border: Border.all(color: Colors.grey.shade800),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 6,
            offset: const Offset(0, 4),
          ),
        ],
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          // =================================================
          // DISPLAY SETTINGS HEADER
          // =================================================

          Material(
            color: Colors.transparent,

            child: InkWell(
              borderRadius: BorderRadius.circular(20),

              onTap: () {
                // Close any open menu before changing
                // the layout.
                if (_isSelectMenuOpen) {
                  return;
                }

                setState(() {
                  _displaySettingsExpanded = !_displaySettingsExpanded;
                });
              },

              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 18,
                ),

                child: Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,

                      decoration: BoxDecoration(
                        color: const Color(0xFF383838),
                        borderRadius: BorderRadius.circular(16),
                      ),

                      child: const Icon(
                        Icons.display_settings_rounded,
                        size: 27,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(width: 16),

                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          Text(
                            'Display Settings',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),

                          SizedBox(height: 4),

                          Text(
                            'Customize the Home display and performance',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ),

                    AnimatedRotation(
                      turns: _displaySettingsExpanded ? 0.25 : 0.0,

                      duration: const Duration(milliseconds: 250),

                      child: const Icon(
                        Icons.chevron_right_rounded,
                        size: 28,
                        color: Colors.white54,
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
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,

            child: _displaySettingsExpanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),

                    child: Column(
                      children: [
                        _buildBackgroundSelectorSection(),

                        const SizedBox(height: 12),

                        _buildRefreshRateSection(),

                        const SizedBox(height: 12),

                        _buildMlServerAddressSetting(),

                        const SizedBox(height: 12),

                        // =========================================
                        // WATER LITE MODE
                        // =========================================
                        ValueListenableBuilder<bool>(
                          valueListenable: homeWaterLite,
                          builder: (context, isLite, _) {
                            return _buildSwitchCard(
                              icon: Icons.waves_rounded,
                              title: 'Water Lite Mode',
                              subtitle:
                                  'Straight water, no waves or rubber duck',
                              value: isLite,
                              onChanged: (value) {
                                setHomeWaterLiteMode(value);

                                _saveWaterLite(value);
                              },
                            );
                          },
                        ),

                        const SizedBox(height: 12),

                        // =========================================
                        // LOW-END PERFORMANCE MODE
                        // =========================================
                        ValueListenableBuilder<bool>(
                          valueListenable: homePerformanceMode,
                          builder: (context, isPerf, _) {
                            return _buildSwitchCard(
                              icon: Icons.speed_rounded,
                              title: 'Low-End Performance Mode',
                              subtitle: 'Smoother Home page on low-end devices',
                              value: isPerf,
                              onChanged: (value) {
                                setHomePerformanceMode(value);

                                _savePerformanceMode(value);
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _buildMlServerAddressSetting() {
    return Material(
      color: const Color(0xFF383838),
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        leading: const Icon(Icons.wifi_tethering_rounded, color: Colors.white),
        title: const Text(
          'ML Server Address',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        subtitle: const Text(
          'Set the public HTTPS URL for ML forecasts',
          style: TextStyle(color: Colors.white60),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: Colors.white54,
        ),
        onTap: _editMlServerAddress,
      ),
    );
  }

  Future<void> _editMlServerAddress() async {
    final service = MlApiConnection.instance;
    final current = await service.manualUrl;
    if (!mounted) return;
    final controller = TextEditingController(text: current ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ML Server Address'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://your-public-ml-host/predict',
            helperText:
                'Leave empty to retry the shared URL, then use the app build URL.',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, ''),
            child: const Text('Clear URL'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) return;
    try {
      await service.saveManualUrl(value);
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  // =====================================================
  // EXPANDABLE SECTION CARD
  // =====================================================

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool expanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,

      decoration: BoxDecoration(
        color: const Color(0xFF383838),

        borderRadius: BorderRadius.circular(16),

        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          // =================================================
          // HEADER
          // =================================================

          Material(
            color: Colors.transparent,

            child: InkWell(
              borderRadius: BorderRadius.circular(16),

              onTap: () {
                if (_isSelectMenuOpen) {
                  return;
                }

                onToggle();
              },

              child: Padding(
                padding: const EdgeInsets.symmetric(
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
                        borderRadius: BorderRadius.circular(13),
                      ),

                      child: Icon(icon, size: 23, color: Colors.white),
                    ),

                    const SizedBox(width: 13),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,

                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),

                          const SizedBox(height: 3),

                          Text(
                            subtitle,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ),

                    AnimatedRotation(
                      turns: expanded ? 0.25 : 0.0,

                      duration: const Duration(milliseconds: 250),

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
          // OPTIONS
          // =================================================
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,

            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: child,
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // HOME BACKGROUND SECTION
  // =====================================================

  Widget _buildBackgroundSelectorSection() {
    return _buildSectionCard(
      icon: Icons.wallpaper_rounded,
      title: 'Home Background',
      subtitle: 'Choose the weather shown on Home',
      expanded: _bgExpanded,

      onToggle: () {
        setState(() {
          _bgExpanded = !_bgExpanded;
        });
      },

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          // =================================================
          // BACKGROUND CHOICE
          // =================================================

          ValueListenableBuilder<HomeBgChoice>(
            valueListenable: homeBgChoice,

            builder: (context, choice, _) {
              return _buildSelectField<HomeBgChoice>(
                current: choice,

                // IMPORTANT:
                // This keeps the original order.
                values: HomeBgChoice.values,

                iconOf: _bgIcon,
                labelOf: _bgLabel,

                onSelected: (value) {
                  homeBgChoice.value = value;

                  _saveHomeBgChoice(value);
                },
              );
            },
          ),

          const SizedBox(height: 14),

          // =================================================
          // QUALITY LABEL
          // =================================================
          const Text(
            'Background Quality',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),

          const SizedBox(height: 4),

          const Text(
            'Choose Low for smoother performance on low-end devices',
            style: TextStyle(fontSize: 12, color: Colors.white60),
          ),

          const SizedBox(height: 10),

          // =================================================
          // QUALITY CHOICE
          // =================================================
          ValueListenableBuilder<HomeBgQuality>(
            valueListenable: homeBgQuality,

            builder: (context, quality, _) {
              return _buildSelectField<HomeBgQuality>(
                current: quality,

                values: HomeBgQuality.values,

                iconOf: _qualityIcon,

                labelOf: _qualityLabel,

                onSelected: (value) {
                  homeBgQuality.value = value;

                  _saveHomeBgQuality(value);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // =====================================================
  // DASHBOARD REFRESH RATE SECTION
  // =====================================================

  Widget _buildRefreshRateSection() {
    return _buildSectionCard(
      icon: Icons.update_rounded,
      title: 'Dashboard Refresh Rate',
      subtitle: 'Choose how often Home info updates',

      expanded: _refreshExpanded,

      onToggle: () {
        setState(() {
          _refreshExpanded = !_refreshExpanded;
        });
      },

      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,

        children: [
          const Text(
            'Lower the refresh rate to reduce how often the dashboard changes',
            style: TextStyle(fontSize: 12, color: Colors.white60),
          ),

          const SizedBox(height: 10),

          ValueListenableBuilder<Duration>(
            valueListenable: homeRefreshInterval,

            builder: (context, interval, _) {
              final Duration selected = _refreshOptions.contains(interval)
                  ? interval
                  : const Duration(seconds: 30);

              return _buildSelectField<Duration>(
                current: selected,

                values: _refreshOptions,

                iconOf: _refreshIcon,

                labelOf: _refreshLabel,

                onSelected: (value) {
                  setHomeRefreshRate(value);

                  _saveRefreshRate(value);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  // =====================================================
  // SWITCH CARD
  // =====================================================

  Widget _buildSwitchCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Material(
      color: Colors.transparent,

      child: InkWell(
        borderRadius: BorderRadius.circular(16),

        onTap: () => onChanged(!value),

        child: Container(
          width: double.infinity,

          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),

          decoration: BoxDecoration(
            color: const Color(0xFF383838),

            borderRadius: BorderRadius.circular(16),

            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),

          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,

                decoration: BoxDecoration(
                  color: const Color(0xFF444444),
                  borderRadius: BorderRadius.circular(13),
                ),

                child: Icon(icon, size: 23, color: Colors.white),
              ),

              const SizedBox(width: 13),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              Switch(
                value: value,
                activeColor: Colors.lightBlueAccent,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

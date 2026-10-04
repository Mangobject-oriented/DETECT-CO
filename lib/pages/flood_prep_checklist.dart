
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:detectco/main.dart'; // for isDarkModeNotifier

class FloodPreparationChecklist extends StatefulWidget {
  const FloodPreparationChecklist({super.key});

  @override
  State<FloodPreparationChecklist> createState() =>
      _FloodPreparationChecklistState();
}

class _FloodPreparationChecklistState
    extends State<FloodPreparationChecklist> {
  static const String _storageKey =
      'detect_co_flood_preparation_checklist';

  // =====================================================
  // ANIME OVERLAY
  // =====================================================

  static const String _animeIdle =
      'assets/images/1anime.png';

  static const String _animeChecked =
      'assets/images/2anime.png';

  static const String _animeUnchecked =
      'assets/images/3anime.png';

  static const String _animeCompleted =
      'assets/images/4anime.png';

  String _currentAnime = _animeIdle;

  bool _showAnimeOverlay = false;

  Timer? _animeTimer;

  // =====================================================
  // CHECKLIST ITEMS
  // =====================================================

  final List<String> _beforeFloodItems = [
    'Monitor DETECT-CO flood alerts',
    'Monitor weather and rainfall updates',
    'Prepare drinking water',
    'Prepare ready-to-eat food',
    'Charge your phone',
    'Charge your power bank',
    'Prepare a flashlight',
    'Prepare a first-aid kit',
    'Prepare necessary medicines',
    'Secure important documents in waterproof packaging',
    'Prepare extra clothes',
    'Move important belongings to a higher location',
    'Identify the nearest evacuation center',
    'Inform family members about your evacuation plan',
  ];

  final List<String> _duringFloodItems = [
    'Stay alert for emergency announcements',
    'Move to higher ground if instructed',
    'Keep your emergency bag with you',
    'Avoid walking through moving floodwater',
    'Avoid driving through flooded roads',
    'Stay away from electrical wires and equipment exposed to water',
    'Follow instructions from local authorities',
    'Evacuate immediately when instructed',
  ];

  final List<String> _afterFloodItems = [
    'Wait for authorities to declare the area safe',
    'Avoid contaminated floodwater',
    'Avoid downed electrical wires',
    'Check family members',
    'Report emergencies or hazards',
    'Check your surroundings before returning home',
  ];

  final Set<String> _completedItems = {};

  bool _isLoading = true;

  // =====================================================
  // LOAD SAVED CHECKLIST
  // =====================================================

  @override
  void initState() {
    super.initState();
    _loadChecklist();
  }

  Future<void> _loadChecklist() async {
    try {
      final SharedPreferences prefs =
          await SharedPreferences.getInstance();

      final List<String> savedItems =
          prefs.getStringList(_storageKey) ?? [];

      if (!mounted) return;

      setState(() {
        _completedItems.addAll(savedItems);
        _isLoading = false;
      });

      // Keep the original idle state after loading.
      _currentAnime = _animeIdle;
      _showAnimeOverlay = false;
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });
    }
  }

  // =====================================================
  // SAVE CHECKLIST
  // =====================================================

  Future<void> _saveChecklist() async {
    try {
      final SharedPreferences prefs =
          await SharedPreferences.getInstance();

      await prefs.setStringList(
        _storageKey,
        _completedItems.toList(),
      );
    } catch (_) {
      // The checklist still works even if saving fails.
    }
  }

  // =====================================================
  // ANIME OVERLAY
  // =====================================================

  void _showAnime(String animeAsset) {
    if (!mounted) return;

    _animeTimer?.cancel();

    setState(() {
      _currentAnime = animeAsset;
      _showAnimeOverlay = true;
    });

    _animeTimer = Timer(
      const Duration(milliseconds: 1400),
      () {
        if (!mounted) return;

        setState(() {
          _showAnimeOverlay = false;
        });

        // Wait for the slide-out animation to finish
        // before returning to the idle image.
        Timer(
          const Duration(milliseconds: 400),
          () {
            if (!mounted) return;

            if (!_showAnimeOverlay) {
              setState(() {
                _currentAnime = _animeIdle;
              });
            }
          },
        );
      },
    );
  }

  // =====================================================
  // TOGGLE ITEM
  // =====================================================

  void _toggleItem(String item) {
    final bool wasCompleted =
        _completedItems.contains(item);

    setState(() {
      if (wasCompleted) {
        _completedItems.remove(item);
      } else {
        _completedItems.add(item);
      }
    });

    _saveChecklist();

    // -----------------------------------------------------
    // UNCHECKED ITEM
    // -----------------------------------------------------

    if (wasCompleted) {
      _showAnime(_animeUnchecked);
      return;
    }

    // -----------------------------------------------------
    // 100% COMPLETED
    // -----------------------------------------------------

    if (_completedCount >= _totalItems &&
        _totalItems > 0) {
      _showAnime(_animeCompleted);
      return;
    }

    // -----------------------------------------------------
    // CHECKED ITEM
    // -----------------------------------------------------

    _showAnime(_animeChecked);
  }

  // =====================================================
  // RESET CHECKLIST
  // =====================================================

  Future<void> _resetChecklist() async {
    final bool? shouldReset = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final bool isDarkMode =
            isDarkModeNotifier.value;

        return AlertDialog(
          backgroundColor: isDarkMode
              ? const Color(0xFF303030)
              : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Reset Checklist?',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDarkMode
                  ? Colors.white
                  : const Color(0xFF1D2B4A),
            ),
          ),
          content: Text(
            'All completed items will be unchecked.',
            style: TextStyle(
              color: isDarkMode
                  ? Colors.grey[300]
                  : const Color(0xFF5F6F8F),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text(
                'RESET',
                style: TextStyle(
                  color: Color(0xFFFF3035),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (shouldReset != true) return;

    _animeTimer?.cancel();

    setState(() {
      _completedItems.clear();
      _currentAnime = _animeIdle;
      _showAnimeOverlay = false;
    });

    await _saveChecklist();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(
              Icons.refresh_rounded,
              color: Colors.white,
            ),
            SizedBox(width: 10),
            Text('Checklist has been reset.'),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  // =====================================================
  // TOTAL ITEMS
  // =====================================================

  int get _totalItems =>
      _beforeFloodItems.length +
      _duringFloodItems.length +
      _afterFloodItems.length;

  int get _completedCount =>
      _completedItems.length;

  // =====================================================
  // PROGRESS HEADER
  // =====================================================

  Widget _progressHeader(bool isDarkMode) {
    final double progress = _totalItems == 0
        ? 0
        : _completedCount / _totalItems;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF303030)
            : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(3, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF2867F5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.checklist_rounded,
                  color: Colors.white,
                  size: 27,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Flood Preparation',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode
                            ? Colors.white
                            : const Color(0xFF1D2B4A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Be prepared before flooding occurs.',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDarkMode
                            ? Colors.grey[400]
                            : const Color(0xFF8194BB),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Progress',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode
                      ? Colors.white
                      : const Color(0xFF1D2B4A),
                ),
              ),
              Text(
                '$_completedCount / $_totalItems',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2867F5),
                ),
              ),
            ],
          ),

          const SizedBox(height: 9),

          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: isDarkMode
                  ? const Color(0xFF454545)
                  : const Color(0xFFE8ECF3),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(
                Color(0xFF2867F5),
              ),
            ),
          ),

          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton.icon(
              onPressed:
                  _completedCount == 0
                      ? null
                      : _resetChecklist,
              icon: const Icon(
                Icons.refresh_rounded,
                size: 18,
              ),
              label: const Text(
                'RESET CHECKLIST',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    const Color(0xFFFF3035),
                side: BorderSide(
                  color: _completedCount == 0
                      ? Colors.grey
                      : const Color(0xFFFF3035),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // CHECKLIST SECTION
  // =====================================================

  Widget _checklistSection(
    String title,
    String subtitle,
    List<String> items,
    bool isDarkMode,
    IconData icon,
  ) {
    final int sectionCompleted =
        items.where(
          (item) =>
              _completedItems.contains(item),
        ).length;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.fromLTRB(
        16,
        16,
        16,
        8,
      ),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF303030)
            : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(3, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF2867F5),
                  borderRadius:
                      BorderRadius.circular(13),
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 23,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight:
                            FontWeight.bold,
                        color: isDarkMode
                            ? Colors.white
                            : const Color(
                                0xFF1D2B4A,
                              ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDarkMode
                            ? Colors.grey[400]
                            : const Color(
                                0xFF8194BB,
                              ),
                      ),
                    ),
                  ],
                ),
              ),

              Container(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: sectionCompleted ==
                          items.length
                      ? Colors.green
                          .withOpacity(0.15)
                      : const Color(0xFF2867F5)
                          .withOpacity(0.12),
                  borderRadius:
                      BorderRadius.circular(10),
                ),
                child: Text(
                  '$sectionCompleted/${items.length}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        FontWeight.bold,
                    color: sectionCompleted ==
                            items.length
                        ? Colors.green
                        : const Color(
                            0xFF2867F5,
                          ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          ...items.map(
            (item) => _checklistItem(
              item,
              isDarkMode,
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // CHECKLIST ITEM
  // =====================================================

  Widget _checklistItem(
    String item,
    bool isDarkMode,
  ) {
    final bool isCompleted =
        _completedItems.contains(item);

    return InkWell(
      onTap: () => _toggleItem(item),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: 5,
        ),
        child: Row(
          crossAxisAlignment:
              CrossAxisAlignment.center,
          children: [
            Checkbox(
              value: isCompleted,
              onChanged: (_) {
                _toggleItem(item);
              },
              activeColor:
                  const Color(0xFF2867F5),
              shape: RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(5),
              ),
            ),

            const SizedBox(width: 2),

            Expanded(
              child: Text(
                item,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.3,
                  color: isCompleted
                      ? (isDarkMode
                          ? Colors.grey[500]
                          : Colors.grey[500])
                      : (isDarkMode
                          ? Colors.grey[200]
                          : const Color(
                              0xFF35415A,
                            )),
                  decoration: isCompleted
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                  decorationColor: isDarkMode
                      ? Colors.grey[500]
                      : Colors.grey[500],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // ANIME CHARACTER OVERLAY
  // =====================================================

  Widget _animeOverlay(BuildContext context) {
    final Size screenSize =
        MediaQuery.of(context).size;

    // MUCH LARGER CHARACTER.
    // The image itself is intentionally oversized
    // so the character appears large on the right side.
    final double animeHeight =
        screenSize.height * 1.40;

    final double animeWidth =
        screenSize.width * 1.40;

    return AnimatedPositioned(
      duration: const Duration(
        milliseconds: 400,
      ),
      curve: Curves.easeOutCubic,

      // Completely outside the RIGHT side when hidden.
      //
      // When shown, the oversized image is still pushed
      // toward the RIGHT side instead of sitting in the middle.
      right: _showAnimeOverlay
          ? -animeWidth * 0.08
          : -animeWidth - 30,

      top: (screenSize.height -
              animeHeight) /
          2,

      width: animeWidth,
      height: animeHeight,

      child: IgnorePointer(
        child: Align(
          alignment: Alignment.centerRight,
          child: Image.asset(
            _currentAnime,
            width: animeWidth,
            height: animeHeight,
            fit: BoxFit.contain,
            errorBuilder: (
              context,
              error,
              stackTrace,
            ) {
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }

  // =====================================================
  // DISPOSE
  // =====================================================

  @override
  void dispose() {
    _animeTimer?.cancel();
    super.dispose();
  }

  // =====================================================
  // BUILD
  // =====================================================

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDarkModeNotifier,
      builder: (
        context,
        isDarkMode,
        child,
      ) {
        return Scaffold(
          backgroundColor: isDarkMode
              ? const Color(0xFF212121)
              : const Color(0xFFF7F8FA),

          appBar: AppBar(
            elevation: 0,
            backgroundColor: isDarkMode
                ? const Color(0xFF212121)
                : const Color.fromARGB(
                    255,
                    72,
                    119,
                    247,
                  ),
            foregroundColor: Colors.white,
            title: const Text(
              'Flood Preparation Checklist',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          body: _isLoading
              ? const Center(
                  child:
                      CircularProgressIndicator(
                    color: Color(0xFF2867F5),
                  ),
                )
              : Stack(
                  children: [
                    SingleChildScrollView(
                      padding:
                          const EdgeInsets.fromLTRB(
                        24,
                        18,
                        24,
                        30,
                      ),
                      child: Column(
                        children: [
                          // =================================================
                          // PROGRESS
                          // =================================================

                          _progressHeader(
                            isDarkMode,
                          ),

                          // =================================================
                          // BEFORE A FLOOD
                          // =================================================

                          _checklistSection(
                            'Before a Flood',
                            'Prepare yourself, your family, and your home.',
                            _beforeFloodItems,
                            isDarkMode,
                            Icons.home_work_rounded,
                          ),

                          // =================================================
                          // WHEN FLOODING STARTS
                          // =================================================

                          _checklistSection(
                            'When Flooding Starts',
                            'Stay alert and follow safety instructions.',
                            _duringFloodItems,
                            isDarkMode,
                            Icons.warning_amber_rounded,
                          ),

                          // =================================================
                          // AFTER THE FLOOD
                          // =================================================

                          _checklistSection(
                            'After the Flood',
                            'Return only when the area is considered safe.',
                            _afterFloodItems,
                            isDarkMode,
                            Icons.health_and_safety_rounded,
                          ),

                          // =================================================
                          // INFORMATION NOTE
                          // =================================================

                          Container(
                            width: double.infinity,
                            padding:
                                const EdgeInsets.all(15),
                            decoration:
                                BoxDecoration(
                              color: isDarkMode
                                  ? const Color(
                                      0xFF303030,
                                    )
                                  : Colors.white,
                              borderRadius:
                                  BorderRadius.circular(
                                16,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment
                                      .start,
                              children: [
                                Icon(
                                  Icons
                                      .info_outline_rounded,
                                  color: isDarkMode
                                      ? Colors.grey[400]
                                      : const Color(
                                          0xFF8194BB,
                                        ),
                                  size: 20,
                                ),
                                const SizedBox(
                                  width: 10,
                                ),
                                Expanded(
                                  child: Text(
                                    'This checklist is a preparation guide. '
                                    'Always follow official emergency instructions '
                                    'and evacuation orders when issued.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      height: 1.4,
                                      color: isDarkMode
                                          ? Colors
                                              .grey[400]
                                          : const Color(
                                              0xFF8194BB,
                                            ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // =====================================================
                    // ANIME CHARACTER OVERLAY
                    // =====================================================

                    _animeOverlay(context),
                  ],
                ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:detectco/services/emergency_location_service.dart';
import 'package:torch_flashlight/torch_flashlight.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

import 'package:detectco/main.dart'; // for isDarkModeNotifier
import 'package:detectco/pages/during_after_flood.dart';
import 'package:detectco/pages/flood_prep_checklist.dart';

class EvacuateTab extends StatefulWidget {
  const EvacuateTab({super.key, this.onGoToMap});

  /// Called when the user taps an evacuation card.
  /// (name, address, latitude, longitude)
  final void Function(String name, String address, double lat, double lng)?
      onGoToMap;

  @override
  State<EvacuateTab> createState() => _EvacuateTabState();
}

class _EvacuateTabState extends State<EvacuateTab>
    with WidgetsBindingObserver {
  // 0 = Evacuation Centers, 1 = Emergency Numbers, 2 = Flood Prep Guides
  int _selectedSection = 0;

  late final PageController _pageController =
      PageController(initialPage: _selectedSection);

  final EmergencyLocationService _emergencyLocationService =
      EmergencyLocationService();
  EmergencyLocationSession? _emergencySession;
  bool _startingEmergencySession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkEmergencySessionExpiry();
    }
  }

  Future<void> _checkEmergencySessionExpiry() async {
    final expired = await _emergencyLocationService.expireIfNeeded();
    if (expired && mounted) {
      setState(() => _emergencySession = null);
      _showEmergencyMessage('Emergency location sharing has expired.');
    }
  }

  Future<void> _startEmergencyLocation() async {
    if (_startingEmergencySession) return;
    if (_emergencySession != null) {
      if (DateTime.now().isBefore(_emergencySession!.expiresAt)) return;
      await _checkEmergencySessionExpiry();
      if (!mounted) return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Share your emergency location?'),
        content: const Text(
          'Your current GPS location and updates will be temporarily shared '
          'with authorized emergency responders for up to 30 minutes. '
          'You can stop sharing at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Share location'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _startingEmergencySession = true);
    try {
      final session = await _emergencyLocationService.start(
        onExpired: () {
          if (!mounted) return;
          setState(() => _emergencySession = null);
          _showEmergencyMessage('Emergency location sharing has expired.');
        },
      );
      if (mounted) setState(() => _emergencySession = session);
    } catch (error) {
      if (!mounted) return;
      _showEmergencyMessage(
        error is EmergencyLocationException
            ? error.message
            : 'Could not start emergency location sharing. Check your connection and try again.',
      );
    } finally {
      if (mounted) setState(() => _startingEmergencySession = false);
    }
  }

  Future<void> _stopEmergencyLocation() async {
    try {
      await _emergencyLocationService.stop();
      if (!mounted) return;
      setState(() => _emergencySession = null);
      _showEmergencyMessage('Emergency location sharing stopped.');
    } catch (_) {
      if (!mounted) return;
      setState(() => _emergencySession = null);
      _showEmergencyMessage(
        'Sharing stopped on this device, but the session status could not be updated. Please check your connection.',
      );
    }
  }

  void _showEmergencyMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // =====================================================
  // SOS FLASHLIGHT
  // =====================================================

  bool _isSosActive = false;

  Future<void> _startSosFlashlight() async {
    try {
      final bool isAvailable =
          await TorchFlashlight.isTorchFlashlightAvailable();

      if (!isAvailable) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Flashlight is not available on this device.',
            ),
          ),
        );

        return;
      }

      await TorchFlashlight.startSOS();

      if (!mounted) return;

      setState(() {
        _isSosActive = true;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to start SOS flashlight.',
          ),
        ),
      );
    }
  }

  Future<void> _stopSosFlashlight() async {
    try {
      await TorchFlashlight.stopSOS();

      if (!mounted) return;

      setState(() {
        _isSosActive = false;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to stop SOS flashlight.',
          ),
        ),
      );
    }
  }

  // =====================================================
  // EMERGENCY ALARM
  // =====================================================

  bool _isEmergencyAlarmActive = false;

  Future<void> _startEmergencyAlarm() async {
    try {
      await FlutterRingtonePlayer().playAlarm(
        looping: true,
        volume: 1.0,
        asAlarm: true,
      );

      if (!mounted) return;

      setState(() {
        _isEmergencyAlarmActive = true;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to start emergency alarm.',
          ),
        ),
      );
    }
  }

  Future<void> _stopEmergencyAlarm() async {
    try {
      await FlutterRingtonePlayer().stop();

      if (!mounted) return;

      setState(() {
        _isEmergencyAlarmActive = false;
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to stop emergency alarm.',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    TorchFlashlight.stopSOS();
    FlutterRingtonePlayer().stop();
    _pageController.dispose();
    super.dispose();
  }

  // =====================================================
  // COPY TO CLIPBOARD (still used by emergency numbers)
  // =====================================================

  void _copyToClipboard(
    BuildContext context,
    String text,
    String message,
  ) {
    Clipboard.setData(
      ClipboardData(text: text),
    );

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle,
              color: Colors.white,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message),
            ),
          ],
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  // =====================================================
  // SEGMENTED SECTION TABS
  // =====================================================

  Widget _sectionTabs(bool isDarkMode) {
    final labels = ['Evacuation', 'Emergency', 'Guides'];

    return Container(
      margin: const EdgeInsets.only(top: 16, bottom: 8),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF303030)
            : const Color(0xFFF0F2F5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final bool isSelected = _selectedSection == index;

          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedSection = index;
                });

                _pageController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  // Evacuation (0) = green, Emergency (1) = red,
                  // Guides (2) = unchanged blue.
                  color: !isSelected
                      ? Colors.transparent
                      : index == 0
                          ? Colors.green
                          : index == 1
                              ? const Color(0xFFFF3035)
                              : const Color.fromARGB(255, 72, 119, 247),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  labels[index],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? Colors.white
                        : (isDarkMode
                            ? Colors.grey[400]
                            : Colors.grey[600]),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
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
        top: 12,
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
  // EVACUATE ON MAP
  // =====================================================

  void _openOnMap(
    String name,
    String address,
    double lat,
    double lng,
  ) {
    widget.onGoToMap?.call(name, address, lat, lng);
  }

  // =====================================================
  // EVACUATION CENTER CARD
  //
  // Tapping the card now switches to the Map tab (via the
  // onGoToMap callback owned by BottomNavPage) instead of
  // pushing a new screen. "Tap to copy address" was removed;
  // the address is shown as plain text.
  // =====================================================

  Widget _evacuationCard(
    BuildContext context,
    String name,
    String address,
    String distance,
    double lat,
    double lng,
    bool isDarkMode,
  ) {
    return GestureDetector(
      onTap: () => _openOnMap(name, address, lat, lng),
      child: Container(
        height: 78,
        margin: const EdgeInsets.only(bottom: 14),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isDarkMode
              ? const Color(0xFF303030)
              : Colors.white,
          borderRadius: BorderRadius.circular(18),
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
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
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
                  const SizedBox(height: 3),
                  Text(
                    address,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDarkMode
                          ? Colors.grey[400]
                          : const Color(0xFF8194BB),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    distance,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF8194BB),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Icon(
                    Icons.map_outlined,
                    size: 16,
                    color: isDarkMode
                        ? Colors.grey[400]
                        : const Color(0xFF8194BB),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =====================================================
  // EMERGENCY NUMBER CARD
  // =====================================================

  Widget _emergencyCard(
    BuildContext context,
    String number,
    String description,
    bool isDarkMode,
  ) {
    return GestureDetector(
      onTap: () {
        _copyToClipboard(
          context,
          number,
          'Emergency number copied to clipboard',
        );
      },
      child: Container(
        height: 78,
        margin: const EdgeInsets.only(bottom: 14),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isDarkMode
              ? const Color(0xFF303030)
              : Colors.white,
          borderRadius: BorderRadius.circular(18),
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
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    number,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode
                          ? Colors.white
                          : const Color(0xFF1D2B4A),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(
                        Icons.copy_rounded,
                        size: 12,
                        color: isDarkMode
                            ? Colors.grey[400]
                            : const Color(0xFF8194BB),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Tap to copy number',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDarkMode
                                ? Colors.grey[400]
                                : const Color(0xFF8194BB),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Flexible(
              flex: 0,
              child: Padding(
                padding: const EdgeInsets.only(
                  left: 8,
                  right: 16,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 110,
                  ),
                  child: Text(
                    description,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8194BB),
                    ),
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
        ),
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
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isDarkMode
              ? const Color(0xFF303030)
              : Colors.white,
          borderRadius: BorderRadius.circular(18),
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
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
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
  // SOS FLASHLIGHT CARD
  // =====================================================

  Widget _sosFlashlightCard(bool isDarkMode) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF303030)
            : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 8,
            offset: const Offset(4, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: _isSosActive
                      ? const Color(0xFFFF3035)
                      : const Color(0xFF2867F5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.flashlight_on,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SOS Flashlight',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode
                            ? Colors.white
                            : const Color(0xFF1D2B4A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isSosActive
                          ? 'SOS signal is active'
                          : 'Use your flashlight to signal for help',
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
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isSosActive
                  ? _stopSosFlashlight
                  : _startSosFlashlight,
              icon: Icon(
                _isSosActive
                    ? Icons.stop_circle
                    : Icons.sos,
              ),
              label: Text(
                _isSosActive
                    ? 'STOP SOS'
                    : 'START SOS FLASHLIGHT',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isSosActive
                    ? const Color(0xFFFF3035)
                    : const Color(0xFF2867F5),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // EMERGENCY ALARM CARD
  // =====================================================

  Widget _emergencyAlarmCard(bool isDarkMode) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF303030)
            : Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.20),
            blurRadius: 8,
            offset: const Offset(4, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: _isEmergencyAlarmActive
                      ? const Color(0xFFFF3035)
                      : const Color(0xFFFF7A00),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.volume_up_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Emergency Alarm',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode
                            ? Colors.white
                            : const Color(0xFF1D2B4A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isEmergencyAlarmActive
                          ? 'Emergency alarm is active'
                          : 'Play a continuous emergency alarm',
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
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isEmergencyAlarmActive
                  ? _stopEmergencyAlarm
                  : _startEmergencyAlarm,
              icon: Icon(
                _isEmergencyAlarmActive
                    ? Icons.stop_circle
                    : Icons.campaign_rounded,
              ),
              label: Text(
                _isEmergencyAlarmActive
                    ? 'STOP EMERGENCY ALARM'
                    : 'START EMERGENCY ALARM',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isEmergencyAlarmActive
                    ? const Color(0xFFFF3035)
                    : const Color(0xFFFF7A00),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =====================================================
  // SECTION CONTENT
  // =====================================================

  List<Widget> _evacuationSection(
    BuildContext context,
    bool isDarkMode,
  ) {
    return [
      _sectionTitle(
        'EVACUATION CENTERS',
        isDarkMode,
      ),
      _evacuationCard(
        context,
        'Lingga Elementary School',
        '658J+7WC, Dany, Calamba, 4027 Laguna',
        '-- km',
        14.215765305050551,
        121.18228271136698,
        isDarkMode,
      ),
      _evacuationCard(
        context,
        'Uwisan Barangay Hall',
        '65PF+Q9Q Uwisan, Calamba, 4027 Laguna',
        '-- km',
        14.23707209551028,
        121.17340069445697,
        isDarkMode,
      ),
      _evacuationCard(
        context,
        'Palingon Elementary School',
        '658P+425, 202 Caballero St, Real, Calamba, 4027 Laguna',
        '-- km',
        14.215617735789499,
        121.1861596967596,
        isDarkMode,
      ),
    ];
  }

  List<Widget> _emergencySection(
    BuildContext context,
    bool isDarkMode,
  ) {
    return [
      _sectionTitle(
        'EMERGENCY NUMBERS',
        isDarkMode,
      ),
      _emergencyCard(
        context,
        '911',
        'Emergency Hotline',
        isDarkMode,
      ),
      _emergencyCard(
        context,
        '0917 148 9813',
        'Calamba CDRRMO',
        isDarkMode,
      ),
      _emergencyCard(
        context,
        '(+63) 992 377 5096',
        'Uwisan Health Center',
        isDarkMode,
      ),
    ];
  }

  List<Widget> _guidesSection(
    BuildContext context,
    bool isDarkMode,
  ) {
    return [
      _sectionTitle(
        'FLOOD PREPARATION GUIDES',
        isDarkMode,
      ),

      _emergencyLocationCard(isDarkMode),

      // =====================================================
      // SOS FLASHLIGHT
      // =====================================================

      _sosFlashlightCard(isDarkMode),

      // =====================================================
      // EMERGENCY ALARM
      // =====================================================

      _emergencyAlarmCard(isDarkMode),

      _guideCard(
        'Flood Preparation Checklist',
        isDarkMode,
        () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  const FloodPreparationChecklist(),
            ),
          );
        },
      ),

      _guideCard(
        'During and After Flood',
        isDarkMode,
        () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  const DuringAfterFlood(),
            ),
          );
        },
      ),
    ];
  }

  Widget _emergencyLocationCard(bool isDarkMode) {
    final session = _emergencySession;
    final active = session != null &&
        DateTime.now().isBefore(session.expiresAt);
    final expiryLabel = session == null
        ? ''
        : TimeOfDay.fromDateTime(session.expiresAt).format(context);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF303030)
            : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: active
            ? Border.all(color: const Color(0xFFFF3035), width: 1.5)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 8,
            offset: const Offset(4, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: active
                      ? const Color(0xFFFF3035)
                      : const Color(0xFF2867F5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.location_on,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Emergency Locate Me',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode
                            ? Colors.white
                            : const Color(0xFF1D2B4A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      active
                          ? 'LOCATION SHARING ACTIVE · Expires $expiryLabel'
                          : 'Temporarily share your GPS location with emergency responders',
                      style: TextStyle(
                        fontSize: 12,
                        color: active
                            ? const Color(0xFFFF6B6B)
                            : (isDarkMode
                                ? Colors.grey[400]
                                : const Color(0xFF8194BB)),
                        fontWeight:
                            active ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _startingEmergencySession
                  ? null
                  : (active
                      ? _stopEmergencyLocation
                      : _startEmergencyLocation),
              icon: _startingEmergencySession
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(active ? Icons.stop_circle : Icons.my_location),
              label: Text(
                _startingEmergencySession
                    ? 'GETTING LOCATION…'
                    : (active
                        ? 'STOP EMERGENCY'
                        : 'EMERGENCY LOCATE ME'),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: active
                    ? const Color(0xFFFF3035)
                    : const Color(0xFF2867F5),
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.blueGrey,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
      builder: (
        context,
        isDarkMode,
        child,
      ) {
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
                    : const Color.fromARGB(
                        255,
                        72,
                        119,
                        247,
                      ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        GestureDetector(
                          child: SizedBox(
                            width: 50,
                            height: 50,
                            child: Image.asset(
                              "assets/icon/detect-co_logo.png",
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Tools',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // =================================================
              // SEGMENTED TABS
              // =================================================

              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                ),
                child: _sectionTabs(isDarkMode),
              ),

              // =================================================
              // PAGE CONTENT — SWIPEABLE SECTIONS
              // =================================================

              Expanded(
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() {
                      _selectedSection = index;
                    });
                  },
                  children: [
                    SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40,
                        vertical: 8,
                      ),
                      child: Column(
                        children: [
                          ..._evacuationSection(
                            context,
                            isDarkMode,
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                    SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40,
                        vertical: 8,
                      ),
                      child: Column(
                        children: [
                          ..._emergencySection(
                            context,
                            isDarkMode,
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                    SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40,
                        vertical: 8,
                      ),
                      child: Column(
                        children: [
                          ..._guidesSection(
                            context,
                            isDarkMode,
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}


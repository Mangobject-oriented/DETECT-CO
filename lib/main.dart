import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import 'package:detectco/pages/home.dart';
import 'package:detectco/pages/map.dart';
import 'package:detectco/pages/evacuate.dart';
import 'package:detectco/pages/notification.dart';
import 'package:detectco/pages/menu.dart';
import 'package:detectco/pages/local_ai_test.dart';
import 'package:detectco/services/emergency_location_service.dart';
import 'package:detectco/services/ml_api_connection.dart';
import 'package:detectco/tutorial/tutorial_coordinator.dart';

// =====================================================
// LOCAL NOTIFICATIONS
// =====================================================

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    EmergencyLocationService.notificationPlugin;

// =====================================================
// NOTIFICATION CHANNEL IDs
// =====================================================

const String classNotificationChannelId = 'class_alerts';

const String testNotificationChannelId = 'test_alerts_v2';

// =====================================================
// UNREAD NOTIFICATION COUNT
// =====================================================
//
// IMPORTANT:
// Use the SAME notifier used by NotificationStorage.
//
// Previously there were TWO separate notifiers:
// 1. NotificationStorage.unreadCountNotifier
// 2. unreadNotificationCount
//
// That caused the NotificationTab to update while the
// navbar badge stayed unchanged.
//
// This now points directly to the NotificationStorage
// notifier so both the notification page and navbar
// always use the same real-time value.
//

final ValueNotifier<int> unreadNotificationCount =
    NotificationStorage.unreadCountNotifier;

// =====================================================
// REFRESH UNREAD NOTIFICATION COUNT
// =====================================================

Future<void> refreshUnreadNotificationCount() async {
  try {
    final notifications = await NotificationStorage.getNotifications();

    final int unreadCount = notifications
        .where((notification) => !notification.isRead)
        .length;

    // This is now the SAME notifier used by the navbar.
    unreadNotificationCount.value = unreadCount;

    print('Unread notification count refreshed: $unreadCount');
  } catch (e) {
    print('ERROR REFRESHING UNREAD NOTIFICATION COUNT: $e');
  }
}

// =====================================================
// INITIALIZE LOCAL NOTIFICATIONS
// =====================================================

Future<void> initializeLocalNotifications() async {
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: androidSettings,
  );

  await flutterLocalNotificationsPlugin.initialize(
    settings: initializationSettings,
    onDidReceiveNotificationResponse: emergencyLocationNotificationResponse,
    onDidReceiveBackgroundNotificationResponse:
        emergencyLocationNotificationBackgroundResponse,
  );

  final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
      flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

  if (androidPlugin == null) {
    print('ANDROID LOCAL NOTIFICATIONS PLUGIN NOT AVAILABLE');
    return;
  }

  // ===================================================
  // CLASS ALERT CHANNEL
  // ===================================================

  const AndroidNotificationChannel classChannel = AndroidNotificationChannel(
    classNotificationChannelId,
    'Class Alerts',
    description: 'Notifications for class suspension announcements.',
    importance: Importance.max,
    playSound: true,
  );

  await androidPlugin.createNotificationChannel(classChannel);

  // ===================================================
  // TEST ALERT CHANNEL
  // ===================================================

  const AndroidNotificationChannel testChannel = AndroidNotificationChannel(
    testNotificationChannelId,
    'Test Alerts',
    description: 'Custom sound notifications for DETECT-CO testing.',
    importance: Importance.max,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('test_alert'),
  );

  await androidPlugin.createNotificationChannel(testChannel);

  const AndroidNotificationChannel emergencyLocationChannel =
      AndroidNotificationChannel(
        emergencyLocationNotificationChannelId,
        'Emergency Location Sharing',
        description:
            'Shows while Emergency Locate Me is sharing your location.',
        importance: Importance.high,
        playSound: false,
        enableVibration: false,
      );

  await androidPlugin.createNotificationChannel(emergencyLocationChannel);

  print('LOCAL NOTIFICATIONS INITIALIZED');
  print('Test notification channel: $testNotificationChannelId');
  print('Test notification sound: test_alert');
}

// =====================================================
// SHOW LOCAL NOTIFICATION
// =====================================================

Future<void> showLocalNotification({
  required int id,
  required String title,
  required String body,
  required bool isTestNotification,
}) async {
  final String channelId = isTestNotification
      ? testNotificationChannelId
      : classNotificationChannelId;

  final String channelName = isTestNotification
      ? 'Test Alerts'
      : 'Class Alerts';

  final String channelDescription = isTestNotification
      ? 'Custom sound notifications for DETECT-CO testing.'
      : 'Notifications for class suspension announcements.';

  print('--------------------------------');
  print('SHOWING LOCAL NOTIFICATION');
  print('Channel ID: $channelId');
  print('Channel Name: $channelName');
  print(
    'Custom Sound: '
    '${isTestNotification ? 'test_alert' : 'default'}',
  );
  print('--------------------------------');

  await flutterLocalNotificationsPlugin.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        icon: 'ic_stat_detect_co',
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        sound: isTestNotification
            ? const RawResourceAndroidNotificationSound('test_alert')
            : null,
        enableVibration: true,
      ),
    ),
  );
}

// =====================================================
// BACKGROUND FCM HANDLER
// =====================================================

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('================================');
  print('BACKGROUND FCM MESSAGE');
  print('================================');

  await Firebase.initializeApp();

  if (await MlApiConnection.instance.handleFcmData(message.data)) {
    return;
  }

  // ===================================================
  // INITIALIZE LOCAL NOTIFICATIONS IN BACKGROUND
  // ===================================================

  await initializeLocalNotifications();

  print('Background notification received!');
  print('Message ID: ${message.messageId}');
  print('Title: ${message.notification?.title}');
  print('Body: ${message.notification?.body}');
  print('Type: ${message.data['type']}');

  // ===================================================
  // DETERMINE TYPE
  // ===================================================

  final bool isTestNotification = message.data['type'] == 'test';

  final String notificationType = message.data['type'] == 'alert'
      ? 'alert'
      : 'announcement';

  // ===================================================
  // SAVE NOTIFICATION TO LOCAL HISTORY
  // ===================================================

  final RemoteNotification? notification = message.notification;

  final String title =
      notification?.title ?? message.data['title'] ?? 'DETECT-CO';

  final String body = notification?.body ?? message.data['body'] ?? '';

  await NotificationStorage.saveNotification(
    AppNotification(
      id:
          message.data['announcementId']?.toString() ??
          message.messageId ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      body: body,
      type: notificationType,
      timestamp: DateTime.now(),
      isRead: false,
    ),
  );

  print('Background notification saved to history!');

  // ===================================================
  // ONLY SHOW LOCAL NOTIFICATION FOR DATA-ONLY MESSAGE
  // ===================================================

  if (notification == null) {
    await showLocalNotification(
      id: DateTime.now().millisecondsSinceEpoch,
      title: title,
      body: body,
      isTestNotification: isTestNotification,
    );

    print(
      isTestNotification
          ? 'BACKGROUND TEST -> CUSTOM SOUND'
          : 'BACKGROUND CLASS -> NORMAL SOUND',
    );
  } else {
    print(
      'FCM notification payload detected.'
      ' Android may display it automatically.',
    );
  }

  print('================================');
}

// =====================================================
// INITIALIZE FCM SERVICES
// =====================================================

Future<void> initializeFirebaseMessagingServices() async {
  unawaited(MlApiConnection.instance.synchronizeRemoteConfig());

  // ===================================================
  // LOCAL NOTIFICATIONS
  // ===================================================

  try {
    await initializeLocalNotifications();
  } catch (e) {
    print('LOCAL NOTIFICATIONS ERROR: $e');
  }

  // ===================================================
  // LOAD UNREAD NOTIFICATION COUNT
  // ===================================================

  try {
    await refreshUnreadNotificationCount();
  } catch (e) {
    print('UNREAD COUNT ERROR: $e');
  }

  // ===================================================
  // FIREBASE MESSAGING
  // ===================================================

  final FirebaseMessaging messaging = FirebaseMessaging.instance;

  // ===================================================
  // REQUEST NOTIFICATION PERMISSION
  // ===================================================

  try {
    final NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    print(
      'Notification permission: '
      '${settings.authorizationStatus}',
    );
  } catch (e) {
    print('FCM PERMISSION ERROR: $e');
  }

  // ===================================================
  // SUBSCRIBE TO DETECT-CO ANNOUNCEMENT TOPIC
  // ===================================================

  try {
    await messaging.subscribeToTopic('detect_co_announcements');

    print('FCM: Subscribed to detect_co_announcements');
  } catch (e) {
    print('FCM TOPIC ERROR: $e');
  }

  try {
    await messaging.subscribeToTopic('detect_co_ml_config');
  } catch (e) {
    print('ML CONFIG TOPIC ERROR: $e');
  }

  // ===================================================
  // GET FCM TOKEN
  // ===================================================

  print('FCM: Getting token...');

  try {
    final String? token = await messaging.getToken();

    print('FCM: Token request completed.');

    print('FCM token available: ${token != null}');
  } catch (e) {
    print('FCM TOKEN ERROR: $e');
  }

  // ===================================================
  // FOREGROUND FCM MESSAGE
  // ===================================================

  FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
    if (await MlApiConnection.instance.handleFcmData(message.data)) {
      return;
    }

    print('================================');
    print('FOREGROUND FCM MESSAGE');
    print('================================');

    print('Title: ${message.notification?.title}');

    print('Body: ${message.notification?.body}');

    print('Type: ${message.data['type']}');

    print('Data: ${message.data}');

    final RemoteNotification? notification = message.notification;

    // =================================================
    // GET TITLE/BODY
    // =================================================

    final String title =
        notification?.title ?? message.data['title'] ?? 'DETECT-CO';

    final String body = notification?.body ?? message.data['body'] ?? '';

    // =================================================
    // DETERMINE TEST NOTIFICATION
    // =================================================

    final bool isTestNotification = message.data['type'] == 'test';

    // =================================================
    // DETERMINE HISTORY TYPE
    // =================================================

    final String notificationType = message.data['type'] == 'alert'
        ? 'alert'
        : 'announcement';

    // =================================================
    // DEBUG
    // =================================================

    if (isTestNotification) {
      print('--------------------------------');
      print('TEST NOTIFICATION DETECTED');
      print('Channel: $testNotificationChannelId');
      print('Sound: test_alert');
      print('--------------------------------');
    } else {
      print('--------------------------------');
      print('CLASS NOTIFICATION DETECTED');
      print('Channel: $classNotificationChannelId');
      print('Sound: DEFAULT');
      print('--------------------------------');
    }

    // =================================================
    // SAVE NOTIFICATION TO LOCAL HISTORY
    // =================================================

    await NotificationStorage.saveNotification(
      AppNotification(
        id:
            message.data['announcementId']?.toString() ??
            message.messageId ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        title: title,
        body: body,
        type: notificationType,
        timestamp: DateTime.now(),
        isRead: false,
      ),
    );

    // =================================================
    // UPDATE UNREAD COUNT
    // =================================================

    await refreshUnreadNotificationCount();

    print(
      'Unread notification count: '
      '${unreadNotificationCount.value}',
    );

    print('Notification saved to history!');

    // =================================================
    // SHOW LOCAL NOTIFICATION
    // =================================================

    await showLocalNotification(
      id: message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch,
      title: title,
      body: body,
      isTestNotification: isTestNotification,
    );

    print('Local notification displayed.');

    print('================================');
  });

  FirebaseMessaging.onMessageOpenedApp.listen((message) async {
    await MlApiConnection.instance.handleFcmData(message.data);
  });

  final initialMessage = await messaging.getInitialMessage();
  if (initialMessage != null) {
    await MlApiConnection.instance.handleFcmData(initialMessage.data);
  }
}

// =====================================================
// MAIN
// =====================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ===================================================
  // FIREBASE
  // ===================================================

  await Firebase.initializeApp();

  // ===================================================
  // REGISTER BACKGROUND HANDLER
  // ===================================================

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // ===================================================
  // START APP
  // ===================================================

  runApp(const MyApp());

  // ===================================================
  // INITIALIZE FCM SERVICES AFTER APP START
  // ===================================================

  initializeFirebaseMessagingServices();
}

// =====================================================
// GLOBAL DARK MODE
// =====================================================

final ValueNotifier<bool> isDarkModeNotifier = ValueNotifier<bool>(true);

// =====================================================
// APP
// =====================================================

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DETECT CO',
      debugShowCheckedModeBanner: false,

      // =================================================
      // LOCAL AI TEST ROUTE
      // =================================================
      routes: {'/local-ai-test': (context) => const LocalAiTestPage()},

      // =================================================
      // DARK THEME ONLY
      // =================================================
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF212121),
      ),

      // =================================================
      // DARK MODE IS ALWAYS ON
      // =================================================
      themeMode: ThemeMode.dark,

      home: const BottomNavPage(),
    );
  }
}

// =====================================================
// BOTTOM NAVIGATION
// =====================================================

class BottomNavPage extends StatefulWidget {
  const BottomNavPage({super.key});

  @override
  State<BottomNavPage> createState() => _BottomNavPageState();
}

class _BottomNavPageState extends State<BottomNavPage>
    with WidgetsBindingObserver {
  static const String _tutorialCompleteKey = 'detectco_tutorial_completed_v1';
  static const String _tutorialLanguageKey = 'detectco_tutorial_language_v1';

  final ValueNotifier<TutorialLanguage> _tutorialLanguage = ValueNotifier(
    TutorialLanguage.english,
  );
  TutorialCoachMark? _tutorial;
  OverlayEntry? _tutorialCardEntry;
  bool _tutorialCompleted = false;
  bool _tutorialRequested = false;
  bool _tutorialActive = false;
  bool _criticalFloodWarning = false;
  bool _tutorialEndedByUser = false;
  int _tutorialStep = 0;
  final GlobalKey<EvacuateTabState> _toolsTabKey =
      GlobalKey<EvacuateTabState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTutorialPreferencesAndMaybeStart();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(MlApiConnection.instance.synchronizeRemoteConfig());
      if (_tutorialRequested && !_criticalFloodWarning) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _startTutorialAt(_tutorialStep);
        });
      }
    } else if (_tutorialActive) {
      _closeTutorialForInterruption();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _removeTutorialCardEntry();
    _tutorialLanguage.dispose();
    super.dispose();
  }

  Future<void> _loadTutorialPreferencesAndMaybeStart() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    _tutorialCompleted = preferences.getBool(_tutorialCompleteKey) ?? false;
    final storedLanguage = preferences.getString(_tutorialLanguageKey);
    if (storedLanguage == TutorialLanguage.filipino.name) {
      _tutorialLanguage.value = TutorialLanguage.filipino;
    } else if (storedLanguage == TutorialLanguage.english.name) {
      _tutorialLanguage.value = TutorialLanguage.english;
    } else {
      final languageCode = Localizations.localeOf(context).languageCode;
      _tutorialLanguage.value = languageCode == 'fil' || languageCode == 'tl'
          ? TutorialLanguage.filipino
          : TutorialLanguage.english;
    }
    if (!_tutorialCompleted) {
      _tutorialRequested = true;
      _startTutorialAt(0);
    }
  }

  Future<void> _saveTutorialLanguage(TutorialLanguage language) async {
    _tutorialLanguage.value = language;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_tutorialLanguageKey, language.name);
  }

  void _onCriticalFloodWarningChanged(bool critical) {
    if (_criticalFloodWarning == critical) return;
    _criticalFloodWarning = critical;
    if (critical && _tutorialActive) {
      _closeTutorialForInterruption();
    } else if (!critical && _tutorialRequested && !_tutorialActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startTutorialAt(_tutorialStep);
      });
    }
  }

  Future<void> _startTutorialReplay() async {
    _tutorialRequested = true;
    _tutorialStep = 0;
    if (_criticalFloodWarning) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tutorial paused while a critical flood warning is active.',
          ),
        ),
      );
      return;
    }
    await _startTutorialAt(0);
  }

  int _tabForTutorialStep(int step) => switch (step) {
    0 || 1 || 2 || 3 || 4 || 5 => 2,
    6 || 7 || 8 || 9 || 10 || 11 => 0,
    12 || 13 || 14 || 15 || 16 || 17 => 1,
    18 => 3,
    19 || 20 => 4,
    _ => 2,
  };

  GlobalKey _targetForTutorialStep(int step) => switch (step) {
    0 => TutorialTargets.homeBarangay,
    1 => TutorialTargets.homeRisk,
    2 => TutorialTargets.homeWeather,
    3 => TutorialTargets.homeWater,
    4 => TutorialTargets.homeRainfall,
    5 => TutorialTargets.bottomNavigation,
    6 => TutorialTargets.toolsSections,
    7 => TutorialTargets.toolsEmergencyAlarm,
    8 || 9 => TutorialTargets.toolsSosFlashlight,
    10 => TutorialTargets.toolsEmergencyLocation,
    11 => TutorialTargets.toolsLocalAi,
    12 => TutorialTargets.mapSearch,
    13 => TutorialTargets.mapFilters,
    14 => TutorialTargets.mapLegend,
    15 => TutorialTargets.mapMlRisk,
    16 => TutorialTargets.mapNearestResources,
    17 => TutorialTargets.mapLocateMe,
    18 => TutorialTargets.notificationTabs,
    19 => TutorialTargets.menuHowToUse,
    20 => TutorialTargets.bottomMenu,
    _ => TutorialTargets.homeBarangay,
  };

  Future<bool> _prepareTutorialTarget(int step) async {
    if (!mounted || step < 0 || step >= tutorialEnglishCopy.length) {
      return false;
    }
    final tab = _tabForTutorialStep(step);
    if (_currentIndex != tab) {
      setState(() => _currentIndex = tab);
    }
    await WidgetsBinding.instance.endOfFrame;
    if (step >= 7 && step <= 11) {
      await _toolsTabKey.currentState?.showTutorialSection(3);
      await WidgetsBinding.instance.endOfFrame;
    }
    var targetContext = _targetForTutorialStep(step).currentContext;
    for (var attempt = 0; targetContext == null && attempt < 3; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await WidgetsBinding.instance.endOfFrame;
      targetContext = _targetForTutorialStep(step).currentContext;
    }
    if (targetContext == null || !targetContext.mounted) return false;
    final renderObject = targetContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return false;
    try {
      await Scrollable.ensureVisible(
        targetContext,
        alignment: 0.35,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    } catch (_) {
      // Targets outside a Scrollable are already visible and need no action.
    }
    await WidgetsBinding.instance.endOfFrame;
    return mounted && _targetForTutorialStep(step).currentContext != null;
  }

  Future<void> _startTutorialAt(int requestedStep) async {
    if (!mounted || _criticalFloodWarning || _tutorialActive) return;
    var step = requestedStep.clamp(0, tutorialEnglishCopy.length - 1);
    while (step < tutorialEnglishCopy.length &&
        !await _prepareTutorialTarget(step)) {
      step++;
    }
    if (!mounted ||
        _criticalFloodWarning ||
        step >= tutorialEnglishCopy.length) {
      return;
    }

    _tutorialStep = step;
    _tutorialEndedByUser = false;
    final targets = <TargetFocus>[];
    for (var index = 0; index < tutorialEnglishCopy.length; index++) {
      final targetKey = _targetForTutorialStep(index);
      targets.add(
        TargetFocus(
          identify: 'detectco_tutorial_$index',
          keyTarget: targetKey,
          shape: ShapeLightFocus.RRect,
          radius: 12,
          paddingFocus: 6,
          enableTargetTab: false,
          enableOverlayTab: false,
          // Keep the spotlight target only. The dialogue is placed in a
          // separate safe-area overlay so its position is recalculated for
          // the active target and current device metrics.
          contents: const [],
        ),
      );
    }

    _tutorialActive = true;
    _tutorialRequested = true;
    final coachMark = TutorialCoachMark(
      targets: targets,
      initialFocus: step,
      colorShadow: Colors.black,
      opacityShadow: 0.82,
      pulseEnable: false,
      useSafeArea: true,
      hideSkip: true,
      onFinish: _handleTutorialOverlayClosed,
      onSkip: () {
        _handleTutorialOverlayClosed();
        return true;
      },
    );
    _tutorial = coachMark;
    coachMark.show(context: context);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && _tutorialActive && _tutorialCardEntry == null) {
      _tutorialCardEntry = OverlayEntry(builder: _buildTutorialCardOverlay);
      Overlay.of(context, rootOverlay: true).insert(_tutorialCardEntry!);
    }
  }

  Widget _buildTutorialCardOverlay(BuildContext context) {
    final step = _tutorialStep;
    final targetContext = _targetForTutorialStep(step).currentContext;
    final renderObject = targetContext?.findRenderObject();
    Rect? targetRect;
    if (renderObject is RenderBox && renderObject.hasSize) {
      targetRect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
    }
    return TutorialCardOverlay(
      targetRect: targetRect,
      cardBuilder: (placement) => Align(
        alignment: Alignment.center,
        child: TutorialStepCard(
          language: _tutorialLanguage,
          stepIndex: step,
          isLast: step == tutorialEnglishCopy.length - 1,
          canGoBack: step > 0,
          maxHeight: placement.maxHeight,
          onLanguageChanged: (language) {
            unawaited(_saveTutorialLanguage(language));
          },
          onBack: () => unawaited(_moveTutorialTo(step - 1)),
          onNext: () => unawaited(
            step == tutorialEnglishCopy.length - 1
                ? _completeTutorial()
                : _moveTutorialTo(step + 1),
          ),
          onSkip: () => unawaited(_completeTutorial()),
        ),
      ),
    );
  }

  void _removeTutorialCardEntry() {
    _tutorialCardEntry?.remove();
    _tutorialCardEntry = null;
  }

  Future<void> _moveTutorialTo(int requestedStep) async {
    if (!_tutorialActive || _criticalFloodWarning) return;
    final step = requestedStep.clamp(0, tutorialEnglishCopy.length - 1);
    if (!await _prepareTutorialTarget(step) || !_tutorialActive) {
      if (step + 1 < tutorialEnglishCopy.length) {
        await _moveTutorialTo(step + 1);
      }
      return;
    }
    _tutorialStep = step;
    _tutorial?.goTo(step);
    _tutorialCardEntry?.markNeedsBuild();
  }

  Future<void> _completeTutorial() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_tutorialCompleteKey, true);
    _tutorialCompleted = true;
    _tutorialEndedByUser = true;
    _tutorial?.finish();
  }

  void _closeTutorialForInterruption() {
    if (!_tutorialActive) return;
    _tutorialEndedByUser = false;
    _tutorial?.finish();
  }

  void _handleTutorialOverlayClosed() {
    _removeTutorialCardEntry();
    _tutorial = null;
    _tutorialActive = false;
    if (_tutorialEndedByUser) {
      _tutorialRequested = false;
      _tutorialEndedByUser = false;
    } else if (_tutorialRequested &&
        !_criticalFloodWarning &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _startTutorialAt(_tutorialStep);
      });
    }
  }

  // ===================================================
  // START ON HOME
  //
  // 0 = Tools
  // 1 = Map
  // 2 = Home
  // 3 = Notifications
  // 4 = Menu
  // ===================================================

  int _currentIndex = 2;

  final GlobalKey<CurvedNavigationBarState> _navKey =
      GlobalKey<CurvedNavigationBarState>();

  // ===================================================
  // PENDING "GO TO THIS EVAC SITE ON THE MAP" REQUEST
  // ===================================================

  String? _focusName;
  String? _focusAddress;
  double? _focusLat;
  double? _focusLng;
  int _focusRequestId = 0;

  void _goToEvacSiteOnMap(String name, String address, double lat, double lng) {
    setState(() {
      _focusName = name;
      _focusAddress = address;
      _focusLat = lat;
      _focusLng = lng;
      _focusRequestId++;
      _currentIndex = 1;
    });
  }

  // ===================================================
  // TABS
  // ===================================================

  List<Widget> get _tabs => [
    EvacuateTab(key: _toolsTabKey, onGoToMap: _goToEvacSiteOnMap),
    MapTab(
      focusRequestId: _focusRequestId,
      focusName: _focusName,
      focusLat: _focusLat,
      focusLng: _focusLng,
      focusDescription: _focusAddress,
    ),
    HomeTab(onCriticalFloodWarningChanged: _onCriticalFloodWarningChanged),
    const NotificationTab(),
    MenuTab(onStartTutorial: _startTutorialReplay),
  ];

  @override
  Widget build(BuildContext context) {
    // =================================================
    // NAVIGATION COLORS
    // =================================================

    final Color navBackground = const Color(0xFF212121);

    final Color barColor = const Color(0xFF303030);

    // =================================================
    // ICON COLORS
    // =================================================

    final Color iconColor = Colors.white;

    // =================================================
    // SELECTED BUTTON
    // =================================================

    final Color selectedButtonColor = const Color(0xFF424242);

    final Color selectedIconColor = Colors.white;

    return Scaffold(
      backgroundColor: navBackground,

      // =================================================
      // CURRENT TAB
      // =================================================
      body: IndexedStack(index: _currentIndex, children: _tabs),

      // =================================================
      // BOTTOM NAVIGATION
      // =================================================
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          key: TutorialTargets.bottomNavigation,
          height: 75,
          color: barColor,
          child: Stack(
            children: [
              // =================================================
              // CURVED NAVIGATION BAR
              // =================================================

              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 55,

                child: CurvedNavigationBar(
                  key: _navKey,

                  index: _currentIndex,

                  height: 55,

                  backgroundColor: navBackground,

                  color: barColor,

                  // =================================================
                  // SELECTED ICON CIRCLE
                  // =================================================
                  buttonBackgroundColor: selectedButtonColor,

                  // =================================================
                  // ANIMATION
                  // =================================================
                  animationDuration: const Duration(milliseconds: 350),

                  animationCurve: Curves.easeInOut,

                  // =================================================
                  // ICONS
                  // =================================================
                  items: [
                    // =================================================
                    // TOOLS
                    // =================================================

                    Image.asset(
                      'assets/icon/tools.png',
                      width: 26,
                      height: 26,
                      color: _currentIndex == 0 ? selectedIconColor : iconColor,
                    ),

                    // =================================================
                    // MAP
                    // =================================================
                    Icon(
                      Icons.map,
                      size: 26,
                      color: _currentIndex == 1 ? selectedIconColor : iconColor,
                    ),

                    // =================================================
                    // HOME
                    // =================================================
                    Icon(
                      Icons.home,
                      size: 26,
                      color: _currentIndex == 2 ? selectedIconColor : iconColor,
                    ),

                    // =================================================
                    // NOTIFICATIONS
                    // =================================================
                    ValueListenableBuilder<int>(
                      valueListenable: unreadNotificationCount,

                      builder: (context, unreadCount, child) {
                        return Stack(
                          clipBehavior: Clip.none,

                          children: [
                            Icon(
                              Icons.notifications_none_rounded,
                              size: 26,
                              color: _currentIndex == 3
                                  ? selectedIconColor
                                  : iconColor,
                            ),

                            // =================================================
                            // RED UNREAD BADGE
                            // =================================================
                            if (unreadCount > 0)
                              Positioned(
                                right: -8,
                                top: -8,

                                child: Container(
                                  constraints: const BoxConstraints(
                                    minWidth: 18,
                                    minHeight: 18,
                                  ),

                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),

                                  decoration: BoxDecoration(
                                    color: Colors.red,

                                    borderRadius: BorderRadius.circular(20),

                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1.5,
                                    ),
                                  ),

                                  child: Text(
                                    unreadCount > 99
                                        ? '99+'
                                        : unreadCount.toString(),

                                    textAlign: TextAlign.center,

                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),

                    // =================================================
                    // MENU
                    // =================================================
                    Icon(
                      Icons.menu_rounded,
                      key: TutorialTargets.bottomMenu,
                      size: 26,
                      color: _currentIndex == 4 ? selectedIconColor : iconColor,
                    ),
                  ],

                  // =================================================
                  // NAVIGATION TAP
                  // =================================================
                  onTap: (index) {
                    setState(() {
                      _currentIndex = index;
                    });
                  },
                ),
              ),

              // =================================================
              // LABELS
              // =================================================
              Positioned(
                left: 0,
                right: 0,
                bottom: 15,
                height: 14,

                child: Row(
                  children: [
                    Expanded(child: _buildLabel('Tools', 0)),

                    Expanded(child: _buildLabel('Map', 1)),

                    Expanded(child: _buildLabel('Home', 2)),

                    Expanded(child: _buildLabel('Notifications', 3)),

                    Expanded(child: _buildLabel('Menu', 4)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =====================================================
  // NAVIGATION LABEL
  // =====================================================

  Widget _buildLabel(String label, int index) {
    final bool isSelected = _currentIndex == index;

    return Center(
      child: Text(
        label,

        maxLines: 1,

        overflow: TextOverflow.ellipsis,

        textAlign: TextAlign.center,

        style: TextStyle(
          fontSize: 10,

          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,

          color: isSelected ? Colors.white : Colors.white70,
        ),
      ),
    );
  }
}

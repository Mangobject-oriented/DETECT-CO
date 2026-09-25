
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:detectco/pages/home.dart';
import 'package:detectco/pages/map.dart';
import 'package:detectco/pages/evacuate.dart';
import 'package:detectco/pages/notification.dart';
import 'package:detectco/pages/menu.dart';

// =====================================================
// LOCAL NOTIFICATIONS
// =====================================================

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// =====================================================
// NOTIFICATION CHANNEL IDs
//
// IMPORTANT:
// Android notification channel settings are persistent.
// Using a new ID makes sure the custom sound is applied.
// =====================================================

const String classNotificationChannelId = 'class_alerts';

const String testNotificationChannelId = 'test_alerts_v2';

// =====================================================
// UNREAD NOTIFICATION COUNT
// =====================================================

final ValueNotifier<int> unreadNotificationCount =
    ValueNotifier<int>(0);

// =====================================================
// REFRESH UNREAD NOTIFICATION COUNT
// =====================================================

Future<void> refreshUnreadNotificationCount() async {
  try {
    final notifications =
        await NotificationStorage.getNotifications();

    final int unreadCount = notifications
        .where((notification) => !notification.isRead)
        .length;

    unreadNotificationCount.value = unreadCount;

    print(
      'Unread notification count refreshed: $unreadCount',
    );
  } catch (e) {
    print(
      'ERROR REFRESHING UNREAD NOTIFICATION COUNT: $e',
    );
  }
}

// =====================================================
// INITIALIZE LOCAL NOTIFICATIONS
//
// This function is used by BOTH:
// - foreground
// - background isolate
//
// This is important because the background handler runs
// separately from the normal Flutter UI isolate.
// =====================================================

Future<void> initializeLocalNotifications() async {
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings =
      InitializationSettings(
    android: androidSettings,
  );

  await flutterLocalNotificationsPlugin.initialize(
    settings: initializationSettings,
  );

  final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
      flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

  if (androidPlugin == null) {
    print('ANDROID LOCAL NOTIFICATIONS PLUGIN NOT AVAILABLE');
    return;
  }

  // ===================================================
  // CLASS ALERT CHANNEL
  // ===================================================

  const AndroidNotificationChannel classChannel =
      AndroidNotificationChannel(
    classNotificationChannelId,
    'Class Alerts',
    description:
        'Notifications for class suspension announcements.',
    importance: Importance.max,
    playSound: true,
  );

  await androidPlugin.createNotificationChannel(
    classChannel,
  );

  // ===================================================
  // TEST ALERT CHANNEL
  //
  // NEW CHANNEL ID:
  // test_alerts_v2
  //
  // This is intentional because Android remembers the
  // settings of old notification channels.
  // ===================================================

  const AndroidNotificationChannel testChannel =
      AndroidNotificationChannel(
    testNotificationChannelId,
    'Test Alerts',
    description:
        'Custom sound notifications for DETECT-CO testing.',
    importance: Importance.max,
    playSound: true,
    sound: RawResourceAndroidNotificationSound(
      'test_alert',
    ),
  );

  await androidPlugin.createNotificationChannel(
    testChannel,
  );

  print('LOCAL NOTIFICATIONS INITIALIZED');
  print(
    'Test notification channel: $testNotificationChannelId',
  );
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
  final String channelId =
      isTestNotification
          ? testNotificationChannelId
          : classNotificationChannelId;

  final String channelName =
      isTestNotification
          ? 'Test Alerts'
          : 'Class Alerts';

  final String channelDescription =
      isTestNotification
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

        importance: Importance.max,
        priority: Priority.high,

        playSound: true,

        // =================================================
        // CUSTOM SOUND ONLY FOR TEST NOTIFICATIONS
        // =================================================

        sound: isTestNotification
            ? const RawResourceAndroidNotificationSound(
                'test_alert',
              )
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
Future<void> firebaseMessagingBackgroundHandler(
    RemoteMessage message) async {
  print('================================');
  print('BACKGROUND FCM MESSAGE');
  print('================================');

  await Firebase.initializeApp();

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

  final bool isTestNotification =
      message.data['type'] == 'test';

  final String notificationType =
      message.data['type'] == 'alert'
          ? 'alert'
          : 'announcement';

  // ===================================================
  // SAVE NOTIFICATION TO LOCAL HISTORY
  // ===================================================

  final RemoteNotification? notification =
      message.notification;

  final String title =
      notification?.title ??
      message.data['title'] ??
      'DETECT-CO';

  final String body =
      notification?.body ??
      message.data['body'] ??
      '';

  await NotificationStorage.saveNotification(
    AppNotification(
      id: message.messageId ??
          DateTime.now()
              .millisecondsSinceEpoch
              .toString(),
      title: title,
      body: body,
      type: notificationType,
      timestamp: DateTime.now(),
      isRead: false,
    ),
  );

  print('Background notification saved to history!');

  // ===================================================
  // IMPORTANT
  //
  // Only show a local notification here when the FCM
  // message does NOT contain a notification payload.
  //
  // This prevents duplicate notifications.
  //
  // Your test-notification.js should therefore send
  // the TEST notification as DATA-ONLY.
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
//
// IMPORTANT:
// This is intentionally started AFTER runApp().
//
// Network-dependent operations such as:
// - notification permission
// - topic subscription
// - FCM token
//
// should NOT prevent the application from opening
// when there is no Wi-Fi or mobile data.
// =====================================================

Future<void> initializeFirebaseMessagingServices() async {
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
  //
  // This uses local notification storage and does not
  // need internet access.
  // ===================================================

  try {
    await refreshUnreadNotificationCount();
  } catch (e) {
    print('UNREAD COUNT ERROR: $e');
  }

  // ===================================================
  // FIREBASE MESSAGING
  // ===================================================

  final FirebaseMessaging messaging =
      FirebaseMessaging.instance;

  // ===================================================
  // REQUEST NOTIFICATION PERMISSION
  // ===================================================

  try {
    final NotificationSettings settings =
        await messaging.requestPermission(
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
    await messaging.subscribeToTopic(
      'detect_co_announcements',
    );

    print(
      'FCM: Subscribed to detect_co_announcements',
    );
  } catch (e) {
    print('FCM TOPIC ERROR: $e');
  }

  // ===================================================
  // GET FCM TOKEN
  // ===================================================

  print('FCM: Getting token...');

  try {
    final String? token =
        await messaging.getToken();

    print('FCM: Token request completed.');
    print('FCM TOKEN: $token');
  } catch (e) {
    print('FCM TOKEN ERROR: $e');
  }

  // ===================================================
  // FOREGROUND FCM MESSAGE
  // ===================================================

  FirebaseMessaging.onMessage.listen(
    (RemoteMessage message) async {
      print('================================');
      print('FOREGROUND FCM MESSAGE');
      print('================================');

      print(
        'Title: ${message.notification?.title}',
      );

      print(
        'Body: ${message.notification?.body}',
      );

      print(
        'Type: ${message.data['type']}',
      );

      print(
        'Data: ${message.data}',
      );

      final RemoteNotification? notification =
          message.notification;

      // =================================================
      // GET TITLE/BODY
      // =================================================

      final String title =
          notification?.title ??
          message.data['title'] ??
          'DETECT-CO';

      final String body =
          notification?.body ??
          message.data['body'] ??
          '';

      // =================================================
      // DETERMINE TEST NOTIFICATION
      // =================================================

      final bool isTestNotification =
          message.data['type'] == 'test';

      // =================================================
      // DETERMINE HISTORY TYPE
      // =================================================

      final String notificationType =
          message.data['type'] == 'alert'
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
          id: message.messageId ??
              DateTime.now()
                  .millisecondsSinceEpoch
                  .toString(),
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
        id: message.messageId?.hashCode ??
            DateTime.now().millisecondsSinceEpoch,
        title: title,
        body: body,
        isTestNotification: isTestNotification,
      );

      print('Local notification displayed.');

      print('================================');
    },
  );
}

// =====================================================
// MAIN
// =====================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ===================================================
  // FIREBASE
  //
  // Firebase initialization is kept before runApp()
  // because the application pages use Firebase.
  // Firebase initialization itself does not require an
  // active internet connection.
  // ===================================================

  await Firebase.initializeApp();

  // ===================================================
  // REGISTER BACKGROUND HANDLER
  // ===================================================

  FirebaseMessaging.onBackgroundMessage(
    firebaseMessagingBackgroundHandler,
  );

  // ===================================================
  // START APP
  //
  // IMPORTANT:
  // The app starts BEFORE notification permission,
  // FCM topic subscription, and FCM token retrieval.
  //
  // This prevents the splash screen from being held
  // when there is no Wi-Fi or mobile data.
  // ===================================================

  runApp(const MyApp());

  // ===================================================
  // INITIALIZE FCM SERVICES AFTER APP START
  //
  // These operations are intentionally not awaited.
  // They can continue in the background while the
  // application UI is already running.
  // ===================================================

  initializeFirebaseMessagingServices();
}

// =====================================================
// GLOBAL DARK MODE
// =====================================================
//
// Dark mode is now permanently enabled.
// The notifier is kept so existing files that reference
// isDarkModeNotifier do not break.
// =====================================================

final ValueNotifier<bool> isDarkModeNotifier =
    ValueNotifier<bool>(true);

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
      // DARK THEME ONLY
      // =================================================

      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor:
            const Color(0xFF212121),
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
  State<BottomNavPage> createState() =>
      _BottomNavPageState();
}

class _BottomNavPageState
    extends State<BottomNavPage> {

  // ===================================================
  // START ON HOME
  //
  // 0 = Evacuate
  // 1 = Map
  // 2 = Home
  // 3 = Notifications
  // 4 = Menu
  // ===================================================

  int _currentIndex = 2;

  final GlobalKey<CurvedNavigationBarState> _navKey =
      GlobalKey<CurvedNavigationBarState>();

  // ===================================================
  // TABS
  // ===================================================

  final List<Widget> _tabs = const [
    EvacuateTab(),
    MapTab(),
    HomeTab(),
    NotificationTab(),
    MenuTab(),
  ];

  @override
  Widget build(BuildContext context) {

    // =================================================
    // NAVIGATION COLORS
    // =================================================

    final Color navBackground =
        const Color(0xFF212121);

    final Color barColor =
        const Color(0xFF303030);

    // =================================================
    // ICON COLORS
    // =================================================

    final Color iconColor =
        Colors.white;

    // =================================================
    // SELECTED BUTTON
    // =================================================

    final Color selectedButtonColor =
        const Color(0xFF424242);

    final Color selectedIconColor =
        Colors.white;

    return Scaffold(
      backgroundColor: navBackground,

      // =================================================
      // CURRENT TAB
      //
      // IndexedStack keeps all tabs alive instead of
      // destroying HomeTab when another tab is selected.
      // =================================================

      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),

      // =================================================
      // BOTTOM NAVIGATION
      // =================================================

      bottomNavigationBar: Container(
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

                backgroundColor:
                    navBackground,

                color:
                    barColor,

                // =================================================
                // SELECTED ICON CIRCLE
                // =================================================

                buttonBackgroundColor:
                    selectedButtonColor,

                // =================================================
                // ANIMATION
                // =================================================

                animationDuration:
                    const Duration(
                  milliseconds: 350,
                ),

                animationCurve:
                    Curves.easeInOut,

                // =================================================
                // ICONS
                // =================================================

                items: [

                  // =================================================
                  // EVACUATE
                  // =================================================

                  Icon(
                    Icons.directions_run,
                    size: 26,
                    color:
                        _currentIndex == 0
                            ? selectedIconColor
                            : iconColor,
                  ),

                  // =================================================
                  // MAP
                  // =================================================

                  Icon(
                    Icons.map,
                    size: 26,
                    color:
                        _currentIndex == 1
                            ? selectedIconColor
                            : iconColor,
                  ),

                  // =================================================
                  // HOME
                  // =================================================

                  Icon(
                    Icons.home,
                    size: 26,
                    color:
                        _currentIndex == 2
                            ? selectedIconColor
                            : iconColor,
                  ),

                  // =================================================
                  // NOTIFICATIONS
                  // =================================================

                  ValueListenableBuilder<int>(
                    valueListenable:
                        unreadNotificationCount,

                    builder: (
                      context,
                      unreadCount,
                      child,
                    ) {
                      return Stack(
                        clipBehavior:
                            Clip.none,

                        children: [

                          Icon(
                            Icons
                                .notifications_none_rounded,
                            size: 26,
                            color:
                                _currentIndex == 3
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

                              child:
                                  Container(
                                constraints:
                                    const BoxConstraints(
                                  minWidth: 18,
                                  minHeight: 18,
                                ),

                                padding:
                                    const EdgeInsets
                                        .symmetric(
                                  horizontal: 4,
                                ),

                                decoration:
                                    BoxDecoration(
                                  color:
                                      Colors.red,

                                  borderRadius:
                                      BorderRadius
                                          .circular(
                                    20,
                                  ),

                                  border:
                                      Border.all(
                                    color:
                                        Colors.white,
                                    width: 1.5,
                                  ),
                                ),

                                child: Text(
                                  unreadCount >
                                          99
                                      ? '99+'
                                      : unreadCount
                                          .toString(),

                                  textAlign:
                                      TextAlign.center,

                                  style:
                                      const TextStyle(
                                    color:
                                        Colors.white,
                                    fontSize:
                                        10,
                                    fontWeight:
                                        FontWeight.bold,
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
                    size: 26,
                    color:
                        _currentIndex == 4
                            ? selectedIconColor
                            : iconColor,
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

                  Expanded(
                    child: _buildLabel(
                      'Tools',
                      0,
                    ),
                  ),

                  Expanded(
                    child: _buildLabel(
                      'Map',
                      1,
                    ),
                  ),

                  Expanded(
                    child: _buildLabel(
                      'Home',
                      2,
                    ),
                  ),

                  Expanded(
                    child: _buildLabel(
                      'Notifications',
                      3,
                    ),
                  ),

                  Expanded(
                    child: _buildLabel(
                      'Menu',
                      4,
                    ),
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
  // NAVIGATION LABEL
  // =====================================================

  Widget _buildLabel(
    String label,
    int index,
  ) {
    final bool isSelected =
        _currentIndex == index;

    return Center(
      child: Text(
        label,

        maxLines: 1,

        overflow:
            TextOverflow.ellipsis,

        textAlign:
            TextAlign.center,

        style: TextStyle(
          fontSize: 10,

          fontWeight:
              isSelected
                  ? FontWeight.bold
                  : FontWeight.w500,

          color:
              isSelected
                  ? Colors.white
                  : Colors.white70,
        ),
      ),
    );
  }
}

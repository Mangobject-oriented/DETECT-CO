import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:detectco/pages/home.dart';
import 'package:detectco/pages/map.dart';
import 'package:detectco/pages/evacuate.dart';

// =====================================================
// LOCAL NOTIFICATIONS
// =====================================================

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// =====================================================
// BACKGROUND FCM HANDLER
// =====================================================

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(
    RemoteMessage message) async {
  await Firebase.initializeApp();

  print('Background notification received!');
  print('Title: ${message.notification?.title}');
  print('Body: ${message.notification?.body}');
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
  // BACKGROUND FCM
  // ===================================================

  FirebaseMessaging.onBackgroundMessage(
    firebaseMessagingBackgroundHandler,
  );

  // ===================================================
  // LOCAL NOTIFICATION INITIALIZATION
  // ===================================================

  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings =
      InitializationSettings(
    android: androidSettings,
  );

  await flutterLocalNotificationsPlugin.initialize(
    settings: initializationSettings,
  );

  // ===================================================
  // ANDROID NOTIFICATION CHANNEL
  // ===================================================

  const AndroidNotificationChannel channel =
      AndroidNotificationChannel(
    'class_alerts',
    'Class Alerts',
    description:
        'Notifications for class suspension announcements.',
    importance: Importance.max,
    playSound: true,
  );

  final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
      flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

  await androidPlugin?.createNotificationChannel(channel);

  // ===================================================
  // REQUEST NOTIFICATION PERMISSION
  // ===================================================

  final FirebaseMessaging messaging =
      FirebaseMessaging.instance;

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

  // ===================================================
  // GET FCM TOKEN
  // ===================================================

  print('FCM: Getting token...');

  try {
    final String? token = await messaging.getToken();

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
      print('NOTIFICATION RECEIVED!');
      print(
        'Title: ${message.notification?.title}',
      );
      print(
        'Body: ${message.notification?.body}',
      );
      print('================================');

      final RemoteNotification? notification =
          message.notification;

      if (notification == null) {
        return;
      }

      await flutterLocalNotificationsPlugin.show(
        id: notification.hashCode,
        title: notification.title ?? 'DETECT CO',
        body: notification.body ?? '',
        notificationDetails:
            const NotificationDetails(
          android: AndroidNotificationDetails(
            'class_alerts',
            'Class Alerts',
            channelDescription:
                'Notifications for class suspension announcements.',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
          ),
        ),
      );
    },
  );

  // ===================================================
  // START APP
  // ===================================================

  runApp(const MyApp());
}

// =====================================================
// GLOBAL DARK MODE
// =====================================================

final ValueNotifier<bool> isDarkModeNotifier =
    ValueNotifier<bool>(false);

// =====================================================
// APP
// =====================================================

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDarkModeNotifier,
      builder: (context, isDarkMode, child) {
        return MaterialApp(
          title: 'DETECT CO',
          debugShowCheckedModeBanner: false,

          theme: ThemeData(
            brightness: Brightness.light,
            primarySwatch: Colors.blue,
            scaffoldBackgroundColor: Colors.white,
          ),

          darkTheme: ThemeData(
            brightness: Brightness.dark,
            scaffoldBackgroundColor:
                const Color(0xFF212121),
          ),

          themeMode:
              isDarkMode
                  ? ThemeMode.dark
                  : ThemeMode.light,

          home: const BottomNavPage(),
        );
      },
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
  int _currentIndex = 0;

  final List<Widget> _tabs = const [
    HomeTab(),
    MapTab(),
    EvacuateTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _tabs[_currentIndex],

      bottomNavigationBar:
          BottomNavigationBar(
        backgroundColor:
            Theme.of(context).brightness ==
                    Brightness.dark
                ? const Color(0xFF303030)
                : Colors.white,

        currentIndex: _currentIndex,

        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(
              Icons.directions_run,
            ),
            label: 'Evacuate',
          ),
        ],

        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },

        selectedItemColor:
            const Color(0xFF0353A4),

        unselectedItemColor:
            Colors.grey,
      ),
    );
  }
}
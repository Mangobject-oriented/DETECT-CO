import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:detectco/pages/home.dart';
import 'package:detectco/pages/map.dart';
import 'package:detectco/pages/evacuate.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  runApp(const MyApp());
}

// =====================================================
// GLOBAL DARK MODE
// =====================================================

final ValueNotifier<bool> isDarkModeNotifier = ValueNotifier<bool>(false);

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
            scaffoldBackgroundColor: const Color(0xFF212121),
          ),

          themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,

          home: const BottomNavPage(),
        );
      },
    );
  }
}

class BottomNavPage extends StatefulWidget {
  const BottomNavPage({super.key});

  @override
  State<BottomNavPage> createState() => _BottomNavPageState();
}

class _BottomNavPageState extends State<BottomNavPage> {
  int _currentIndex = 0;

  final GlobalKey<CurvedNavigationBarState> _navKey =
      GlobalKey<CurvedNavigationBarState>();

  final List<Widget> _tabs = const [
    HomeTab(),
    MapTab(),
    EvacuateTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isDarkModeNotifier,
      builder: (context, isDarkMode, child) {
        final Color navBackground =
            isDarkMode ? const Color(0xFF212121) : Colors.white;
        final Color barColor =
            isDarkMode ? const Color(0xFF303030) : const Color(0xFF0353A4);
        final Color iconColor =
            isDarkMode ? Colors.white70 : Colors.white;

        return Scaffold(
          backgroundColor: navBackground,
          body: _tabs[_currentIndex],

          bottomNavigationBar: CurvedNavigationBar(
            key: _navKey,
            index: _currentIndex,
            height: 55,
            backgroundColor: navBackground, // shows behind the curve
            color: barColor, // the curved bar itself
            buttonBackgroundColor: barColor,
            animationDuration: const Duration(milliseconds: 350),
            animationCurve: Curves.easeInOut,
            items: [
              Icon(Icons.home, size: 26, color: iconColor),
              Icon(Icons.map, size: 26, color: iconColor),
              Icon(Icons.directions_run, size: 26, color: iconColor),
            ],
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
          ),
        );
      },
    );
  }
}
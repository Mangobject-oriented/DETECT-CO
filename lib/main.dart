import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart'; // ✅ REQUIRED FOR FIREBASE
import 'package:detectco/pages/home.dart';  
import 'package:detectco/pages/map.dart';   

void main() async {
  WidgetsFlutterBinding.ensureInitialized(); // ✅ REQUIRED BEFORE INITIALIZATION
  await Firebase.initializeApp(); // ✅ INITIALIZE FIREBASE
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DETECT CO',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const BottomNavPage(),
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

  final List<Widget> _tabs = [
    const HomeTab(),   
    const MapTab(),  
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _tabs[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
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
        ],
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        selectedItemColor: const Color(0xFF0353A4),
        unselectedItemColor: Colors.grey,
      ),
    );
  }
}
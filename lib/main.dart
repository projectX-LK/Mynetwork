import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const LocalCastApp());
}

class LocalCastApp extends StatelessWidget {
  const LocalCastApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LocalCast',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.orange,
        scaffoldBackgroundColor: const Color(0xFF0B101C),
      ),
      home: const HomeScreen(),
    );
  }
}

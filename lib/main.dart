import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const FormatConverterApp());
}

class FormatConverterApp extends StatelessWidget {
  const FormatConverterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '全能格式转换',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
        fontFamily: 'Noto Sans SC',
      ),
      home: const HomeScreen(),
    );
  }
}

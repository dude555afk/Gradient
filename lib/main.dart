import 'package:flutter/material.dart';

import 'features/home/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GradientApp());
}

class GradientApp extends StatelessWidget {
  const GradientApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF8F8CFF);
    return MaterialApp(
      title: 'Gradient',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F7F9),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0D0D0F),
      ),
      home: const HomePage(),
    );
  }
}

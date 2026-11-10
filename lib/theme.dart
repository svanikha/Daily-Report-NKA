import 'package:flutter/material.dart';

const brandGreen = Color(0xFF008A4E);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: brandGreen, primary: brandGreen);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFFF5F7F6),
    appBarTheme: const AppBarTheme(
      backgroundColor: brandGreen,
      foregroundColor: Colors.white,
      centerTitle: false,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
      fillColor: Colors.white,
    ),
  );
}

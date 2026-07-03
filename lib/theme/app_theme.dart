import 'package:flutter/material.dart';
class AppTheme {
  // Legacy colors (kept for existing screens to not break them, but pink is removed)
  static const Color primaryBlue = Color(0xFF3B5998);
  static const Color textBlack = Color(0xFF1A1A1A);
  static const Color textGrey = Color(0xFF757575);
  static const Color bgWhite = Colors.white;
  static const Color bgLight = Color(0xFFF8F9FA);
  static const Color containerWhite = Color(0xFFFFFFFF);
  static const Color inputBg = Color(0xFFF3F5F9);
  static const Color borderGrey = Color(0xFFE0E0E0);
  static const Color lightBlue = Color(0xFFE8EEF9);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: bgWhite,
      colorScheme: ColorScheme.light(
        primary: primaryBlue,
        secondary: primaryBlue,
        surface: bgWhite,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textBlack,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bgWhite,
        elevation: 0,
        iconTheme: IconThemeData(color: textBlack),
        titleTextStyle: TextStyle(
          color: textBlack,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          color: textBlack,
          fontSize: 28,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
        titleLarge: TextStyle(
          color: textBlack,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(
          color: textBlack,
          fontSize: 16,
          fontWeight: FontWeight.normal,
        ),
        bodyMedium: TextStyle(
          color: textGrey,
          fontSize: 14,
          fontWeight: FontWeight.normal,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFCCCCCC),
          disabledForegroundColor: const Color(0xFF888888),
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: primaryBlue, width: 1.5),
        ),
        hintStyle: const TextStyle(
          color: textGrey,
          fontSize: 16,
        ),
      ),
    );
  }
}

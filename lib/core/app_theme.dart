import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global tema — yorug' (oq/ko'k) va qorong'i rejim.
/// Ranglar `AppTheme.bg`, `AppTheme.card`, `AppTheme.accent` ... orqali olinadi.
/// Almashtirilganda `notifyListeners` chaqiriladi; ekranlar AnimatedBuilder bilan yangilanadi.
class AppTheme extends ChangeNotifier {
  AppTheme._();
  static final AppTheme instance = AppTheme._();

  bool _isDark = false; // boshlang'ich: YORUG' (oq/ko'k)
  bool get isDark => _isDark;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _isDark = p.getBool('app_dark') ?? false;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> toggle() async {
    _isDark = !_isDark;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('app_dark', _isDark);
    } catch (_) {}
  }

  // ── Ranglar (statik — kodda AppTheme.bg deb ishlatiladi) ──
  static bool get dark => instance._isDark;

  // Sahifa foni
  static Color get bg => instance._isDark ? const Color(0xFF0F1726) : const Color(0xFFEFF4FC);
  // Karta / yuza
  static Color get card => instance._isDark ? const Color(0xFF18233A) : Colors.white;
  // Asosiy accent — ko'k
  static Color get accent => instance._isDark ? const Color(0xFF3B82F6) : const Color(0xFF2F80ED);
  // Och ko'k yumshoq fon (chip, belgi)
  static Color get accentSoft => instance._isDark ? const Color(0xFF1E2C4A) : const Color(0xFFE6F0FF);
  // Asosiy matn
  static Color get text => instance._isDark ? Colors.white : const Color(0xFF14233B);
  // Yumshoq matn (izoh, label)
  static Color get textSoft => instance._isDark ? const Color(0xFF9AA6B8) : const Color(0xFF64748B);
  // Chegara / chiziq
  static Color get border => instance._isDark ? const Color(0x1AFFFFFF) : const Color(0xFFD8E3F3);
  // Accent ustidagi matn (tugma) — har doim oq
  static Color get onAccent => Colors.white;
}

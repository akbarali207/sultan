import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global tema — yorug' va qorong'i rejim + dizayn-tizim tokenlari.
/// Ranglar `AppTheme.bg`, `AppTheme.card`, `AppTheme.accent` ... orqali olinadi.
/// Almashtirilganda `notifyListeners` chaqiriladi; ekranlar AnimatedBuilder bilan yangilanadi.
/// DIZAYN: faqat KO'RINISH tokenlari — biznes-mantiqqa aloqasi yo'q.
class AppTheme extends ChangeNotifier {
  AppTheme._();
  static final AppTheme instance = AppTheme._();

  bool _isDark = false; // boshlang'ich: YORUG'
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

  static bool get dark => instance._isDark;
  static bool get _d => instance._isDark;

  // ── SURFACES (yuzalar) ──
  static Color get bg   => _d ? const Color(0xFF0B1120) : const Color(0xFFF4F6FB);
  static Color get bg2  => _d ? const Color(0xFF0F1830) : const Color(0xFFF1F5FB); // vtorichniy fon
  static Color get card => _d ? const Color(0xFF141E33) : Colors.white;

  // ── ACCENT (asosiy) ──
  static Color get accent     => _d ? const Color(0xFF3B82F6) : const Color(0xFF2563EB);
  static Color get accentSoft => _d ? const Color(0x2E3B82F6) : const Color(0xFFEAF1FE);

  // ── TEXT ──
  static Color get text     => _d ? const Color(0xFFF1F5F9) : const Color(0xFF0F1B33);
  static Color get textSoft => _d ? const Color(0xFF8A9BB5) : const Color(0xFF69748C);

  // ── LINES ──
  static Color get border => _d ? const Color(0x17FFFFFF) : const Color(0xFFEAEEF6);
  static Color get track  => _d ? const Color(0xFF1B2540) : const Color(0xFFEDF1F8); // progress trek

  // ── ON ACCENT (tugma matni) ──
  static Color get onAccent => Colors.white;

  // ── SEMANTIK ranglar (ikkala temada bir xil) ──
  static const Color success = Color(0xFF10B981); // kirim / to'langan / bo'sh
  static const Color danger  = Color(0xFFF43F5E); // chiqim / bekor / band
  static const Color warning = Color(0xFFF59E0B); // qarz / ogohlantirish
  static const Color violet  = Color(0xFF8B5CF6); // qo'shimcha metrika
  static const Color sky     = Color(0xFF0EA5E9);
  static Color get successSoft => _d ? const Color(0x2610B981) : const Color(0xFFE7F8F1);
  static Color get dangerSoft  => _d ? const Color(0x26F43F5E) : const Color(0xFFFDECEF);
  static Color get warningSoft => _d ? const Color(0x26F59E0B) : const Color(0xFFFEF3E2);

  // ── TENI (soft, Material elevation emas) ──
  static List<BoxShadow> get cardShadow => [
        BoxShadow(blurRadius: 22, offset: const Offset(0, 8),
            color: _d ? const Color(0x40000000) : const Color(0x0F14234B)),
      ];
  static List<BoxShadow> get softShadow => [
        BoxShadow(blurRadius: 14, offset: const Offset(0, 5),
            color: _d ? const Color(0x33000000) : const Color(0x0A14234B)),
      ];

  // ── RADIUSLAR ──
  static const double rLg = 20, rTile = 18, rMd = 16, rSm = 14, rPill = 999, rSheet = 26;

  // ── HERO gradient (ekran shapkalari) ──
  static const LinearGradient hero = LinearGradient(
    begin: Alignment.topLeft, end: Alignment.bottomRight,
    colors: [Color(0xFF4338CA), Color(0xFF2563EB)]);

  // ── SHRIFT (lokal bundle qilinmaguncha system; keyin 'Plus Jakarta Sans') ──
  static const String? fontFamily = null;
  /// Pul/metrika raqamlari uchun — mo ­noshirin raqamlar
  static const List<FontFeature> tnum = [FontFeature.tabularFigures()];
}

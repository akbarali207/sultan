import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'core/app_theme.dart';
import 'core/lang.dart';
import 'core/api_service.dart';
import 'screens/login_screen.dart';

// Global navigator — 401 (sessiya tugadi) da istalgan joydan login ga qaytish uchun
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Eslatma: Firebase OLIB TASHLANDI (2026-07-14). Loyiha local-first — baza
  // gibrid (bulut PostgreSQL + lokal POS-PC), ApiService.resolveBase orqali
  // lokal Wi-Fi ↔ internet almashadi; Firebase'ga bog'liq emas edi (bo'sh init).
  // Push-bildirishnoma kerak bo'lsa: firebase_core + firebase_messaging birga qo'shiladi.

  await AppTheme.instance.load();
  await Lang.instance.load();

  // Server manzilini aniqlaymiz: restoran Wi-Fi'sida lokal POS-PC bo'lsa — lokal
  // (internetsiz ham ishlaydi), aks holda internet. Xato bo'lsa ham ilova ochiladi.
  try {
    await ApiService.resolveBase();
  } catch (_) {}

  // Token muddati o'tsa (401) — ilova avtomatik login ekraniga qaytadi
  // (aks holda ro'yxatlar jimgina bo'sh qolib, smena to'xtab qolardi).
  ApiService.onUnauthorized = () {
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  };

  runApp(const SultanApp());
}

class SultanApp extends StatelessWidget {
  const SultanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      // Tema yoki til o'zgarganda butun ilova qayta quriladi
      child: AnimatedBuilder(
        animation: Listenable.merge([AppTheme.instance, Lang.instance]),
        builder: (context, _) => MaterialApp(
          title: 'Sultan Restoran',
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            scaffoldBackgroundColor: AppTheme.bg,
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppTheme.accent,
              brightness: AppTheme.dark ? Brightness.dark : Brightness.light,
            ),
          ),
          home: const LoginScreen(),
        ),
      ),
    );
  }
}

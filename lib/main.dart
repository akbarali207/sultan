import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'providers/auth_provider.dart';
import 'core/app_theme.dart';
import 'core/lang.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase FAQAT Android va Web'da (FCM/bildirishnomalar uchun poydevor).
  // Windows kassalarida ISHLATILMAYDI — u yerda SDK beta va kassaga xavf.
  // Firebase ishga tushmasa ham ilova baribir ochiladi (kassa Firebase'ga bog'liq emas).
  if (kIsWeb || defaultTargetPlatform == TargetPlatform.android) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    } catch (e) {
      debugPrint('Firebase ishga tushmadi (ilova baribir ishlaydi): $e');
    }
  }

  await AppTheme.instance.load();
  await Lang.instance.load();
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

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../core/app_theme.dart';
import '../core/lang.dart';
import '../core/api_service.dart';
import 'admin/admin_screen.dart';
import 'waiter/waiter_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoadingBiometric = false;
  bool _hasBiometric = false;
  final LocalAuthentication _localAuth = LocalAuthentication();

  @override
  void initState() {
    super.initState();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final token = prefs.getString('token');
    final biometricEnabled = prefs.getBool('biometric_enabled') ?? false;

    if (token != null && biometricEnabled) {
      setState(() => _hasBiometric = true);
      _authenticateWithBiometric();
    }
  }

  Future<void> _authenticateWithBiometric() async {
    setState(() => _isLoadingBiometric = true);
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!mounted) return;
      if (!canCheck) {
        setState(() => _isLoadingBiometric = false);
        return;
      }
      final authenticated = await _localAuth.authenticate(
        localizedReason: tr('Sultan Restoranga kirish uchun tasdiqlang'),
        options: const AuthenticationOptions(
          biometricOnly: false,
          stickyAuth: true,
        ),
      );
      if (!mounted) return;
      if (authenticated) {
        final prefs = await SharedPreferences.getInstance();
        // Rolni JWT token payload'idan olamiz (sessiyaning haqiqiy manbasi) —
        // alohida 'user_role' pref eskirib noto'g'ri ekranga yo'naltirishi mumkin.
        final role = _roleFromToken(prefs.getString('token')) ??
            (prefs.getString('user_role') ?? '');
        _navigateByRole(role);
      }
    } catch (e) {
      debugPrint('Biometric xato: $e');
    } finally {
      if (mounted) setState(() => _isLoadingBiometric = false);
    }
  }

  Future<void> _login() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final error = await auth.login(
      _phoneController.text.trim(),
      _passwordController.text.trim(),
    );
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red),
      );
      return;
    }

    // Biometric taklif qilish (web/desktop'da qo'llab-quvvatlanmasligi mumkin — xatoni yutamiz)
    bool canCheck = false;
    try {
      canCheck = await _localAuth.canCheckBiometrics;
    } catch (_) {
      canCheck = false;
    }
    if (canCheck) {
      _showBiometricDialog(auth.role ?? '');
    } else {
      _navigateByRole(auth.role ?? '');
    }
  }

  void _showBiometricDialog(String role) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(
          tr('Face ID / Fingerprint'),
          style: TextStyle(color: AppTheme.text),
        ),
        content: Text(
          tr('Keyingi safar Face ID yoki barmoq izi bilan kirishni xohlaysizmi?'),
          style: TextStyle(color: AppTheme.textSoft),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateByRole(role);
            },
            child: Text(tr('Yo\'q'), style: TextStyle(color: AppTheme.textSoft)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
            ),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('biometric_enabled', true);
              await prefs.setString('user_role', role);
              Navigator.pop(context);
              _navigateByRole(role);
            },
            child: Text(tr('Ha, yoqish'), style: TextStyle(color: AppTheme.onAccent)),
          ),
        ],
      ),
    );
  }

  /// JWT (header.payload.signature) payload'idagi `role` ni qaytaradi.
  /// Token yaroqsiz/yo'q bo'lsa null.
  String? _roleFromToken(String? token) {
    if (token == null) return null;
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      switch (payload.length % 4) {
        case 2:
          payload += '==';
          break;
        case 3:
          payload += '=';
          break;
      }
      final decoded = jsonDecode(utf8.decode(base64.decode(payload)));
      final role = decoded is Map ? decoded['role'] : null;
      return (role is String && role.isNotEmpty) ? role : null;
    } catch (_) {
      return null;
    }
  }

  void _navigateByRole(String role) {
    if (role == 'admin' || role == 'director' || role == 'guest') {
      // guest = SUPER-ADMIN (yashirin egasi), director = nazorat. Ikkalasi ham to'liq
      // ko'rishga (admin paneli) tushadi. guest'da qo'shimcha STOP tugmasi bo'ladi.
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AdminScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const WaiterScreen()),
      );
    }
  }

  // Server manzili sozlamasi — restoran ichida internetsiz ishlash uchun POS-PC IP'si.
  Future<void> _showServerSettings() async {
    final current = await ApiService.getLocalServer();
    String initial = '';
    if (current != null) {
      final u = Uri.tryParse(current);
      if (u != null && u.host.isNotEmpty) initial = u.hasPort ? '${u.host}:${u.port}' : u.host;
    }
    final ctrl = TextEditingController(text: initial);
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('Server sozlamasi'), style: TextStyle(color: AppTheme.text, fontSize: 17)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            tr('Restoran ichida internetsiz ishlash uchun POS-PC manzilini kiriting (masalan 192.168.1.10). Bo\'sh qoldirsangiz — faqat internet orqali ishlaydi.'),
            style: TextStyle(color: AppTheme.textSoft, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: ctrl,
            style: TextStyle(color: AppTheme.text),
            decoration: InputDecoration(
              labelText: tr('POS-PC manzili (IP)'),
              hintText: '192.168.1.10',
              labelStyle: TextStyle(color: AppTheme.textSoft),
              prefixIcon: Icon(Icons.dns, color: AppTheme.accent),
              enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
              focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.accent)),
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Icon(Icons.circle, size: 10, color: ApiService.mode == 'local' ? Colors.green : Colors.orange),
            const SizedBox(width: 6),
            Text(
              ApiService.mode == 'local' ? tr('Hozir: lokal (Wi-Fi)') : tr('Hozir: internet'),
              style: TextStyle(color: AppTheme.textSoft, fontSize: 12),
            ),
          ]),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
            onPressed: () async {
              final v = ctrl.text.trim();
              await ApiService.setLocalServer(v.isEmpty ? null : v);
              if (!mounted) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(ApiService.mode == 'local'
                    ? tr('Lokal server topildi ✓ (internetsiz ishlaydi)')
                    : tr('Lokal topilmadi — internet orqali ishlaydi')),
                backgroundColor: ApiService.mode == 'local' ? Colors.green : Colors.orange,
              ));
            },
            child: Text(tr('Saqlash va sinash'), style: TextStyle(color: AppTheme.onAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Stack(children: [
        Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.restaurant, size: 80, color: AppTheme.accent),
              const SizedBox(height: 16),
              Text(
                tr('Sultan Restoran'),
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: AppTheme.text),
              ),
              const SizedBox(height: 8),
              Text(tr('Tizimga kirish'),
                  style: TextStyle(color: AppTheme.textSoft, fontSize: 16)),
              const SizedBox(height: 40),

              // Biometric tugma
              if (_hasBiometric) ...[
                GestureDetector(
                  onTap: _isLoadingBiometric ? null : _authenticateWithBiometric,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.card,
                      border: Border.all(color: AppTheme.accent, width: 2),
                    ),
                    child: _isLoadingBiometric
                        ? CircularProgressIndicator(color: AppTheme.accent)
                        : Icon(Icons.face, size: 60, color: AppTheme.accent),
                  ),
                ),
                const SizedBox(height: 16),
                Text(tr('Kirish uchun bosing'),
                    style: TextStyle(color: AppTheme.textSoft, fontSize: 14)),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => setState(() => _hasBiometric = false),
                  child: Text(tr('Parol bilan kirish'),
                      style: TextStyle(color: AppTheme.accent)),
                ),
              ] else ...[
                TextField(
                  controller: _phoneController,
                  style: TextStyle(color: AppTheme.text),
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: tr('Telefon raqam'),
                    labelStyle: TextStyle(color: AppTheme.textSoft),
                    prefixIcon: Icon(Icons.phone, color: AppTheme.accent),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppTheme.textSoft),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppTheme.accent),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  style: TextStyle(color: AppTheme.text),
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: tr('Parol'),
                    labelStyle: TextStyle(color: AppTheme.textSoft),
                    prefixIcon: Icon(Icons.lock, color: AppTheme.accent),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility : Icons.visibility_off,
                        color: AppTheme.textSoft,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppTheme.textSoft),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppTheme.accent),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: auth.isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: auth.isLoading
                        ? CircularProgressIndicator(color: AppTheme.onAccent)
                        : Text(tr('Kirish'),
                        style: TextStyle(fontSize: 18, color: AppTheme.onAccent)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
        Positioned(
          top: 8,
          right: 8,
          child: SafeArea(
            child: IconButton(
              tooltip: tr('Server sozlamasi'),
              icon: Icon(Icons.dns_outlined, color: AppTheme.textSoft),
              onPressed: _showServerSettings,
            ),
          ),
        ),
      ]),
    );
  }
}
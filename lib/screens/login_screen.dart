import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../core/api_service.dart';
import '../core/constants.dart';
import '../core/app_theme.dart';
import '../core/lang.dart';
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
      if (authenticated) {
        final prefs = await SharedPreferences.getInstance();
        final role = prefs.getString('user_role') ?? '';
        _navigateByRole(role);
      }
    } catch (e) {
      print('Biometric xato: $e');
    } finally {
      setState(() => _isLoadingBiometric = false);
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

  void _navigateByRole(String role) {
    if (role == 'admin') {
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

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Center(
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
    );
  }
}
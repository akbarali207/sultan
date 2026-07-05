import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/api_service.dart';
import '../core/constants.dart';

class AuthProvider extends ChangeNotifier {
  String? _token;
  Map<String, dynamic>? _user;
  bool _isLoading = false;

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _token != null;
  String? get role => _user?['role'];

  Future<void> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    notifyListeners();
  }

  Future<String?> login(String phone, String password) async {
    _isLoading = true;
    notifyListeners();
    try {
      final response = await ApiService.post(AppConstants.login, {
        'phone': phone,
        'password': password,
      });

      if (response is Map && response['token'] != null) {
        _token = response['token'];
        _user = Map<String, dynamic>.from(response['user']);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', _token!);
        notifyListeners();
        return null;
      }
      return response['message'] ?? 'Xato yuz berdi!';
    } catch (e) {
      return 'Server bilan ulanishda xato: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    _token = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    // Faqat SESSIYA ma'lumotlari o'chadi. Qurilma sozlamalari (printer_name,
    // printer_url, tema va h.k.) saqlanib qoladi — prefs.clear() ULARNI HAM
    // o'chirib yuborardi.
    await prefs.remove('token');
    await prefs.remove('user_role');
    await prefs.remove('user_id');
    await prefs.remove('biometric_enabled'); // keshlangan rol o'chdi — biometrik kirish ham qayta sozlanadi
    notifyListeners();
  }
}
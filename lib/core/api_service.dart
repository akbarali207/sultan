import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'constants.dart';

/// Server yoki tarmoq xatosi. `statusCode == null` — tarmoqqa ulanib bo'lmadi.
class ApiException implements Exception {
  final int? statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  bool get isNetwork => statusCode == null;
  @override
  String toString() => message;
}

class ApiService {
  static const Duration _timeout = Duration(seconds: 15);

  /// Token muddati o'tganda (HTTP 401) chaqiriladi — ilova login ekraniga qaytadi.
  /// main.dart da o'rnatiladi. Shu bo'lmasa 401 da ro'yxatlar jimgina bo'sh qolardi.
  static void Function()? onUnauthorized;
  static bool _unauthHandling = false;

  static Future<void> _fireUnauthorized() async {
    if (_unauthHandling || onUnauthorized == null) return;
    _unauthHandling = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      // Faqat SESSIYA bor edi (token) bo'lsa login ga qaytaramiz —
      // login urinishidagi 401 (parol xato) ni chalg'itmaymiz.
      if (prefs.getString('token') != null) {
        await prefs.remove('token');
        onUnauthorized!();
      }
    } catch (_) {}
    _unauthHandling = false;
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  static Future<Map<String, String>> getHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Pul operatsiyalari uchun idempotentlik kaliti — TUGMA BOSILGAN paytda
  /// yaratiladi. Xuddi shu kalit bilan takror so'rov serverda ikkinchi marta
  /// bajarilmaydi (saqlangan javob qaytadi).
  static String newIdempotencyKey() {
    final r = Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // UUID v4
    b[8] = (b[8] & 0x3f) | 0x80;
    String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
    return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
  }

  // ==== SERVER MANZILI: lokal (Wi-Fi) <-> internet AVTOMATIK almashinuvi ====
  // Restoran Wi-Fi'sida lokal POS-PC topilса — internet shart emas.
  static const String _localKey = 'local_server_url';
  static String _mode = 'remote'; // 'local' | 'remote' — UI ko'rsatishi uchun
  static String get mode => _mode;

  /// Saqlangan lokal server manzili (masalan http://192.168.1.10:3000/api) yoki null.
  static Future<String?> getLocalServer() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_localKey);
    return (v != null && v.trim().isNotEmpty) ? v.trim() : null;
  }

  /// Lokal server manzilini saqlaydi (bo'sh -> o'chiradi) va qayta aniqlaydi.
  static Future<void> setLocalServer(String? raw) async {
    final p = await SharedPreferences.getInstance();
    if (raw == null || raw.trim().isEmpty) {
      await p.remove(_localKey);
    } else {
      await p.setString(_localKey, normalizeServer(raw));
    }
    await resolveBase();
  }

  /// '192.168.1.10' | '192.168.1.10:3000' | 'http://...' -> 'http://192.168.1.10:3000/api'
  static String normalizeServer(String raw) {
    var s = raw.trim();
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'http://$s';
    final u = Uri.tryParse(s);
    if (u != null && u.host.isNotEmpty) {
      final port = u.hasPort ? u.port : 3000;
      s = '${u.scheme}://${u.host}:$port';
    }
    if (!s.endsWith('/api')) s = '$s/api';
    return s;
  }

  /// Ishga tushganda va tarmoq xatosida chaqiriladi. Lokal manzil javob berса —
  /// lokalga o'tadi (internetsiz ham ishlaydi), aks holda — internet (remote).
  static Future<void> resolveBase() async {
    final local = await getLocalServer();
    if (local == null) {
      AppConstants.baseUrl = AppConstants.remoteBaseUrl;
      _mode = 'remote';
      return;
    }
    final ok = await _probe(local);
    AppConstants.baseUrl = ok ? local : AppConstants.remoteBaseUrl;
    _mode = ok ? 'local' : 'remote';
  }

  static Future<bool> _probe(String base) async {
    try {
      final r = await http
          .get(Uri.parse('$base/health'))
          .timeout(const Duration(milliseconds: 1500));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Javobni tekshirib qaytaradi:
  ///  - 2xx-4xx: JSON body qaytadi (4xx da UI `message` maydonini ko'rsatadi)
  ///  - 5xx yoki JSON bo'lmagan javob: ApiException
  static dynamic _decode(http.Response response) {
    dynamic body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw ApiException(response.statusCode,
          'Server noto\'g\'ri javob berdi (HTTP ${response.statusCode})');
    }
    if (response.statusCode >= 500) {
      final msg = (body is Map && body['message'] != null)
          ? body['message'].toString()
          : 'Server xatosi (HTTP ${response.statusCode})';
      throw ApiException(response.statusCode, msg);
    }
    // Sessiya tugadi/token yaroqsiz — login ga qaytaramiz (fire-and-forget).
    // Body baribir qaytadi, chaqiruvchilar crash bo'lmaydi.
    if (response.statusCode == 401) {
      _fireUnauthorized();
    }
    return body;
  }

  /// So'rovni bajaradi. `retryOnce` — faqat xavfsiz holatlarda (GET yoki
  /// idempotency-key bor mutatsiya) tarmoq xatosida bir marta qayta urinadi.
  static Future<dynamic> _send(
    Future<http.Response> Function() request, {
    required bool retryOnce,
  }) async {
    try {
      return _decode(await request().timeout(_timeout));
    } on ApiException {
      rethrow;
    } catch (_) {
      if (!retryOnce) {
        resolveBase(); // keyingi so'rovga ishlaydigan manzilni fon rejimida tayyorlaymiz
        throw ApiException(null, 'Serverga ulanib bo\'lmadi — Wi-Fi yoki internetni tekshiring');
      }
      // Lokal <-> internet AVTOMATIK almashinuvi: joriy manzil ishlamadi,
      // ishlaydiganini topib (lokal yoki internet), qayta urinamiz.
      await resolveBase();
      await Future.delayed(const Duration(milliseconds: 300));
      try {
        return _decode(await request().timeout(_timeout));
      } on ApiException {
        rethrow;
      } catch (_) {
        throw ApiException(null, 'Serverga ulanib bo\'lmadi — Wi-Fi yoki internetni tekshiring');
      }
    }
  }

  static Future<dynamic> get(String endpoint) async {
    final headers = await getHeaders();
    return _send(
      () => http.get(Uri.parse('${AppConstants.baseUrl}$endpoint'), headers: headers),
      retryOnce: true, // GET har doim xavfsiz
    );
  }

  /// Pul operatsiyalarida `idempotencyKey` BERILISHI SHART (newIdempotencyKey
  /// bilan tugma bosilganda yarating) — shunda tarmoq uzilib retry bo'lsa ham
  /// zakaz/to'lov ikki marta yaratilmaydi.
  static Future<dynamic> post(String endpoint, Map<String, dynamic> body,
      {String? idempotencyKey}) async {
    final headers = await getHeaders();
    if (idempotencyKey != null) headers['Idempotency-Key'] = idempotencyKey;
    return _send(
      () => http.post(Uri.parse('${AppConstants.baseUrl}$endpoint'),
          headers: headers, body: jsonEncode(body)),
      retryOnce: idempotencyKey != null,
    );
  }

  static Future<dynamic> put(String endpoint, Map<String, dynamic> body,
      {String? idempotencyKey}) async {
    final headers = await getHeaders();
    if (idempotencyKey != null) headers['Idempotency-Key'] = idempotencyKey;
    return _send(
      () => http.put(Uri.parse('${AppConstants.baseUrl}$endpoint'),
          headers: headers, body: jsonEncode(body)),
      retryOnce: idempotencyKey != null,
    );
  }

  static Future<dynamic> delete(String endpoint, {String? idempotencyKey}) async {
    final headers = await getHeaders();
    if (idempotencyKey != null) headers['Idempotency-Key'] = idempotencyKey;
    return _send(
      () => http.delete(Uri.parse('${AppConstants.baseUrl}$endpoint'), headers: headers),
      retryOnce: idempotencyKey != null,
    );
  }

  static Future<dynamic> putWithImage(
    String endpoint, {
    required String name,
    required double price,
    int? categoryId,
    bool isActive = true,
    int? stationId,
    List<int>? stationIds,
    List<int>? imageBytes,
    String imageFilename = 'image.jpg',
  }) async {
    final token = await getToken();
    final uri = Uri.parse('${AppConstants.baseUrl}$endpoint');
    final boundary = 'FlutterBoundary${DateTime.now().millisecondsSinceEpoch}';

    final body = <int>[];

    void addField(String fieldName, String value) {
      body.addAll('--$boundary\r\n'.codeUnits);
      body.addAll('Content-Disposition: form-data; name="$fieldName"\r\n\r\n'.codeUnits);
      body.addAll(utf8.encode(value));
      body.addAll('\r\n'.codeUnits);
    }

    addField('name', name);
    addField('price', price.toStringAsFixed(0));
    if (categoryId != null) addField('category_id', categoryId.toString());
    if (stationIds != null && stationIds.isNotEmpty) {
      addField('station_ids', stationIds.join(','));
    } else if (stationId != null) {
      addField('station_id', stationId.toString());
    }
    addField('is_active', isActive.toString());

    if (imageBytes != null) {
      final ext = imageFilename.split('.').last.toLowerCase();
      final mime = ext == 'png'
          ? 'image/png'
          : ext == 'webp'
              ? 'image/webp'
              : 'image/jpeg';
      body.addAll('--$boundary\r\n'.codeUnits);
      body.addAll('Content-Disposition: form-data; name="image"; filename="$imageFilename"\r\n'.codeUnits);
      body.addAll('Content-Type: $mime\r\n\r\n'.codeUnits);
      body.addAll(imageBytes);
      body.addAll('\r\n'.codeUnits);
    }

    body.addAll('--$boundary--\r\n'.codeUnits);

    final response = await http.put(
      uri,
      headers: {
        'Content-Type': 'multipart/form-data; boundary=$boundary',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: body,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Server xato ${response.statusCode}: ${response.body}');
    }

    return jsonDecode(response.body);
  }

  static Future<dynamic> postWithImage(
    String endpoint, {
    required String name,
    required double price,
    int? categoryId,
    List<int>? imageBytes,
    String imageFilename = 'image.jpg',
    String? type,
    int? ingredientId,
    int? stationId,
    List<int>? stationIds,
  }) async {
    final token = await getToken();
    final uri = Uri.parse('${AppConstants.baseUrl}$endpoint');
    // Unikal boundary
    final boundary = 'FlutterBoundary${DateTime.now().millisecondsSinceEpoch}';

    print('[postWithImage] URL: $uri');
    print('[postWithImage] token: ${token != null ? "mavjud (${token.length} belgi)" : "NULL!"}');
    print('[postWithImage] fields: name=$name price=${price.toStringAsFixed(0)} category_id=$categoryId type=$type');

    // Multipart body ni qo'lda yasaymiz
    final body = <int>[];

    // Matn maydon qo'shish yordamchisi
    void addField(String fieldName, String value) {
      body.addAll('--$boundary\r\n'.codeUnits);
      body.addAll('Content-Disposition: form-data; name="$fieldName"\r\n\r\n'.codeUnits);
      body.addAll(utf8.encode(value));
      body.addAll('\r\n'.codeUnits);
    }

    addField('name', name);
    addField('price', price.toStringAsFixed(0));
    if (categoryId != null) addField('category_id', categoryId.toString());
    if (type != null) addField('type', type);
    if (ingredientId != null) addField('ingredient_id', ingredientId.toString());
    if (stationIds != null && stationIds.isNotEmpty) {
      addField('station_ids', stationIds.join(','));
    } else if (stationId != null) {
      addField('station_id', stationId.toString());
    }

    if (imageBytes != null) {
      final ext = imageFilename.split('.').last.toLowerCase();
      final mime = ext == 'png'
          ? 'image/png'
          : ext == 'webp'
              ? 'image/webp'
              : 'image/jpeg';
      body.addAll('--$boundary\r\n'.codeUnits);
      body.addAll('Content-Disposition: form-data; name="image"; filename="$imageFilename"\r\n'.codeUnits);
      body.addAll('Content-Type: $mime\r\n\r\n'.codeUnits);
      body.addAll(imageBytes);
      body.addAll('\r\n'.codeUnits);
      print('[postWithImage] rasm: $imageFilename (${imageBytes.length} bytes, $mime)');
    } else {
      print('[postWithImage] rasm: yuq');
    }

    body.addAll('--$boundary--\r\n'.codeUnits);

    // http.post() ishlatamiz — Request sinfi headerlari to'g'ri ketadi
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'multipart/form-data; boundary=$boundary',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: body,
    );

    print('[postWithImage] statusCode: ${response.statusCode}');
    print('[postWithImage] body: ${response.body}');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Server xato ${response.statusCode}: ${response.body}');
    }

    return jsonDecode(response.body);
  }
}
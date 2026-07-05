import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:printing/printing.dart';
import '../../core/api_service.dart';
import '../../core/constants.dart';
import '../../core/app_theme.dart';
import '../../core/lang.dart';
import '../../core/receipt_printer.dart';
import '../../widgets/table_with_chairs.dart';
import '../../widgets/cashbox_view.dart';
import '../../widgets/orders_view.dart';
import '../../providers/auth_provider.dart';
import '../login_screen.dart';

class WaiterScreen extends StatefulWidget {
  const WaiterScreen({super.key});

  @override
  State<WaiterScreen> createState() => _WaiterScreenState();
}

class _WaiterScreenState extends State<WaiterScreen> {
  int _selectedIndex = 1; // ofitsant kirganda birinchi STOLLAR ochiladi

  // Data
  List<dynamic> _categories = [];
  List<dynamic> _items = [];
  List<dynamic> _tables = [];
  List<dynamic> _orders = [];       // pastki menyu badge soni uchun (to'lanmagan)
  List<dynamic> _rooms = [];
  int _ordersKey = 0;               // Zakazlar tabini ochganda OrdersView ni yangilash uchun
  int _kassaKey = 0;                // Kassa tabini ochganda CashboxView ni yangilash uchun
  Timer? _refreshTimer;             // avto-yangilanish (real-time'ga yaqin)

  // Faqat kassir (va admin) zakazni tugata (to'lov) oladi
  bool get _canComplete {
    final role = Provider.of<AuthProvider>(context, listen: false).user?['role']?.toString() ?? '';
    return role == 'cashier' || role == 'admin';
  }

  // Floor-plan: ofitsant ochgan xona (null = bino ko'rinishi)
  int? _selectedRoomId;

  // Tanlangan stol (menyu va zakaz uchun)
  int? _selectedTableId;
  int? _selectedTableNumber;

  // Cart: menu_item_id -> {item, qty}
  final Map<int, Map<String, dynamic>> _cart = {};

  // Menu master-detail: tanlangan kategoriya
  int? _selectedCatId;

  bool _isLoading = true;
  bool _sendingOrder = false; // zakaz yuborilmoqda — ikki marta bosishdan himoya

  // ─── TEMA (global AppTheme) ──────────────────────────────────────────────────
  bool get _isDark => AppTheme.dark;
  String? _printerName;

  Color get _bg => AppTheme.bg;
  Color get _card => AppTheme.card;
  Color get _accent => AppTheme.accent;
  Color get _accentLight => AppTheme.accentSoft;
  Color get _text => AppTheme.text;
  Color get _textSoft => AppTheme.textSoft;
  // Floor-plan figuralari foni (oq matn o'qiladigan to'q rang)
  Color get _panel => _isDark ? const Color(0xFF0F3460) : AppTheme.accent;
  Color get _cardBorder => AppTheme.border;
  Color get _canvasHint =>
      _isDark ? Colors.white24 : Colors.black.withValues(alpha: 0.12);

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadAll();
    // Avto-yangilanish: har 7 soniyada stollar/zakazlar jim yangilanadi (refresh bosmasdan)
    _refreshTimer = Timer.periodic(const Duration(seconds: 7), (_) => _silentRefresh());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // Jim yangilash — spinner ko'rsatmasdan stollar + zakazlarni qayta yuklaydi
  Future<void> _silentRefresh() async {
    if (!mounted) return;
    try {
      final results = await Future.wait([
        ApiService.get(AppConstants.tables),
        ApiService.get(AppConstants.orders),
      ]);
      if (!mounted) return;
      setState(() {
        if (results[0] is List) _tables = results[0];
        if (results[1] is List) _orders = results[1];
      });
    } catch (_) {}
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _printerName = prefs.getString('printer_name');
    });
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        ApiService.get(AppConstants.menuCategories),
        ApiService.get(AppConstants.menuItems),
        ApiService.get(AppConstants.tables),
        ApiService.get(AppConstants.orders),
        ApiService.get(AppConstants.rooms),
      ]);
      setState(() {
        _categories = results[0] is List ? results[0] : [];
        _items      = results[1] is List ? results[1] : [];
        _tables     = results[2] is List ? results[2] : [];
        _orders     = results[3] is List ? results[3] : [];
        _rooms      = results[4] is List ? results[4] : [];
        // Birinchi (taomi bor) kategoriyani tanlab qo'yamiz
        _selectedCatId = _firstCatWithItems();
      });
    } catch (e) {
      debugPrint('Yuklash xatosi: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Faqat pastki menyu "Zakazlar" badge soni uchun (to'lanmaganlar)
  Future<void> _loadOrders() async {
    try {
      final data = await ApiService.get(AppConstants.orders);
      setState(() => _orders = data is List ? data : []);
    } catch (_) {}
  }

  Future<void> _loadTables() async {
    try {
      final results = await Future.wait([
        ApiService.get(AppConstants.tables),
        ApiService.get(AppConstants.rooms),
      ]);
      setState(() {
        _tables = results[0] is List ? results[0] : [];
        _rooms  = results[1] is List ? results[1] : [];
      });
    } catch (_) {}
  }

  // ─── TEMA / PRINTER ──────────────────────────────────────────────────────

  Future<void> _toggleTheme() async {
    await AppTheme.instance.toggle();
  }

  // To'liq xatoni dialogda ko'rsatish (uzun matn uchun)
  Future<void> _showErrorDialog(String title, String message) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text(title, style: TextStyle(color: _text, fontSize: 16)),
        content: SingleChildScrollView(
          child: SelectableText(message, style: TextStyle(color: _textSoft, fontSize: 13)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Yopish'), style: TextStyle(color: _accent)),
          ),
        ],
      ),
    );
  }

  // Mavjud printerlar ro'yxatini ko'rsatib, foydalanuvchi tanlasin
  Future<void> _configurePrinter() async {
    List<Printer> printers;
    try {
      printers = await Printing.listPrinters();
    } catch (e) {
      await _showErrorDialog('Printerlarni olishda xato', '$e');
      return;
    }
    if (!mounted) return;
    if (printers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(tr('Printer topilmadi (tizimda o\'rnatilgan printer yo\'q)')),
            backgroundColor: Colors.orange),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final currentUrl = prefs.getString('printer_url');

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text(tr('Printerni tanlang'), style: TextStyle(color: _text, fontSize: 16)),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: printers.map((p) {
              final selected = p.url == currentUrl;
              return ListTile(
                leading: Icon(
                  selected ? Icons.radio_button_checked : Icons.print,
                  color: _accent,
                ),
                title: Text(p.name,
                    style: TextStyle(
                        color: _text,
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
                subtitle: Text(
                  '${p.url}'
                  '${p.isDefault ? '  •  (tizim standarti)' : ''}'
                  '${p.isAvailable ? '' : '  •  (mavjud emas)'}',
                  style: TextStyle(color: _textSoft, fontSize: 11),
                ),
                onTap: () async {
                  await prefs.setString('printer_url', p.url);
                  await prefs.setString('printer_name', p.name);
                  if (mounted) setState(() => _printerName = p.name);
                  if (ctx.mounted) Navigator.pop(ctx);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('${tr('Printer tanlandi:')} ${p.name}'),
                          backgroundColor: Colors.green),
                    );
                  }
                },
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Bekor'), style: TextStyle(color: _textSoft)),
          ),
        ],
      ),
    );
  }

  // Namuna chek — zakaz bermasdan printerni sinash uchun
  Future<void> _testPrint() async {
    try {
      await printKitchenReceipt(
        tableNumber: 1,
        waiterName: 'Test',
        items: [
          {'name': 'Бодоно шорпо', 'qty': 1, 'price': 0},
          {'name': 'Choy', 'qty': 2, 'price': 0},
        ],
        total: 0,
        note: 'Test chek',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(tr('Test chek printerga yuborildi')),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      await _showErrorDialog('Test chek chiqmadi', '$e');
    }
  }

  // ─── CART ─────────────────────────────────────────────────────────────────

  void _stopMsg(Map item) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('"${item['name']}" — ${tr('hozir tayyor emas (stop-list)')}'),
      backgroundColor: Colors.red,
      duration: const Duration(milliseconds: 1400),
    ));
  }

  void _addToCart(Map<String, dynamic> item) {
    if (item['available'] == false) { _stopMsg(item); return; } // stop-list
    final id = item['id'] as int;
    setState(() {
      if (_cart.containsKey(id)) {
        _cart[id]!['qty'] = (_cart[id]!['qty'] as int) + 1;
      } else {
        _cart[id] = {'item': item, 'qty': 1};
      }
    });
  }

  void _removeFromCart(int id) {
    setState(() {
      if (_cart.containsKey(id)) {
        final qty = (_cart[id]!['qty'] as int) - 1;
        if (qty <= 0) {
          _cart.remove(id);
        } else {
          _cart[id]!['qty'] = qty;
        }
      }
    });
  }

  int get _cartCount => _cart.values.fold(0, (s, v) => s + (v['qty'] as int));

  double get _cartTotal => _cart.values.fold(0.0, (s, v) {
        final price = double.tryParse(v['item']['price'].toString()) ?? 0;
        return s + price * (v['qty'] as int);
      });

  // ─── SUBMIT ORDER ──────────────────────────────────────────────────────────

  Future<void> _showOrderDialog({int? preselectedTableId}) async {
    if (_cart.isEmpty) return;
    final int? tableId = preselectedTableId ?? _selectedTableId;
    if (tableId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Avval stol tanlang')), backgroundColor: Colors.orange),
      );
      return;
    }
    final notesCtrl = TextEditingController();

    // Tanlangan stol raqami (ko'rsatish uchun)
    final tbl = _tables.firstWhere((t) => t['id'] == tableId, orElse: () => null);
    final dynamic tNumRaw = tbl?['number'] ?? _selectedTableNumber ?? tableId;
    final int tableNumber =
        tNumRaw is int ? tNumRaw : int.tryParse(tNumRaw.toString()) ?? tableId;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text(tr('Zakaz tasdiqlash'),
            style: TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.bold)),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Tanlangan stol (faqat ko'rish — dropdown yo'q)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: _accentLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _accent.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.table_restaurant, color: _accent, size: 20),
                      const SizedBox(width: 8),
                      Text('${tr('Stol')} $tableNumber',
                          style: TextStyle(
                              color: _text, fontSize: 15, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Taomlar
                Text(tr('Taomlar:'), style: TextStyle(color: _textSoft, fontSize: 12)),
                const SizedBox(height: 6),
                ..._cart.values.map((v) {
                  final item = v['item'] as Map<String, dynamic>;
                  final qty  = v['qty'] as int;
                  final price = double.tryParse(item['price'].toString()) ?? 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(item['name'].toString(),
                              style: TextStyle(color: _text, fontSize: 13)),
                        ),
                        Text('x$qty',
                            style: TextStyle(color: _textSoft, fontSize: 12)),
                        const SizedBox(width: 8),
                        Text('${(price * qty).toStringAsFixed(0)} сом',
                            style: TextStyle(color: _accent, fontSize: 13)),
                      ],
                    ),
                  );
                }),
                Divider(color: _textSoft.withValues(alpha: 0.4)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(tr('Jami:'),
                        style: TextStyle(color: _text, fontWeight: FontWeight.bold)),
                    Text('${_cartTotal.toStringAsFixed(0)} сом',
                        style: TextStyle(
                            color: _accent, fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
                const SizedBox(height: 12),
                // Izoh
                TextField(
                  controller: notesCtrl,
                  style: TextStyle(color: _text),
                  decoration: InputDecoration(
                    labelText: tr('Izoh (ixtiyoriy)'),
                    labelStyle: TextStyle(color: _textSoft),
                    prefixIcon: Icon(Icons.note, color: _accent),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: _textSoft)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: _accent)),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Bekor'), style: TextStyle(color: _textSoft)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Yuborish'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    if (_sendingOrder) return; // so'rov ketayotganda takror bosish ishlamaydi
    setState(() => _sendingOrder = true);

    final note = notesCtrl.text.trim();

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id') ??
          (Provider.of<AuthProvider>(context, listen: false).user?['id'] as int? ?? 0);

      final cartItems = _cart.values.map((v) {
        final item = v['item'] as Map<String, dynamic>;
        return {
          'menu_item_id': item['id'],
          'quantity': v['qty'],
          'price': double.tryParse(item['price'].toString()) ?? 0,
          'notes': '',
          'is_kitchen': true,
        };
      }).toList();

      // Idempotency-Key — tarmoq uzilib retry bo'lsa ham zakaz ikki marta yaratilmaydi
      await ApiService.post(AppConstants.orders, {
        'table_id': tableId,
        'waiter_id': userId,
        'items': cartItems,
        'notes': note,
      }, idempotencyKey: ApiService.newIdempotencyKey());

      // Savat va tanlangan stolni tozalab, STOLLAR ga qaytamiz
      setState(() {
        _cart.clear();
        _selectedTableId = null;
        _selectedTableNumber = null;
        _selectedIndex = 1; // stollar
      });
      await Future.wait([_loadOrders(), _loadTables()]);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('Zakaz yuborildi!')),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Chek chop etish endi LOKAL PRINT-AGENT orqali:
      // zakaz bo'limlarga (oshxona/shashlik/somsa/bar) bo'linib, har biri
      // o'z printeriga chiqadi. Ofitsant qurilmasidan chop etilmaydi
      // (ikki marta chiqmasligi uchun).
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Xato: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingOrder = false);
    }
  }

  // ─── TABS ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([AppTheme.instance, Lang.instance]),
      builder: (context, _) => _scaffold(context),
    );
  }

  Widget _scaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _accent))
          : IndexedStack(
              index: _selectedIndex,
              children: [
                _buildMenuTab(),
                _buildTablesTab(),
                OrdersView(
                  key: ValueKey(_ordersKey),
                  canComplete: _canComplete,
                  title: 'Zakazlar',
                ),
                _buildProfileTab(),
                if (_canComplete) CashboxView(key: ValueKey(_kassaKey)),
              ],
            ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: _card,
        selectedItemColor: _accent,
        unselectedItemColor: _textSoft,
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        elevation: 12,
        onTap: (i) {
          setState(() {
            _selectedIndex = i;
            if (i == 2) _ordersKey++; // Zakazlar tabini yangilash (yangi ma'lumot yuklanadi)
            if (i == 4) _kassaKey++;  // Kassa tabini ochganda yangi ma'lumot yuklanadi
          });
          if (i == 2) _loadOrders(); // badge sonini yangilash
          if (i == 1) _loadTables();
        },
        items: [
          BottomNavigationBarItem(
              icon: const Icon(Icons.restaurant_menu), label: tr('Menyu')),
          BottomNavigationBarItem(
              icon: const Icon(Icons.table_restaurant), label: tr('Stollar')),
          BottomNavigationBarItem(
            icon: _orders.isNotEmpty
                ? Badge(
                    label: Text('${_orders.length}'),
                    child: const Icon(Icons.receipt_long),
                  )
                : const Icon(Icons.receipt_long),
            label: tr('Zakazlar'),
          ),
          BottomNavigationBarItem(
              icon: const Icon(Icons.person), label: tr('Profil')),
          if (_canComplete)
            BottomNavigationBarItem(
                icon: const Icon(Icons.point_of_sale), label: tr('Kassa')),
        ],
      ),
    );
  }

  // Umumiy tab header (oq/qorong'u kartochka, yumshoq soya)
  Widget _header(String title, {List<Widget> actions = const [], Widget? leading}) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDark ? 0.3 : 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(8, 48, 12, 12),
      child: Row(
        children: [
          if (leading != null) leading else const SizedBox(width: 8),
          Expanded(
            child: Text(title,
                style: TextStyle(
                    color: _text, fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          ...actions,
        ],
      ),
    );
  }

  // ─── 1. MENYU TAB ─────────────────────────────────────────────────────────

  // Taomi bor birinchi kategoriya id'sini qaytaradi (yo'q bo'lsa null)
  int? _firstCatWithItems() {
    for (final cat in _categories) {
      final catId = cat['id'] as int;
      if (_items.any((i) => i['category_id'] == catId)) return catId;
    }
    return null;
  }

  // Stol tanlanmagan holatdagi menyu ko'rinishi
  Widget _menuNoTablePlaceholder() {
    return Container(
      color: _bg,
      child: Column(
        children: [
          _header(tr('Menyu')),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.touch_app, color: _accent, size: 56),
                  const SizedBox(height: 12),
                  Text(tr('Avval stol tanlang'),
                      style: TextStyle(
                          color: _text, fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(tr('Zakaz berish uchun stollardan birini tanlang'),
                      style: TextStyle(color: _textSoft, fontSize: 13)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.table_restaurant, color: Colors.white),
                    label: Text(tr('Stollarga o\'tish'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onPressed: () => setState(() => _selectedIndex = 1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuTab() {
    // Stol tanlanmagan bo'lsa menyuga kirib bo'lmaydi
    if (_selectedTableId == null) {
      return _menuNoTablePlaceholder();
    }
    // Faqat taomi bor kategoriyalar
    final visibleCats = _categories.where((cat) {
      final catId = cat['id'] as int;
      return _items.any((i) => i['category_id'] == catId);
    }).toList();

    // Tanlangan kategoriya hali yo'q bo'lsa, birinchisini olamiz
    final selectedId = _selectedCatId ??
        (visibleCats.isNotEmpty ? visibleCats.first['id'] as int : null);

    final selectedItems = selectedId == null
        ? <dynamic>[]
        : _items.where((i) => i['category_id'] == selectedId).toList();

    return Column(
      children: [
        // Header
        _header(
          '${tr('Menyu')} — ${tr('Stol')} $_selectedTableNumber',
          actions: [
            if (_cart.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _accentLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                    '$_cartCount ta  •  ${_cartTotal.toStringAsFixed(0)} сом',
                    style: TextStyle(
                        color: _accent, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
        // Master-detail
        Expanded(
          child: visibleCats.isEmpty
              ? Center(
                  child: Text(tr('Menyu bo\'sh'), style: TextStyle(color: _textSoft)))
              : Container(
                  color: _bg,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // CHAP USTUN — kategoriyalar
                      SizedBox(
                        width: 150,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(10, 12, 6, 12),
                          itemCount: visibleCats.length,
                          itemBuilder: (_, idx) {
                            final cat = visibleCats[idx];
                            final catId = cat['id'] as int;
                            final count = _items
                                .where((i) => i['category_id'] == catId)
                                .length;
                            final selected = catId == selectedId;
                            return GestureDetector(
                              onTap: () =>
                                  setState(() => _selectedCatId = catId),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  color: selected ? _accent : _accentLight,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: selected
                                      ? [
                                          BoxShadow(
                                            color: _accent.withValues(alpha: 0.35),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          )
                                        ]
                                      : null,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      cat['name'].toString(),
                                      style: TextStyle(
                                        color: selected ? Colors.white : _text,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '($count ta)',
                                      style: TextStyle(
                                        color: selected
                                            ? Colors.white.withValues(alpha: 0.85)
                                            : _textSoft,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      // O'NG TARAF — taomlar grid
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            int cross = (constraints.maxWidth / 200).floor();
                            cross = cross.clamp(2, 6);
                            return GridView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(6, 12, 10, 12),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cross,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: 0.82,
                              ),
                              itemCount: selectedItems.length,
                              itemBuilder: (_, i) =>
                                  _buildItemCard(selectedItems[i]),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
        ),
        // Cart bar
        if (_cart.isNotEmpty) _buildCartBar(),
      ],
    );
  }

  Widget _buildItemCard(Map<String, dynamic> item) {
    final id = item['id'] as int;
    final inCart = _cart.containsKey(id) ? (_cart[id]!['qty'] as int) : 0;
    final price = double.tryParse(item['price'].toString()) ?? 0;
    final available = item['available'] != false;

    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: !available ? Colors.red.withValues(alpha: 0.4) : (inCart > 0 ? _accent : _cardBorder),
            width: inCart > 0 ? 1.6 : 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDark ? 0.25 : 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          Expanded(
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(13)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  item['image_url'] != null
                      ? Image.network(
                          '${AppConstants.imageBase}${item['image_url']}',
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) => _itemPlaceholder(),
                        )
                      : _itemPlaceholder(),
                  if (!available)
                    Container(
                      color: Colors.black.withValues(alpha: 0.4),
                      alignment: Alignment.center,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
                        child: Text(tr('СТОП'),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Info
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'].toString(),
                  style: TextStyle(
                      color: _text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${price.toStringAsFixed(0)} сом',
                  style: TextStyle(
                      color: _accent, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                // + / qty / -
                Row(
                  children: [
                    if (inCart > 0) ...[
                      _circleBtn(Icons.remove, () => _removeFromCart(id)),
                      Expanded(
                        child: Center(
                          child: Text('$inCart',
                              style: TextStyle(
                                  color: _text, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ] else
                      const Spacer(),
                    _circleBtn(Icons.add, () => _addToCart(item)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(color: _accent, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 17),
      ),
    );
  }

  Widget _itemPlaceholder() {
    return Container(
      color: _accentLight,
      child: Center(child: Icon(Icons.restaurant, color: _accent, size: 34)),
    );
  }

  Widget _buildCartBar() {
    return GestureDetector(
      onTap: () => _showOrderDialog(preselectedTableId: _selectedTableId),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _accent,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
                color: _accent.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8)),
              child: Text('$_cartCount',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ),
            const SizedBox(width: 10),
            Text(tr('Zakaz berish'),
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
            const Spacer(),
            Text('${_cartTotal.toStringAsFixed(0)} сом',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14)),
            const SizedBox(width: 6),
            const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 14),
          ],
        ),
      ),
    );
  }

  // ─── 2. STOLLAR TAB ───────────────────────────────────────────────────────

  // Admin saqlagan AYNAN o'sha joylashuv (nisbiy koordinata) — faqat ko'rish/tanlash.
  Widget _buildTablesTab() {
    final inRoom = _selectedRoomId != null;
    final room = inRoom
        ? _rooms.firstWhere((r) => r['id'] == _selectedRoomId, orElse: () => null)
        : null;
    // Xona o'chirilgan bo'lsa binoga qaytamiz
    if (inRoom && room == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedRoomId = null);
      });
    }

    return Column(
      children: [
        _header(
          (inRoom && room != null) ? room['name'].toString() : tr('Stollar'),
          leading: (inRoom && room != null)
              ? IconButton(
                  icon: Icon(Icons.arrow_back, color: _text),
                  onPressed: () => setState(() => _selectedRoomId = null),
                )
              : null,
          actions: [
            if (inRoom) ...[
              _legendDot(Colors.green, tr('Bo\'sh')),
              const SizedBox(width: 12),
              _legendDot(Colors.red, tr('Band')),
              const SizedBox(width: 12),
            ],
            IconButton(
              icon: Icon(Icons.refresh, color: _textSoft),
              onPressed: _loadTables,
            ),
          ],
        ),
        Expanded(
          child: (inRoom && room != null)
              ? _waiterRoomView(room)
              : _waiterBuildingView(),
        ),
      ],
    );
  }

  double _rel(dynamic v, double def) => double.tryParse(v?.toString() ?? '') ?? def;

  // KO'RINISH 1 — Bino (xonalar)
  Widget _waiterBuildingView() {
    if (_rooms.isEmpty) {
      return Center(
        child: Text(tr('Xonalar topilmadi'), style: TextStyle(color: _textSoft)),
      );
    }
    return InteractiveViewer(
      minScale: 0.6,
      maxScale: 4.0,
      boundaryMargin: const EdgeInsets.all(120),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: AspectRatio(
            aspectRatio: 16 / 10,
            child: LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth, h = c.maxHeight;
                return Container(
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _accent.withValues(alpha: 0.25), width: 2),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Text(tr('Sultan Restoran'),
                            style: TextStyle(
                                color: _canvasHint,
                                fontSize: 24,
                                fontWeight: FontWeight.bold)),
                      ),
                      ..._rooms.map((room) => _waiterRoomFigure(room, w, h)),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _waiterRoomFigure(Map<String, dynamic> room, double W, double H) {
    final rw = _rel(room['width'], 0.3).clamp(0.1, 1.0);
    final rh = _rel(room['height'], 0.3).clamp(0.1, 1.0);
    final px = _rel(room['pos_x'], 0.1).clamp(0.0, (1 - rw).clamp(0.0, 1.0));
    final py = _rel(room['pos_y'], 0.1).clamp(0.0, (1 - rh).clamp(0.0, 1.0));
    final roomTables = _tables.where((t) => t['room_id'] == room['id']).toList();
    final free = roomTables.where((t) => (t['status'] ?? 'free') == 'free').length;

    return Positioned(
      left: px * W,
      top: py * H,
      child: GestureDetector(
        onTap: () => setState(() => _selectedRoomId = room['id'] as int),
        child: Container(
          width: rw * W,
          height: rh * H,
          decoration: BoxDecoration(
            color: _panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _accent.withValues(alpha: 0.7), width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.meeting_room, color: Colors.white, size: 22),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(room['name'].toString(),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 2),
              Text("$free/${roomTables.length} ${tr('bo\'sh')}",
                  style: const TextStyle(color: Colors.white70, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }

  // KO'RINISH 2 — Xona ichi (stollar admin joylashuvida)
  Widget _waiterRoomView(Map<String, dynamic> room) {
    final tables = _tables.where((t) => t['room_id'] == _selectedRoomId).toList();
    // Xona canvas'i admin saqlagan nisbat bo'yicha (admin bilan bir xil)
    final roomAspect =
        ((_rel(room['width'], 0.3) * 16) / (_rel(room['height'], 0.3) * 10)).clamp(0.5, 4.0);
    return InteractiveViewer(
      minScale: 0.6,
      maxScale: 4.0,
      boundaryMargin: const EdgeInsets.all(120),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: AspectRatio(
            aspectRatio: roomAspect.toDouble(),
            child: LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth, h = c.maxHeight;
                return Container(
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _accent.withValues(alpha: 0.25), width: 2),
                  ),
                  child: Stack(
                    children: [
                      if (tables.isEmpty)
                        Center(
                          child: Text(tr('Bu xonada stol yo\'q'),
                              style: TextStyle(color: _canvasHint, fontSize: 18)),
                        ),
                      ...tables.map((t) => _waiterTableFigure(t, w, h)),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _waiterTableFigure(Map<String, dynamic> table, double W, double H) {
    final isFree = (table['status'] ?? 'free') == 'free';
    final color = isFree ? Colors.green : Colors.red;
    final tSize = _rel(table['table_size'], 1.0).clamp(0.6, 2.0);
    final total = TableWithChairs.totalSize(TableWithChairs.defaultBase, tSize.toDouble());
    final seats = int.tryParse(table['seats']?.toString() ?? '') ?? 4;
    final px = _rel(table['pos_x'], 0.5).clamp(0.0, 1.0);
    final py = _rel(table['pos_y'], 0.5).clamp(0.0, 1.0);

    return Positioned(
      left: px * W - total / 2,
      top: py * H - total / 2,
      child: GestureDetector(
        onTap: () => _onTableTap(table),
        child: TableWithChairs(
          number: '${table['number'] ?? table['id']}',
          seats: seats,
          tableSize: tSize.toDouble(),
          color: color, // free=yashil, occupied=qizil (stol + stullar)
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: _textSoft, fontSize: 12)),
      ],
    );
  }

  // Stol tanlanganda — stolni eslab qolib MENYU ga o'tamiz
  void _onTableTap(Map<String, dynamic> table) {
    final num = table['number'] ?? table['id'];
    setState(() {
      _selectedTableId = table['id'] as int;
      _selectedTableNumber = num is int ? num : int.tryParse(num.toString());
      _selectedIndex = 0; // menyu
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${tr('Stol')} $num ${tr('tanlandi. Taom qo\'shing.')}'),
        backgroundColor: _card == Colors.white ? _accent : _card,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ─── 3. ZAKAZLAR TAB ──────────────────────────────────────────────────────
  // Zakazlar ko'rinishi umumiy `OrdersView` widgetida (widgets/orders_view.dart) —
  // admin va ofitsant oynalari shu bitta widgetdan foydalanadi.

  // ─── 4. PROFIL TAB ────────────────────────────────────────────────────────

  Widget _buildProfileTab() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final user = auth.user;
    final roleLabels = {
      'admin':    'Administrator',
      'waiter':   'Ofitsant',
      'chef':     'Oshpaz',
      'cashier':  'Kassir',
      'cleaner':  'Tozalovchi',
    };

    return SingleChildScrollView(
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: _card,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: _isDark ? 0.3 : 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(16, 52, 16, 24),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 38,
                  backgroundColor: _accent.withValues(alpha: 0.2),
                  child: Icon(Icons.person, color: _accent, size: 42),
                ),
                const SizedBox(height: 12),
                Text(
                  user?['full_name']?.toString() ?? tr('Foydalanuvchi'),
                  style: TextStyle(
                      color: _text, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    tr(roleLabels[user?['role']] ?? user?['role']?.toString() ?? ''),
                    style: TextStyle(color: _accent, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Sozlamalar
          _profileSection(tr('Sozlamalar'), [
            // Til almashtirish UZ / RU
            ListTile(
              leading: Icon(Icons.language, color: _accent, size: 22),
              title: Text(tr('Til'),
                  style: TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: Text(Lang.instance.isRu ? 'Русский' : 'O\'zbekcha',
                  style: TextStyle(color: _textSoft, fontSize: 12)),
              trailing: Text(Lang.instance.isRu ? 'УЗ' : 'RU',
                  style: TextStyle(color: _accent, fontWeight: FontWeight.bold, fontSize: 15)),
              onTap: () => Lang.instance.toggle(),
            ),
            // Tema almashtirish
            ListTile(
              leading: Icon(_isDark ? Icons.dark_mode : Icons.light_mode, color: _accent, size: 22),
              title: Text(tr('Tema'),
                  style: TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: Text(_isDark ? tr('Qorong\'u') : tr('Yorug\''),
                  style: TextStyle(color: _textSoft, fontSize: 12)),
              trailing: Switch(
                value: _isDark,
                activeThumbColor: _accent,
                onChanged: (_) => _toggleTheme(),
              ),
            ),
            // Printerni sozlash
            ListTile(
              leading: Icon(Icons.print, color: _accent, size: 22),
              title: Text(tr('Printerni sozlash'),
                  style: TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: Text(
                  _printerName != null
                      ? '${tr('Printer')}: $_printerName'
                      : tr('Tanlanmagan — bosing va tanlang'),
                  style: TextStyle(color: _textSoft, fontSize: 12)),
              trailing: Icon(Icons.chevron_right, color: _textSoft),
              onTap: _configurePrinter,
            ),
            // Test chek
            ListTile(
              leading: Icon(Icons.receipt_long, color: _accent, size: 22),
              title: Text(tr('Test chek chiqarish'),
                  style: TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: Text(tr('Printerni sinash uchun namuna chek'),
                  style: TextStyle(color: _textSoft, fontSize: 12)),
              trailing: Icon(Icons.chevron_right, color: _textSoft),
              onTap: _testPrint,
            ),
          ]),
          const SizedBox(height: 12),
          // Info section
          _profileSection(tr('Ilova haqida'), [
            _profileTile(Icons.info_outline, tr('Versiya'), 'Sultan Restoran v1.1.0'),
            _profileTile(Icons.code, tr('Ishlab chiqaruvchi'), 'Sultan Dev Team'),
          ]),
          const SizedBox(height: 12),
          // Logout
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.withValues(alpha: 0.15),
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red, width: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.logout),
                label: Text(tr('Chiqish'),
                    style:
                        const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                onPressed: () async {
                  await auth.logout();
                  if (mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(
                          builder: (_) => const LoginScreen()),
                      (_) => false,
                    );
                  }
                },
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _profileSection(String title, List<Widget> tiles) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(title,
                style: TextStyle(
                    color: _textSoft,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
          ),
          ...tiles,
        ],
      ),
    );
  }

  Widget _profileTile(IconData icon, String label, String value) {
    return ListTile(
      leading: Icon(icon, color: _accent, size: 20),
      title: Text(label, style: TextStyle(color: _textSoft, fontSize: 13)),
      trailing: Text(value, style: TextStyle(color: _text, fontSize: 13)),
    );
  }
}

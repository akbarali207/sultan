import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../providers/auth_provider.dart';
import '../../core/api_service.dart';
import '../../core/constants.dart';
import '../../core/app_theme.dart';
import '../../core/lang.dart';
import 'analytics_page.dart';
import '../../widgets/table_with_chairs.dart';
import '../../widgets/orders_view.dart';
import '../../widgets/cashbox_view.dart';
import '../../widgets/recipe_section.dart';
import '../login_screen.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  int _selectedIndex = 0;
  bool _frozen = false; // super-admin STOP holati (banner + tugma uchun)

  @override
  void initState() {
    super.initState();
    _loadSystemState();
  }

  Future<void> _loadSystemState() async {
    try {
      final r = await ApiService.get('/system/state');
      if (mounted && r is Map) setState(() => _frozen = r['frozen'] == true);
    } catch (_) {}
  }

  // Super-admin STOP / ochish
  Future<void> _toggleFreeze(bool freeze) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(freeze ? tr('Tizimni TO\'XTATISH?') : tr('Tizimni ochish?'), style: TextStyle(color: AppTheme.text)),
        content: Text(
            freeze
                ? tr('Barcha yangi zakaz va to\'lov bloklanadi. Faqat super-admin qayta ocha oladi.')
                : tr('Tizim yana ishlaydi — zakaz va to\'lov qabul qilinadi.'),
            style: TextStyle(color: AppTheme.textSoft)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: freeze ? Colors.red : Colors.green),
            onPressed: () => Navigator.pop(context, true),
            child: Text(freeze ? tr('TO\'XTATISH') : tr('Ochish'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await ApiService.post('/system/freeze', {'frozen': freeze});
      if (!mounted) return;
      if (r is Map && r['ok'] == true) {
        setState(() => _frozen = r['frozen'] == true);
      } else if (r is Map && r['message'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(r['message'].toString()), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
      }
    }
  }

  final List<Map<String, dynamic>> _menuItems = [
    {'icon': Icons.dashboard, 'label': 'Bosh sahifa'},
    {'icon': Icons.people, 'label': 'Xodimlar'},
    {'icon': Icons.restaurant_menu, 'label': 'Menyu'},
    {'icon': Icons.receipt_long, 'label': 'Zakazlar'},
    {'icon': Icons.account_balance_wallet, 'label': 'Harajatlar'},
    {'icon': Icons.bar_chart, 'label': 'Hisobot'},
    {'icon': Icons.payments, 'label': 'Ish haqi'},
    {'icon': Icons.point_of_sale, 'label': 'Kassa'},
    {'icon': Icons.assignment, 'label': 'Inventarizatsiya'},
    {'icon': Icons.grid_view, 'label': 'Stollar'},
    {'icon': Icons.menu_book, 'label': 'Retseptlar'},
  ];

  @override
  Widget build(BuildContext context) {
    // Tema yoki til o'zgarganda ekran qayta quriladi
    return AnimatedBuilder(
      animation: Listenable.merge([AppTheme.instance, Lang.instance]),
      builder: (context, _) => _scaffold(context),
    );
  }

  Widget _scaffold(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.card,
        title: Text(tr(_menuItems[_selectedIndex]['label']), style: TextStyle(color: AppTheme.text)),
        actions: [
          // Kengaytirilgan analitika — FAQAT direktor (+ guest super-admin) ko'radi
          if (auth.role == 'director' || auth.role == 'guest')
            IconButton(
              tooltip: tr('Analitika'),
              icon: Icon(Icons.insights, color: AppTheme.accent),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnalyticsPage())),
            ),
          // Super-admin (guest) — STOP / ochish tugmasi
          if (auth.role == 'guest')
            IconButton(
              tooltip: _frozen ? tr('Ochish') : tr('STOP'),
              icon: Icon(_frozen ? Icons.play_circle_fill : Icons.stop_circle,
                  color: _frozen ? Colors.green : Colors.red, size: 28),
              onPressed: () => _toggleFreeze(!_frozen),
            ),
          // Til almashtirgich UZ / RU
          TextButton(
            onPressed: () => Lang.instance.toggle(),
            child: Text(
              Lang.instance.isRu ? 'УЗ' : 'RU',
              style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          IconButton(
            icon: Icon(AppTheme.dark ? Icons.light_mode : Icons.dark_mode, color: AppTheme.accent),
            tooltip: tr('Yorug\' / Qorong\'i'),
            onPressed: () => AppTheme.instance.toggle(),
          ),
          IconButton(
            icon: Icon(Icons.logout, color: AppTheme.text),
            onPressed: () async {
              await auth.logout();
              if (context.mounted) {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
              }
            },
          ),
        ],
      ),
      body: Column(children: [
        if (_frozen)
          Container(
            width: double.infinity,
            color: Colors.red,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: Text(tr('⛔ TIZIM TO\'XTATILGAN — yangi zakaz va to\'lov bloklangan'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        Expanded(child: _buildBody()),
      ]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        backgroundColor: AppTheme.card,
        selectedItemColor: AppTheme.accent,
        unselectedItemColor: AppTheme.textSoft,
        type: BottomNavigationBarType.fixed,
        items: _menuItems.map((item) => BottomNavigationBarItem(icon: Icon(item['icon']), label: tr(item['label']))).toList(),
      ),
    );
  }

  Widget _buildBody() {
    // Const EMAS — tema o'zgarganda bo'lim qayta quriladi (holat saqlanadi)
    switch (_selectedIndex) {
      case 0: return DashboardSection();
      case 1: return StaffSection();
      case 2: return MenuSection();
      case 3: return _buildOrders();
      case 4: return _buildExpenses();
      case 5: return _buildReport();
      case 6: return PayrollSection();
      case 7: return const CashboxView();
      case 8: return InventorySection();
      case 9: return FloorPlanSection();
      case 10: return const RecipeSection();
      default: return DashboardSection();
    }
  }

  // Admin zakazni tugata oladi
  Widget _buildOrders() => const OrdersView(canComplete: true);
  Widget _buildExpenses() => ExpensesSection();
  Widget _buildReport() => ReportSection();
}

// ===== BOSH SAHIFA (DASHBOARD) =====
class DashboardSection extends StatefulWidget {
  const DashboardSection({super.key});

  @override
  State<DashboardSection> createState() => _DashboardSectionState();
}

class _DashboardSectionState extends State<DashboardSection> {
  String _period = 'today';
  DateTime? _selectedDate; // aniq kun tanlangan bo'lsa
  Map<String, dynamic>? _data;
  bool _loading = true;
  // Kunlik kuzat (somsa kabi): bugungi tayyorlangan/sotilgan/qolgan
  List<dynamic> _daily = [];
  final Map<int, TextEditingController> _dailyCtrls = {};

  @override
  void dispose() {
    for (final c in _dailyCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  static Color get _accent => AppTheme.accent;
  static Color get _card => AppTheme.card;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final q = _selectedDate != null
          ? '?date=${_ymd(_selectedDate!)}'
          : '?period=$_period';
      final d = await ApiService.get('${AppConstants.dashboardReport}$q');
      setState(() {
        _data = d is Map<String, dynamic> ? d : null;
        _loading = false;
      });
      _loadDaily();
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  // Kunlik kuzat taomlari — faqat "Bugun" ko'rinishida
  Future<void> _loadDaily() async {
    if (_period != 'today' || _selectedDate != null) {
      if (_daily.isNotEmpty && mounted) setState(() => _daily = []);
      return;
    }
    try {
      final d = await ApiService.get('/reports/daily-stock');
      if (d is List && mounted) {
        for (final it in d) {
          final id = it['menu_item_id'] as int;
          final ctrl = _dailyCtrls.putIfAbsent(id, () => TextEditingController());
          ctrl.text = (double.tryParse(it['opening'].toString()) ?? 0).toStringAsFixed(0);
        }
        setState(() => _daily = d);
      }
    } catch (_) {}
  }

  Future<void> _setDaily(int id, String v) async {
    final qty = double.tryParse(v.trim().replaceAll(',', '.')) ?? 0;
    try {
      await ApiService.post('/reports/daily-stock', {'menu_item_id': id, 'quantity': qty});
      await _loadDaily();
    } catch (_) {}
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _setPeriod(String p) {
    if (_period == p && _selectedDate == null) return;
    setState(() {
      _period = p;
      _selectedDate = null; // davr tanlansa, aniq kun bekor qilinadi
    });
    _load();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2023),
      lastDate: DateTime.now(),
      builder: (c, w) => Theme(
        data: (AppTheme.dark ? ThemeData.dark() : ThemeData.light())
            .copyWith(colorScheme: (AppTheme.dark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(primary: AppTheme.accent)),
        child: w!,
      ),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _load();
    }
  }

  String _money(num v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return b.toString();
  }

  String _short(num v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}k';
    return v.round().toString();
  }

  num _num(dynamic v) => v is num ? v : (num.tryParse(v?.toString() ?? '0') ?? 0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: _loading
          ? Center(child: CircularProgressIndicator(color: _accent))
          : _data == null
              ? Center(child: Text(tr('Ma\'lumot yo\'q'), style: TextStyle(color: AppTheme.textSoft)))
              : RefreshIndicator(
                  color: _accent,
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _periodFilter(),
                        const SizedBox(height: 16),
                        _kpiGrid(),
                        const SizedBox(height: 12),
                        _opRow(),
                        if (_daily.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _dailyCard(),
                        ],
                        const SizedBox(height: 16),
                        _chartCard(tr('Oxirgi 7 kun savdosi (сом)'), _sevenDayChart()),
                        const SizedBox(height: 12),
                        _chartCard(tr('Eng gavjum soatlar (сом)'), _hourChart()),
                        const SizedBox(height: 12),
                        _chartCard(tr('Bo\'lim bo\'yicha savdo (сом)'), _stationBars()),
                        const SizedBox(height: 12),
                        _twoLists(),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _periodFilter() {
    Widget pill(String label, String p) {
      final sel = _period == p;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => _setPeriod(p),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? _accent : _card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: sel ? _accent : AppTheme.textSoft.withValues(alpha: 0.4)),
            ),
            child: Text(label,
                style: TextStyle(
                    color: sel ? AppTheme.text : AppTheme.textSoft,
                    fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13)),
          ),
        ),
      );
    }

    final dSel = _selectedDate != null;
    final datePill = Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: _pickDay,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: dSel ? _accent : _card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: dSel ? _accent : AppTheme.textSoft.withValues(alpha: 0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.calendar_today, size: 14, color: dSel ? AppTheme.text : AppTheme.textSoft),
            const SizedBox(width: 6),
            Text(
              dSel
                  ? '${_selectedDate!.day.toString().padLeft(2, '0')}.${_selectedDate!.month.toString().padLeft(2, '0')}.${_selectedDate!.year}'
                  : tr('Kun tanlash'),
              style: TextStyle(
                  color: dSel ? AppTheme.text : AppTheme.textSoft,
                  fontWeight: dSel ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13),
            ),
          ]),
        ),
      ),
    );
    return Wrap(
      runSpacing: 8,
      children: [pill(tr('Bugun'), 'today'), pill(tr('Hafta'), 'week'), pill(tr('Oy'), 'month'), datePill],
    );
  }

  Widget _kpiGrid() {
    final width = MediaQuery.of(context).size.width;
    final cols = width > 900 ? 4 : 2;
    final cards = [
      _kpiCard(tr('Savdo'), '${_money(_num(_data!['sales']))} сом', Icons.payments, Colors.green),
      _kpiCard(tr('Zakazlar'), '${_data!['orders'] ?? 0}', Icons.receipt_long, Colors.blue),
      _kpiCard(tr('Sof foyda'), '${_money(_num(_data!['profit']))} сом', Icons.trending_up, _accent),
      _kpiCard(tr('O\'rtacha chek'), '${_money(_num(_data!['avg_check']))} сом', Icons.calculate, Colors.purpleAccent),
    ];
    return GridView.count(
      crossAxisCount: cols,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 2.2,
      children: cards,
    );
  }

  // KUNLIK KUZAT karta — ertalab son kiritish + sotildi/qoldi
  Widget _dailyCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.event_available, color: Colors.purple, size: 20),
            const SizedBox(width: 8),
            Text(tr('Kunlik taomlar'),
                style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 15)),
          ]),
          const SizedBox(height: 2),
          Text(tr('Ertalab "tayyorlandi" soniga kiriting — tugasa sotuv to\'xtaydi'),
              style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
          const SizedBox(height: 10),
          // Sarlavha qatori
          Row(children: [
            Expanded(flex: 4, child: Text(tr('Taom'), style: TextStyle(color: AppTheme.textSoft, fontSize: 11, fontWeight: FontWeight.bold))),
            SizedBox(width: 68, child: Text(tr('Tayyor'), textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSoft, fontSize: 11, fontWeight: FontWeight.bold))),
            SizedBox(width: 52, child: Text(tr('Sotildi'), textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSoft, fontSize: 11, fontWeight: FontWeight.bold))),
            SizedBox(width: 52, child: Text(tr('Qoldi'), textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSoft, fontSize: 11, fontWeight: FontWeight.bold))),
          ]),
          const Divider(height: 12),
          ..._daily.map((it) {
            final id = it['menu_item_id'] as int;
            final opening = double.tryParse(it['opening'].toString()) ?? 0;
            final sold = double.tryParse(it['sold'].toString()) ?? 0;
            final remaining = double.tryParse(it['remaining'].toString()) ?? 0;
            final hasOpening = it['has_opening'] == true;
            final ctrl = _dailyCtrls[id] ?? TextEditingController(text: opening.toStringAsFixed(0));
            final done = hasOpening && remaining <= 0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                Expanded(flex: 4, child: Text(it['name']?.toString() ?? '',
                    style: TextStyle(color: AppTheme.text, fontSize: 13))),
                SizedBox(
                  width: 68,
                  child: SizedBox(
                    height: 34,
                    child: TextField(
                      controller: ctrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.text, fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 6),
                        hintText: '—',
                        hintStyle: TextStyle(color: AppTheme.textSoft),
                        filled: true,
                        fillColor: AppTheme.bg,
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: BorderSide(color: AppTheme.border)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: const BorderSide(color: Colors.purple)),
                      ),
                      onSubmitted: (v) => _setDaily(id, v),
                    ),
                  ),
                ),
                SizedBox(width: 52, child: Text(sold.toStringAsFixed(0), textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.text, fontSize: 13, fontWeight: FontWeight.w600))),
                SizedBox(width: 52, child: Text(
                    !hasOpening ? '∞' : remaining.toStringAsFixed(0),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: !hasOpening ? AppTheme.textSoft : (done ? Colors.red : Colors.green),
                        fontSize: 13, fontWeight: FontWeight.bold))),
              ]),
            );
          }),
        ],
      ),
    );
  }

  Widget _kpiCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
          ]),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _opRow() {
    final tables = _data!['tables'] as Map? ?? {};
    final staff = _data!['staff'] as Map? ?? {};
    final low = _data!['low_stock'] ?? 0;
    return Row(
      children: [
        Expanded(child: _opCard(Icons.table_restaurant, Colors.blueAccent,
            '${tables['occupied'] ?? 0} / ${tables['total'] ?? 0}', tr('Band stollar'))),
        const SizedBox(width: 12),
        Expanded(child: _opCard(Icons.people, Colors.green,
            '${staff['present'] ?? 0} / ${staff['total'] ?? 0}', tr('Ishda xodim'))),
        const SizedBox(width: 12),
        Expanded(child: _opCard(Icons.warning_amber, Colors.orange, '$low', tr('Kam qolgan sklad'))),
      ],
    );
  }

  Widget _opCard(IconData icon, Color color, String value, String label) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.textSoft.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(color: AppTheme.text, fontSize: 16, fontWeight: FontWeight.bold)),
                Text(label, style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chartCard(String title, Widget child) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.textSoft.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: AppTheme.textSoft, fontSize: 13)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  // Vertikal ustun grafigi
  Widget _vBars(List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return SizedBox(height: 60, child: Center(child: Text(tr('Ma\'lumot yo\'q'), style: TextStyle(color: AppTheme.textSoft))));
    }
    double maxV = 1;
    for (final e in items) {
      final v = (e['value'] as num).toDouble();
      if (v > maxV) maxV = v;
    }
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: items.map((e) {
          final v = (e['value'] as num).toDouble();
          final frac = maxV > 0 ? v / maxV : 0.0;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(v > 0 ? _short(v) : '', style: TextStyle(color: AppTheme.textSoft, fontSize: 9)),
                  const SizedBox(height: 2),
                  Container(
                    height: 4 + frac * 95,
                    decoration: BoxDecoration(
                      color: _accent,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(e['label'].toString(), style: TextStyle(color: AppTheme.textSoft, fontSize: 10)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _sevenDayChart() {
    final raw = (_data!['sales_by_day'] as List?) ?? [];
    final byDate = {for (final e in raw) e['d'].toString(): _num(e['sales'])};
    const wk = ['Du', 'Se', 'Ch', 'Pa', 'Ju', 'Sh', 'Ya'];
    final now = _selectedDate ?? DateTime.now();
    final items = <Map<String, dynamic>>[];
    for (int i = 6; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      final key = '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      items.add({
        'label': tr(wk[day.weekday - 1]),
        'date': '${day.day.toString().padLeft(2, '0')}.${day.month.toString().padLeft(2, '0')}',
        'value': byDate[key] ?? 0,
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _vBars(items),
        const SizedBox(height: 14),
        ..._sevenDayRows(items),
      ],
    );
  }

  // Har kun bo'yicha aniq savdo (sana + summa + bar)
  List<Widget> _sevenDayRows(List<Map<String, dynamic>> items) {
    double maxV = 1;
    for (final e in items) {
      final v = (e['value'] as num).toDouble();
      if (v > maxV) maxV = v;
    }
    return items.map<Widget>((e) {
      final v = (e['value'] as num).toDouble();
      final frac = maxV > 0 ? v / maxV : 0.0;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            SizedBox(
              width: 78,
              child: Text('${e['label']}  ${e['date']}',
                  style: TextStyle(color: AppTheme.text, fontSize: 12)),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: frac,
                  minHeight: 8,
                  backgroundColor: AppTheme.text.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation(_accent),
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 96,
              child: Text('${_money(v)} сом',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                      color: v > 0 ? AppTheme.text : AppTheme.textSoft,
                      fontSize: 12,
                      fontWeight: v > 0 ? FontWeight.w600 : FontWeight.normal)),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _hourChart() {
    final raw = (_data!['sales_by_hour'] as List?) ?? [];
    if (raw.isEmpty) {
      return SizedBox(height: 60, child: Center(child: Text(tr('Ma\'lumot yo\'q'), style: TextStyle(color: AppTheme.textSoft))));
    }
    final items = raw.map<Map<String, dynamic>>((e) => {
          'label': '${e['h']}:00',
          'value': _num(e['sales']),
        }).toList();
    return _vBars(items);
  }

  Widget _stationBars() {
    final raw = (_data!['sales_by_station'] as List?) ?? [];
    if (raw.isEmpty) {
      return Text(tr('Ma\'lumot yo\'q'), style: TextStyle(color: AppTheme.textSoft));
    }
    double maxV = 1;
    for (final e in raw) {
      final v = _num(e['sales']).toDouble();
      if (v > maxV) maxV = v;
    }
    return Column(
      children: raw.map<Widget>((e) {
        final v = _num(e['sales']).toDouble();
        final frac = maxV > 0 ? (v / maxV) : 0.0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(e['name']?.toString() ?? '', style: TextStyle(color: AppTheme.text, fontSize: 13))),
                  Text('${_money(v)} сом', style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: frac,
                  minHeight: 8,
                  backgroundColor: AppTheme.text.withValues(alpha: 0.08),
                  valueColor: AlwaysStoppedAnimation(_accent),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _twoLists() {
    final top = (_data!['top_items'] as List?) ?? [];
    final waiters = (_data!['waiter_sales'] as List?) ?? [];
    final width = MediaQuery.of(context).size.width;
    final topCard = _listCard(tr('Eng ko\'p sotilgan TOP-5'), Icons.local_fire_department,
        top.asMap().entries.map((e) {
      final i = e.key + 1;
      final it = e.value;
      return _listRow('$i. ${it['name']}', '${it['qty']} ${tr('ta')}');
    }).toList());
    final waiterCard = _listCard(tr('Ofitsantlar reytingi'), Icons.emoji_events,
        waiters.asMap().entries.map((e) {
      final i = e.key + 1;
      final w = e.value;
      return _listRow('$i. ${w['full_name']}', '${_money(_num(w['sales']))} сом');
    }).toList());

    if (width > 900) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Expanded(child: topCard), const SizedBox(width: 12), Expanded(child: waiterCard)],
      );
    }
    return Column(children: [topCard, const SizedBox(height: 12), waiterCard]);
  }

  Widget _listCard(String title, IconData icon, List<Widget> rows) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.textSoft.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: _accent, size: 16),
            const SizedBox(width: 6),
            Text(title, style: TextStyle(color: AppTheme.textSoft, fontSize: 13)),
          ]),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            Text(tr('Ma\'lumot yo\'q'), style: TextStyle(color: AppTheme.textSoft, fontSize: 12))
          else
            ...rows,
        ],
      ),
    );
  }

  Widget _listRow(String left, String right) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(left, style: TextStyle(color: AppTheme.text, fontSize: 13), overflow: TextOverflow.ellipsis)),
          Text(right, style: TextStyle(color: Colors.green, fontSize: 13)),
        ],
      ),
    );
  }
}

// ===== HARAJATLAR BO'LIMI =====
class ExpensesSection extends StatefulWidget {
  const ExpensesSection({super.key});

  @override
  State<ExpensesSection> createState() => _ExpensesSectionState();
}

class _ExpensesSectionState extends State<ExpensesSection> {
  String _period = 'today';
  List<dynamic> _types = [];
  List<dynamic> _expenses = [];
  double _totalKassa = 0;
  double _totalOther = 0;
  bool _loading = true;
  bool _saving = false; // harajat saqlanmoqda — ikki marta bosishdan himoya

  static Color get _accent => AppTheme.accent;
  static Color get _card => AppTheme.card;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final types = await ApiService.get(AppConstants.expenseTypes);
      final out = await ApiService.get('${AppConstants.expenseOutflows}?period=$_period');
      setState(() {
        _types = types is List ? types : [];
        _expenses = (out is Map && out['items'] is List) ? out['items'] as List : [];
        _totalKassa = (out is Map) ? _num(out['total_kassa']).toDouble() : 0;
        _totalOther = (out is Map) ? _num(out['total_other']).toDouble() : 0;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _setPeriod(String p) {
    if (_period == p) return;
    setState(() => _period = p);
    _load();
  }

  num _num(dynamic v) => v is num ? v : (num.tryParse(v?.toString() ?? '0') ?? 0);

  String _money(num v) {
    final s = v.round().toString();
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return b.toString();
  }

  Map<String, double> get _byType {
    final m = <String, double>{};
    for (final e in _expenses) {
      if (e['from_kassa'] == false) continue; // faqat Kassadan ketganlar
      final t = (e['type_name'] ?? tr('Boshqa')).toString();
      m[t] = (m[t] ?? 0) + _num(e['amount']).toDouble();
    }
    return m;
  }

  Future<void> _promptNewType(void Function(int) onCreated) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        title: Text(tr('Yangi harajat turi'), style: TextStyle(color: AppTheme.text)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: AppTheme.text),
          decoration: InputDecoration(
            labelText: tr('Tur nomi (masalan: Reklama)'),
            labelStyle: TextStyle(color: AppTheme.textSoft),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.textSoft)),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: _accent)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accent),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Qo\'shish'), style: TextStyle(color: AppTheme.onAccent)),
          ),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      final res = await ApiService.post(AppConstants.expenseTypes, {'name': ctrl.text.trim()});
      final types = await ApiService.get(AppConstants.expenseTypes);
      setState(() => _types = types is List ? types : []);
      if (res is Map && res['id'] != null) onCreated(res['id'] as int);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Widget _srcToggle(void Function(void Function()) setSt, String label, bool sel, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: () => setSt(onTap),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: sel ? _accent.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: sel ? _accent : AppTheme.border),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(color: sel ? _accent : AppTheme.textSoft, fontWeight: sel ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
        ),
      ),
    );
  }

  Future<void> _addExpense() async {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final unitCtrl = TextEditingController();
    final sourceCtrl = TextEditingController();
    String method = 'cash';
    bool fromKassa = true;
    int? typeId = _types.isNotEmpty ? _types.first['id'] as int : null;

    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: AppTheme.textSoft),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.textSoft)),
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: _accent)),
        );

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setSt) => AlertDialog(
          backgroundColor: _card,
          title: Text(tr('Harajat qo\'shish'), style: TextStyle(color: AppTheme.text)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: typeId,
                  dropdownColor: _card,
                  style: TextStyle(color: AppTheme.text),
                  decoration: deco(tr('Tur')),
                  items: [
                    ..._types.map((t) => DropdownMenuItem<int>(
                      value: t['id'] as int,
                      child: Text(t['name']?.toString() ?? '', style: TextStyle(color: AppTheme.text)),
                    )),
                    DropdownMenuItem<int>(value: -1, child: Text(tr('＋ Yangi tur...'), style: TextStyle(color: _accent))),
                  ],
                  onChanged: (v) {
                    if (v == -1) {
                      _promptNewType((id) => setSt(() => typeId = id));
                    } else {
                      setSt(() => typeId = v);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(controller: nameCtrl, style: TextStyle(color: AppTheme.text), decoration: deco(tr('Nomi (masalan: Mol go\'shti)'))),
                const SizedBox(height: 12),
                TextField(controller: amountCtrl, keyboardType: TextInputType.number, style: TextStyle(color: AppTheme.text), decoration: deco(tr('Summa (сом)'))),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: TextField(controller: qtyCtrl, keyboardType: TextInputType.number, style: TextStyle(color: AppTheme.text), decoration: deco(tr('Miqdor (ixtiyoriy)')))),
                    const SizedBox(width: 8),
                    Expanded(child: TextField(controller: unitCtrl, style: TextStyle(color: AppTheme.text), decoration: deco(tr('O\'lchov (kg/dona)')))),
                  ],
                ),
                const SizedBox(height: 12),
                Row(children: [
                  _srcToggle(setSt, tr('Naqd'), method == 'cash', () => method = 'cash'),
                  const SizedBox(width: 8),
                  _srcToggle(setSt, tr('Karta'), method == 'card', () => method = 'card'),
                ]),
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: Text(tr('Pul manbasi'), style: TextStyle(color: AppTheme.textSoft, fontSize: 12))),
                const SizedBox(height: 4),
                Row(children: [
                  _srcToggle(setSt, tr('Kassadan'), fromKassa, () => fromKassa = true),
                  const SizedBox(width: 8),
                  _srcToggle(setSt, tr('Boshqa joydan'), !fromKassa, () => fromKassa = false),
                ]),
                if (!fromKassa) ...[
                  const SizedBox(height: 6),
                  TextField(controller: sourceCtrl, style: TextStyle(color: AppTheme.text), decoration: deco(tr('Qayerdan'))),
                  const SizedBox(height: 4),
                  Align(alignment: Alignment.centerLeft, child: Text(tr('Kassadan pul yechilmaydi'), style: const TextStyle(color: Colors.teal, fontSize: 11))),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _accent),
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('Saqlash'), style: TextStyle(color: AppTheme.onAccent)),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;
    if (typeId == null || typeId == -1) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Turni tanlang!')), backgroundColor: Colors.red));
      return;
    }
    final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
    if (nameCtrl.text.trim().isEmpty || amount <= 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Nom va summani kiriting!')), backgroundColor: Colors.red));
      return;
    }
    if (_saving) return; // so'rov ketayotganda takror bosish ishlamaydi
    setState(() => _saving = true);
    try {
      // Idempotency-Key — harajat (kassa chiqimi) retry'da ikki marta yozilmasligi uchun
      await ApiService.post(AppConstants.expenses, {
        'expense_type_id': typeId,
        'name': nameCtrl.text.trim(),
        'amount': amount,
        'quantity': double.tryParse(qtyCtrl.text.trim()),
        'unit': unitCtrl.text.trim().isEmpty ? null : unitCtrl.text.trim(),
        'method': method,
        'from_kassa': fromKassa,
        'source': fromKassa ? null : (sourceCtrl.text.trim().isEmpty ? null : sourceCtrl.text.trim()),
      }, idempotencyKey: ApiService.newIdempotencyKey());
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteExpense(Map<String, dynamic> e) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        title: Text(tr('O\'chirish'), style: TextStyle(color: AppTheme.text)),
        content: Text('${e['name']} (${_money(_num(e['amount']))} сом) ${tr('o\'chirilsinmi?')}', style: TextStyle(color: AppTheme.textSoft)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('O\'chirish'), style: TextStyle(color: AppTheme.onAccent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final delId = e['delete_id'] ?? e['id'];
    try {
      await ApiService.delete('${AppConstants.expenses}/$delId');
      _load();
    } catch (_) {}
  }

  // Faqat turlarni qayta yuklash (dialog ichida tez yangilash uchun)
  Future<void> _reloadTypes() async {
    try {
      final types = await ApiService.get(AppConstants.expenseTypes);
      if (mounted) setState(() => _types = types is List ? types : []);
    } catch (_) {}
  }

  // Tur nomini o'zgartirish
  Future<void> _renameType(Map<String, dynamic> t) async {
    final ctrl = TextEditingController(text: t['name']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        title: Text(tr('Tur nomini o\'zgartirish'), style: TextStyle(color: AppTheme.text)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: AppTheme.text),
          decoration: InputDecoration(
            labelText: tr('Tur nomi'),
            labelStyle: TextStyle(color: AppTheme.textSoft),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.textSoft)),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: _accent)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accent),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Saqlash'), style: TextStyle(color: AppTheme.onAccent)),
          ),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      final res = await ApiService.put('${AppConstants.expenseTypes}/${t['id']}', {'name': ctrl.text.trim()});
      if (res is Map && res['id'] == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message']?.toString() ?? tr('Xato')), backgroundColor: Colors.red));
        return;
      }
      await _reloadTypes();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
    }
  }

  // Turni o'chirish (unga oid harajat bo'lsa backend bloklaydi)
  Future<void> _deleteType(Map<String, dynamic> t) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        title: Text(tr('Turni o\'chirish'), style: TextStyle(color: AppTheme.text)),
        content: Text('"${t['name']}" ${tr('o\'chirilsinmi?')}', style: TextStyle(color: AppTheme.textSoft)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('O\'chirish'), style: TextStyle(color: AppTheme.onAccent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final res = await ApiService.delete('${AppConstants.expenseTypes}/${t['id']}');
      if (res is Map && res['deleted'] != true) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message']?.toString() ?? tr('Xato')), backgroundColor: Colors.red));
        return;
      }
      await _reloadTypes();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
    }
  }

  // Xarajat turlarini boshqarish (ro'yxat + qo'shish + tahrir + o'chirish)
  Future<void> _manageTypes() async {
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: _card,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(tr('Xarajat turlari'), style: TextStyle(color: AppTheme.text, fontSize: 17)),
              TextButton.icon(
                onPressed: () async {
                  await _promptNewType((_) {});
                  setSt(() {});
                },
                icon: Icon(Icons.add, size: 18, color: _accent),
                label: Text(tr('Qo\'shish'), style: TextStyle(color: _accent, fontSize: 13)),
              ),
            ],
          ),
          content: SizedBox(
            width: 340,
            child: _types.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(tr('Tur yo\'q'), style: TextStyle(color: AppTheme.textSoft)),
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: _types.map((t) {
                        final name = t['name']?.toString() ?? '';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Icon(Icons.label_outline, size: 16, color: AppTheme.textSoft),
                              const SizedBox(width: 8),
                              Expanded(child: Text(name, style: TextStyle(color: AppTheme.text, fontSize: 14))),
                              IconButton(
                                icon: Icon(Icons.edit, size: 18, color: Colors.blue),
                                visualDensity: VisualDensity.compact,
                                tooltip: tr('Tahrirlash'),
                                onPressed: () async { await _renameType(t); setSt(() {}); },
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                visualDensity: VisualDensity.compact,
                                tooltip: tr('O\'chirish'),
                                onPressed: () async { await _deleteType(t); setSt(() {}); },
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Yopish'), style: TextStyle(color: _accent))),
          ],
        ),
      ),
    );
    _load(); // nomlar o'zgargan bo'lsa taqsimotni yangilash
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _accent,
        onPressed: _addExpense,
        icon: Icon(Icons.add, color: AppTheme.onAccent),
        label: Text(tr('Harajat'), style: TextStyle(color: AppTheme.onAccent)),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: _accent))
          : RefreshIndicator(
              color: _accent,
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: _periodFilter(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _manageTypes,
                          icon: Icon(Icons.category_outlined, size: 18, color: _accent),
                          label: Text(tr('Turlar'), style: TextStyle(color: _accent, fontSize: 13)),
                          style: OutlinedButton.styleFrom(side: BorderSide(color: _accent.withValues(alpha: 0.5))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _summary(),
                    const SizedBox(height: 16),
                    if (_byType.isNotEmpty) ...[
                      _breakdownCard(),
                      const SizedBox(height: 16),
                    ],
                    _expenseList(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _periodFilter() {
    Widget pill(String label, String p) {
      final sel = _period == p;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => _setPeriod(p),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? _accent : _card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: sel ? _accent : AppTheme.textSoft.withValues(alpha: 0.4)),
            ),
            child: Text(label,
                style: TextStyle(color: sel ? AppTheme.text : AppTheme.textSoft, fontWeight: sel ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
          ),
        ),
      );
    }

    return Row(children: [pill(tr('Bugun'), 'today'), pill(tr('Hafta'), 'week'), pill(tr('Oy'), 'month')]);
  }

  Widget _summary() {
    final byType = _byType;
    String biggest = '—';
    double maxV = 0;
    byType.forEach((k, v) {
      if (v > maxV) { maxV = v; biggest = k; }
    });
    final hasOther = _totalOther > 0;
    return Row(
      children: [
        Expanded(child: _sumCard(tr('Kassadan jami'), '${_money(_totalKassa)} сом', Colors.red)),
        const SizedBox(width: 12),
        Expanded(child: _sumCard(tr('Soni'), '${_expenses.length}', Colors.blueAccent)),
        const SizedBox(width: 12),
        Expanded(child: hasOther
            ? _sumCard(tr('Boshqa manbadan'), '${_money(_totalOther)} сом', Colors.teal)
            : _sumCard(tr('Eng katta tur'), biggest == '—' ? '—' : tr(biggest), Colors.orange)),
      ],
    );
  }

  Widget _sumCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _breakdownCard() {
    final byType = _byType;
    final entries = byType.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final maxV = entries.isNotEmpty ? entries.first.value : 1;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.textSoft.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Tur bo\'yicha taqsimot'), style: TextStyle(color: AppTheme.textSoft, fontSize: 13)),
          const SizedBox(height: 12),
          ...entries.map((e) {
            final frac = maxV > 0 ? e.value / maxV : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(child: Text(tr(e.key), style: TextStyle(color: AppTheme.text, fontSize: 13))),
                    Text('${_money(e.value)} сом', style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
                  ]),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: frac,
                      minHeight: 8,
                      backgroundColor: AppTheme.text.withValues(alpha: 0.08),
                      valueColor: AlwaysStoppedAnimation(_accent),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _expenseList() {
    if (_expenses.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 40),
        alignment: Alignment.center,
        child: Text(tr('Harajat yo\'q'), style: TextStyle(color: AppTheme.textSoft, fontSize: 16)),
      );
    }
    return Column(
      children: _expenses.map<Widget>((e) {
        final qty = e['quantity'];
        final unit = e['unit'];
        final t = DateTime.tryParse(e['created_at']?.toString() ?? '');
        final timeStr = t != null
            ? '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}'
            : '';
        final qtyStr = (qty != null && _num(qty) > 0) ? '${_num(qty)} ${unit ?? ''} · ' : '';
        final method = e['method'] == 'card' ? tr('Karta') : tr('Naqd');
        final notKassa = e['from_kassa'] == false;
        final canDelete = e['can_delete'] == true;
        final src = e['source']?.toString() ?? 'expense';
        final badgeColor = src == 'salary' || src == 'advance'
            ? Colors.purple
            : src == 'stock'
                ? Colors.teal
                : src == 'manual'
                    ? Colors.blueGrey
                    : Colors.red;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.textSoft.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(tr(e['type_name']?.toString() ?? ''), style: TextStyle(color: badgeColor, fontSize: 11, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e['name']?.toString() ?? '', style: TextStyle(color: AppTheme.text, fontSize: 14)),
                    Text('$qtyStr$timeStr • $method${notKassa ? ' • ${tr('Boshqa joydan')}' : ''}',
                        style: TextStyle(color: notKassa ? Colors.teal : AppTheme.textSoft, fontSize: 12)),
                  ],
                ),
              ),
              Text('-${_money(_num(e['amount']))} сом', style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 14)),
              if (canDelete)
                IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.red, size: 20),
                  onPressed: () => _deleteExpense(e),
                )
              else
                const SizedBox(width: 12),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ===== MENYU BO'LIMI =====
class MenuSection extends StatefulWidget {
  const MenuSection({super.key});

  @override
  State<MenuSection> createState() => _MenuSectionState();
}

class _MenuSectionState extends State<MenuSection> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _categories = [];
  List<dynamic> _items = [];
  List<dynamic> _ingredients = [];
  List<dynamic> _warehouses = [];
  List<dynamic> _stations = [];
  int? _selectedWarehouseId;
  final Map<int, Map<String, dynamic>> _costs = {};
  bool _isLoading = true;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  String _catSearchQuery = '';
  final TextEditingController _catSearchController = TextEditingController();
  String _itemSearchQuery = '';
  final TextEditingController _itemSearchController = TextEditingController();
  final Set<String> _expandedCategories = {};
  final Set<String> _expandedMenuCategories = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _catSearchController.dispose();
    _itemSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final cats = await ApiService.get(AppConstants.menuCategories);
      final items = await ApiService.get(AppConstants.menuItems);
      final whs = await ApiService.get(AppConstants.warehouses);
      final warehouses = whs is List ? whs : [];
      final sts = await ApiService.get(AppConstants.stations);

      // Tanlangan sklad: oldingisi hali mavjud bo'lsa saqlaymiz, aks holda 1-skladni
      int? selected = _selectedWarehouseId;
      final exists = warehouses.any((w) => w['id'] == selected);
      if (!exists) {
        selected = warehouses.isNotEmpty ? warehouses.first['id'] as int : null;
      }

      final ings = selected != null
          ? await ApiService.get('${AppConstants.stock}?warehouse_id=$selected')
          : await ApiService.get(AppConstants.stock);

      setState(() {
        _categories = cats is List ? cats : [];
        _items = items is List ? items : [];
        _warehouses = warehouses;
        _stations = sts is List ? sts : [];
        _selectedWarehouseId = selected;
        _ingredients = ings is List ? ings : [];
      });
      _loadCosts();
    } catch (e) {
      print('Xato: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // STOP-LIST: taomni "tayyor"/"tayyor emas" qilish
  // Kunlik kuzat belgisini almashtirish (somsa kabi taomlar uchun)
  Future<void> _toggleDailyTrack(Map item) async {
    final newVal = item['daily_tracked'] != true;
    try {
      await ApiService.put('${AppConstants.menuItems}/${item['id']}/daily-track', {'tracked': newVal});
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(newVal
              ? '"${item['name']}" — ${tr('kunlik kuzat YOQILDI (Bosh sahifada son kiriting)')}'
              : '"${item['name']}" — ${tr('kunlik kuzat o\'chirildi')}'),
          backgroundColor: newVal ? Colors.purple : AppTheme.textSoft,
          duration: const Duration(milliseconds: 1800),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _toggleAvailable(Map item) async {
    final newVal = item['available'] == false; // hozir stop bo'lsa -> tayyor, aksincha
    try {
      await ApiService.put('${AppConstants.menuItems}/${item['id']}/available', {'available': newVal});
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(newVal
              ? '"${item['name']}" — ${tr('tayyor (zakaz qilsa bo\'ladi)')}'
              : '"${item['name']}" — ${tr('STOP (tayyor emas)')}'),
          backgroundColor: newVal ? Colors.green : Colors.red,
          duration: const Duration(milliseconds: 1500),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // Faqat tanlangan sklad mahsulotlarini qayta yuklash
  Future<void> _reloadIngredients() async {
    final selected = _selectedWarehouseId;
    final ings = selected != null
        ? await ApiService.get('${AppConstants.stock}?warehouse_id=$selected')
        : await ApiService.get(AppConstants.stock);
    if (mounted) {
      setState(() => _ingredients = ings is List ? ings : []);
    }
  }

  // Sklad tanlash
  Future<void> _selectWarehouse(int id) async {
    if (_selectedWarehouseId == id) return;
    setState(() {
      _selectedWarehouseId = id;
      _searchController.clear();
      _searchQuery = '';
      _expandedCategories.clear();
    });
    await _reloadIngredients();
  }

  // Yangi sklad qo'shish
  void _showAddWarehouseDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('Yangi sklad'), style: TextStyle(color: AppTheme.text)),
        content: _buildTextField(nameController, tr('Sklad nomi'), Icons.warehouse),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              final res = await ApiService.post(AppConstants.warehouses, {'name': name});
              Navigator.pop(context);
              if (res is Map && res['id'] != null) {
                _selectedWarehouseId = res['id'] as int;
              }
              await _loadData();
            },
            child: Text(tr('Saqlash'), style: TextStyle(color: AppTheme.text)),
          ),
        ],
      ),
    );
  }

  // Sklad tahrir/o'chirish (uzoq bosilganda)
  void _showWarehouseOptions(Map<String, dynamic> wh) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.card,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.edit, color: Colors.blue),
              title: Text(tr('Nomini o\'zgartirish'), style: TextStyle(color: AppTheme.text)),
              onTap: () {
                Navigator.pop(context);
                _showEditWarehouseDialog(wh);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Colors.red),
              title: Text(tr('Skladni o\'chirish'), style: TextStyle(color: AppTheme.text)),
              onTap: () {
                Navigator.pop(context);
                _confirmDeleteWarehouse(wh);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEditWarehouseDialog(Map<String, dynamic> wh) {
    final nameController = TextEditingController(text: wh['name']?.toString() ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('Sklad nomi'), style: TextStyle(color: AppTheme.text)),
        content: _buildTextField(nameController, tr('Sklad nomi'), Icons.warehouse),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              await ApiService.put('${AppConstants.warehouses}/${wh['id']}', {'name': name});
              Navigator.pop(context);
              await _loadData();
            },
            child: Text(tr('Saqlash'), style: TextStyle(color: AppTheme.text)),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteWarehouse(Map<String, dynamic> wh) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('Skladni o\'chirish'), style: TextStyle(color: AppTheme.text)),
        content: Text('"${wh['name']}" ${tr('skladini o\'chirilsinmi?')}', style: TextStyle(color: AppTheme.textSoft)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final result = await ApiService.delete('${AppConstants.warehouses}/${wh['id']}');
              Navigator.pop(context);
              final msg = (result is Map && result['message'] != null)
                  ? result['message'].toString()
                  : tr('Bajarildi');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
              }
              if (_selectedWarehouseId == wh['id']) {
                _selectedWarehouseId = null;
              }
              await _loadData();
            },
            child: Text(tr('O\'chirish'), style: TextStyle(color: AppTheme.text)),
          ),
        ],
      ),
    );
  }

  void _loadCosts() {
    for (final item in _items) {
      final id = item['id'] as int;
      ApiService.get('/menu/items/$id/cost').then((data) {
        if (mounted && data is Map) {
          setState(() => _costs[id] = Map<String, dynamic>.from(data));
        }
      }).catchError((_) {});
    }
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: AppTheme.textSoft),
      prefixIcon: Icon(icon, color: AppTheme.accent),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.textSoft)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.accent)),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool isNumber = false, VoidCallback? onTap}) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: TextStyle(color: AppTheme.text),
      decoration: _inputDecoration(label, icon),
      onTap: onTap,
    );
  }

  Future<void> _showEditCategoryDialog(dynamic cat) async {
    final ctrl = TextEditingController(text: cat['name'].toString());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('Kategoriya tahrirlash'), style: TextStyle(color: AppTheme.text)),
        content: _buildTextField(ctrl, tr('Kategoriya nomi'), Icons.category),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Saqlash')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await ApiService.put('${AppConstants.menuCategories}/${cat['id']}', {'name': ctrl.text.trim()});
        _loadData();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmDeleteCategory(dynamic cat) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr("O'chirish"), style: TextStyle(color: AppTheme.text)),
        content: Text(
          "'${cat['name']}' ${tr("kategoriyasini o'chirishni tasdiqlaysizmi?\nFaqat bo'sh kategoriyalarni o'chirish mumkin.")}",
          style: TextStyle(color: AppTheme.textSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr("O'chirish")),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await ApiService.delete('${AppConstants.menuCategories}/${cat['id']}');
        _loadData();
      } catch (e) {
        final msg = e.toString().contains('400') ? tr('Kategoriyada faol taomlar bor!') : '${tr('Xato')}: $e';
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmDeleteMenuItem(dynamic item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr("O'chirish"), style: TextStyle(color: AppTheme.text)),
        content: Text(
          "'${item['name']}' ${tr("taomini o'chirishni tasdiqlaysizmi?")}",
          style: TextStyle(color: AppTheme.textSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr("O'chirish")),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await ApiService.delete('${AppConstants.menuItems}/${item['id']}');
        _loadData();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showAddCategoryDialog() {
    final nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('Kategoriya qo\'shish'), style: TextStyle(color: AppTheme.text)),
        content: _buildTextField(nameController, tr('Kategoriya nomi'), Icons.category),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
            onPressed: () async {
              if (nameController.text.isEmpty) return;
              await ApiService.post(AppConstants.menuCategories, {'name': nameController.text});
              Navigator.pop(context);
              _loadData();
            },
            child: Text(tr('Saqlash'), style: TextStyle(color: AppTheme.text)),
          ),
        ],
      ),
    );
  }

  // Ko'p-bo'lim tanlash (taom bir nechta sexga chek chiqarishi mumkin)
  Widget _buildStationPicker(Set<int> selected, StateSetter setSt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.print, color: AppTheme.accent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(tr('Bo\'lim(lar) — chek shu sexlardan chiqadi'),
                style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
          ),
        ]),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _stations.map((s) {
            final sid = s['id'] as int;
            final sel = selected.contains(sid);
            return FilterChip(
              label: Text(s['name']?.toString() ?? ''),
              selected: sel,
              onSelected: (v) => setSt(() {
                if (v) {
                  selected.add(sid);
                } else {
                  selected.remove(sid);
                }
              }),
              backgroundColor: AppTheme.bg,
              selectedColor: AppTheme.accent.withValues(alpha: 0.25),
              checkmarkColor: AppTheme.accent,
              labelStyle: TextStyle(color: sel ? AppTheme.accent : AppTheme.text, fontSize: 13),
              side: BorderSide(color: sel ? AppTheme.accent : AppTheme.border),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _showAddItemDialog() {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    int? selectedCategoryId = _categories.isNotEmpty ? _categories[0]['id'] : null;
    final Set<int> selectedStationIds =
        _stations.isNotEmpty ? <int>{_stations[0]['id'] as int} : <int>{};
    XFile? pickedImage;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text(tr('Taom qo\'shish'), style: TextStyle(color: AppTheme.text)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Rasm tanlash
                GestureDetector(
                  onTap: () async {
                    final picker = ImagePicker();
                    final image = await picker.pickImage(
                      source: ImageSource.gallery,
                      imageQuality: 80,
                    );
                    if (image != null) {
                      setStateDialog(() => pickedImage = image);
                    }
                  },
                  child: Container(
                    height: 140,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppTheme.bg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.accent.withOpacity(0.5)),
                    ),
                    child: pickedImage != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(pickedImage!.path),
                              fit: BoxFit.cover,
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_a_photo, color: AppTheme.accent, size: 36),
                              SizedBox(height: 8),
                              Text(tr('Rasm tanlash'), style: TextStyle(color: AppTheme.textSoft, fontSize: 13)),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                _buildTextField(nameController, tr('Taom nomi'), Icons.restaurant),
                const SizedBox(height: 12),
                _buildTextField(priceController, tr('Narxi (so\'m)'), Icons.monetization_on, isNumber: true,
                  onTap: () => priceController.selection = TextSelection(
                    baseOffset: 0, extentOffset: priceController.text.length)),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: selectedCategoryId,
                  dropdownColor: AppTheme.card,
                  style: TextStyle(color: AppTheme.text),
                  decoration: _inputDecoration(tr('Kategoriya'), Icons.category),
                  items: _categories.map((c) => DropdownMenuItem<int>(
                    value: c['id'],
                    child: Text(c['name'], style: TextStyle(color: AppTheme.text)),
                  )).toList(),
                  onChanged: (v) => setStateDialog(() => selectedCategoryId = v),
                ),
                const SizedBox(height: 12),
                // Bo'lim(lar) (printer) — chek qaysi sex printer(lar)iga chiqishi (bir nechta bo'lishi mumkin)
                _buildStationPicker(selectedStationIds, setStateDialog),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
              onPressed: () async {
                if (nameController.text.isEmpty || priceController.text.isEmpty) return;

                List<int>? imageBytes;
                String imageFilename = 'image.jpg';
                if (pickedImage != null) {
                  imageBytes = await pickedImage!.readAsBytes();
                  final name = pickedImage!.name;
                  imageFilename = name.isNotEmpty ? name : 'image.jpg';
                }

                try {
                  await ApiService.postWithImage(
                    AppConstants.menuItems,
                    name: nameController.text,
                    price: double.tryParse(priceController.text) ?? 0,
                    categoryId: selectedCategoryId,
                    stationIds: selectedStationIds.toList(),
                    imageBytes: imageBytes,
                    imageFilename: imageFilename,
                  );
                  if (context.mounted) Navigator.pop(context);
                  _loadData();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: Text(tr('Saqlash'), style: TextStyle(color: AppTheme.text)),
            ),
          ],
        ),
      ),
    );
  }

  void _showRecipeDialog(Map<String, dynamic> item) async {
    final recipeData = await ApiService.get('/menu/recipe/${item['id']}');
    final recipeList = recipeData is List ? recipeData : [];

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text('${item['name']} — ${tr('retsept')}', style: TextStyle(color: AppTheme.text)),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (recipeList.isEmpty)
                  Text(tr('Masaliqlar kiritilmagan'), style: TextStyle(color: AppTheme.textSoft))
                else
                  ...recipeList.map((r) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppTheme.bg, borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        Expanded(child: Text(r['ingredient_name'], style: TextStyle(color: AppTheme.text))),
                        Text('${r['quantity']} ${r['unit']}', style: TextStyle(color: AppTheme.accent)),
                        IconButton(
                          icon: Icon(Icons.delete, color: Colors.red, size: 18),
                          onPressed: () async {
                            await ApiService.delete('/menu/recipe/${r['id']}');
                            Navigator.pop(context);
                            _showRecipeDialog(item);
                          },
                        ),
                      ],
                    ),
                  )),
                Divider(color: AppTheme.textSoft),
                _showAddRecipeForm(item['id'], () {
                  Navigator.pop(context);
                  _showRecipeDialog(item);
                }),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Yopish'), style: TextStyle(color: AppTheme.textSoft))),
        ],
      ),
    );
  }

  Widget _showAddRecipeForm(int menuItemId, VoidCallback onSaved) {
    final quantityController = TextEditingController();
    String selectedUnit = 'kg';
    const units = ['kg', 'g', 'litr', 'ml', 'dona', 'pachka'];
    String ingredientName = '';

    return StatefulBuilder(
      builder: (context, setStateForm) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Masaliq qo\'shish'),
              style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Autocomplete<Map<String, dynamic>>(
            optionsBuilder: (TextEditingValue textValue) {
              ingredientName = textValue.text;
              if (textValue.text.isEmpty) return const Iterable.empty();
              return _ingredients.cast<Map<String, dynamic>>().where((ing) =>
                  (ing['name'] as String)
                      .toLowerCase()
                      .contains(textValue.text.toLowerCase()));
            },
            displayStringForOption: (option) => option['name'] as String,
            onSelected: (option) {
              final unit = option['unit'] as String? ?? 'kg';
              setStateForm(() {
                ingredientName = option['name'] as String;
                selectedUnit = units.contains(unit) ? unit : 'kg';
              });
            },
            fieldViewBuilder: (context, textController, focusNode, onSubmit) {
              return TextField(
                controller: textController,
                focusNode: focusNode,
                style: TextStyle(color: AppTheme.text),
                decoration: InputDecoration(
                  labelText: tr('Masaliq nomi'),
                  labelStyle: TextStyle(color: AppTheme.textSoft),
                  prefixIcon: Icon(Icons.inventory, color: AppTheme.accent),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppTheme.textSoft)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppTheme.accent)),
                ),
              );
            },
            optionsViewBuilder: (context, onSelected, options) => Align(
              alignment: Alignment.topLeft,
              child: Material(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(8),
                elevation: 6,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options.elementAt(index);
                      return ListTile(
                        dense: true,
                        title: Text(option['name'] as String,
                            style: TextStyle(color: AppTheme.text)),
                        trailing: Text(option['unit'] as String? ?? '',
                            style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
                        onTap: () => onSelected(option),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildTextField(quantityController, tr('Miqdori'), Icons.scale,
                    isNumber: true),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 100,
                child: DropdownButtonFormField<String>(
                  value: selectedUnit,
                  isExpanded: true,
                  dropdownColor: AppTheme.card,
                  style: TextStyle(color: AppTheme.text),
                  decoration: InputDecoration(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppTheme.textSoft)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: AppTheme.accent)),
                  ),
                  items: units
                      .map((u) => DropdownMenuItem(
                            value: u,
                            child: Text(u, style: TextStyle(color: AppTheme.text)),
                          ))
                      .toList(),
                  onChanged: (v) => setStateForm(() => selectedUnit = v ?? 'kg'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
              onPressed: () async {
                if (ingredientName.trim().isEmpty || quantityController.text.isEmpty) return;
                await ApiService.post(AppConstants.menuRecipe, {
                  'menu_item_id': menuItemId,
                  'ingredient_name': ingredientName.trim(),
                  'unit': selectedUnit,
                  'quantity': double.tryParse(quantityController.text) ?? 0,
                });
                onSaved();
              },
              child: Text(tr('Qo\'shish'), style: TextStyle(color: AppTheme.text)),
            ),
          ),
        ],
      ),
    );
  }

  String get _selectedWarehouseName {
    final wh = _warehouses.firstWhere(
      (w) => w['id'] == _selectedWarehouseId,
      orElse: () => null,
    );
    return wh != null ? (wh['name']?.toString() ?? '') : '';
  }

  void _showAddIngredientDialog() {
    final nameController = TextEditingController();
    final quantityController = TextEditingController();
    final minQuantityController = TextEditingController();
    final priceController = TextEditingController();
    final sellingPriceController = TextEditingController();
    String selectedUnit = 'kg';
    String selectedCategory = 'Ингредиенты';
    final units = ['kg', 'g', 'litr', 'ml', 'dona', 'pachka'];
    const stockCategories = ['Продукция', 'Десерт', 'Холодные напитки', 'Ингредиенты', 'П/Ф'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          final isRetail = _retailCategories.contains(selectedCategory);
          return AlertDialog(
            backgroundColor: AppTheme.card,
            title: Text(
              _selectedWarehouseName.isEmpty
                  ? tr('Sklad — mahsulot qo\'shish')
                  : '$_selectedWarehouseName — ${tr('mahsulot qo\'shish')}',
              style: TextStyle(color: AppTheme.text, fontSize: 17),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTextField(nameController, tr('Mahsulot nomi'), Icons.inventory),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedUnit,
                    dropdownColor: AppTheme.card,
                    style: TextStyle(color: AppTheme.text),
                    decoration: _inputDecoration(tr('O\'lchov birligi'), Icons.scale),
                    items: units.map((u) => DropdownMenuItem<String>(
                      value: u,
                      child: Text(u, style: TextStyle(color: AppTheme.text)),
                    )).toList(),
                    onChanged: (v) => setStateDialog(() => selectedUnit = v!),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedCategory,
                    dropdownColor: AppTheme.card,
                    style: TextStyle(color: AppTheme.text),
                    decoration: _inputDecoration(tr('Kategoriya'), Icons.folder_outlined),
                    items: stockCategories.map((c) => DropdownMenuItem<String>(
                      value: c,
                      child: Text(c, style: TextStyle(color: AppTheme.text, fontSize: 13)),
                    )).toList(),
                    onChanged: (v) => setStateDialog(() {
                      selectedCategory = v!;
                      if (selectedCategory == 'Десерт' || selectedCategory == 'Холодные напитки') {
                        selectedUnit = 'dona';
                      } else if (selectedCategory == 'Ингредиенты' || selectedCategory == 'П/Ф') {
                        selectedUnit = 'kg';
                      }
                    }),
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(quantityController, tr('Boshlang\'ich miqdor'), Icons.numbers, isNumber: true),
                  const SizedBox(height: 12),
                  _buildTextField(
                    priceController,
                    isRetail ? tr('Kirish narxi (so\'m)') : tr('Narxi (so\'m)'),
                    Icons.monetization_on,
                    isNumber: true,
                    onTap: () => priceController.selection = TextSelection(
                      baseOffset: 0, extentOffset: priceController.text.length),
                  ),
                  if (isRetail) ...[
                    const SizedBox(height: 12),
                    _buildTextField(sellingPriceController, tr('Sotish narxi (so\'m)'), Icons.sell, isNumber: true,
                      onTap: () => sellingPriceController.selection = TextSelection(
                        baseOffset: 0, extentOffset: sellingPriceController.text.length)),
                  ],
                  const SizedBox(height: 12),
                  _buildTextField(minQuantityController, tr('Minimum miqdor (ogohlantirish)'), Icons.warning, isNumber: true),
                  const SizedBox(height: 4),
                  Text(tr('* Bu miqdordan kam bo\'lsa xabar beriladi'), style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
                onPressed: () async {
                  if (nameController.text.isEmpty) return;
                  await ApiService.post(AppConstants.stock, {
                    'name': nameController.text,
                    'unit': selectedUnit,
                    'category': selectedCategory,
                    'stock_quantity': double.tryParse(quantityController.text) ?? 0,
                    'min_quantity': double.tryParse(minQuantityController.text) ?? 0,
                    'price_per_unit': double.tryParse(priceController.text) ?? 0,
                    'selling_price': isRetail
                        ? (double.tryParse(sellingPriceController.text) ?? 0)
                        : 0,
                    'warehouse_id': _selectedWarehouseId,
                  });
                  Navigator.pop(context);
                  _loadData();
                },
                child: Text(tr('Saqlash'), style: TextStyle(color: AppTheme.text)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _noImagePlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_a_photo, color: AppTheme.accent, size: 36),
        SizedBox(height: 8),
        Text(tr('Rasm tanlash'), style: TextStyle(color: AppTheme.textSoft, fontSize: 13)),
      ],
    );
  }

  void _showEditItemDialog(Map<String, dynamic> item) {
    final nameController = TextEditingController(text: item['name'] ?? '');
    final priceController = TextEditingController(text: (item['price'] ?? '').toString());
    int? selectedCategoryId = item['category_id'] is int
        ? item['category_id']
        : int.tryParse(item['category_id']?.toString() ?? '');
    final Set<int> selectedStationIds = <int>{};
    final dynamic sids = item['station_ids'];
    if (sids is List && sids.isNotEmpty) {
      for (final e in sids) {
        final n = e is int ? e : int.tryParse(e.toString());
        if (n != null) selectedStationIds.add(n);
      }
    } else {
      final single = item['station_id'] is int
          ? item['station_id'] as int
          : int.tryParse(item['station_id']?.toString() ?? '');
      if (single != null) selectedStationIds.add(single);
    }
    XFile? pickedImage;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text(tr('Taomni tahrirlash'), style: TextStyle(color: AppTheme.text)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Rasm
                GestureDetector(
                  onTap: () async {
                    final picker = ImagePicker();
                    final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
                    if (image != null) setStateDialog(() => pickedImage = image);
                  },
                  child: Container(
                    height: 140,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppTheme.bg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.accent.withOpacity(0.5)),
                    ),
                    child: pickedImage != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(File(pickedImage!.path), fit: BoxFit.cover),
                          )
                        : item['image_url'] != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  '${AppConstants.imageBase}${item['image_url']}',
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _noImagePlaceholder(),
                                ),
                              )
                            : _noImagePlaceholder(),
                  ),
                ),
                const SizedBox(height: 6),
                Text(tr('Rasmni o\'zgartirish uchun bosing (ixtiyoriy)'),
                    style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
                const SizedBox(height: 12),
                _buildTextField(nameController, tr('Taom nomi'), Icons.restaurant),
                const SizedBox(height: 12),
                _buildTextField(priceController, tr('Narxi (so\'m)'), Icons.monetization_on, isNumber: true,
                  onTap: () => priceController.selection = TextSelection(
                    baseOffset: 0, extentOffset: priceController.text.length)),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: selectedCategoryId,
                  dropdownColor: AppTheme.card,
                  style: TextStyle(color: AppTheme.text),
                  decoration: _inputDecoration(tr('Kategoriya'), Icons.category),
                  items: _categories.map((c) => DropdownMenuItem<int>(
                    value: c['id'] as int,
                    child: Text(c['name'] as String, style: TextStyle(color: AppTheme.text)),
                  )).toList(),
                  onChanged: (v) => setStateDialog(() => selectedCategoryId = v),
                ),
                const SizedBox(height: 12),
                _buildStationPicker(selectedStationIds, setStateDialog),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
              onPressed: () async {
                if (nameController.text.isEmpty || priceController.text.isEmpty) return;

                List<int>? imageBytes;
                String imageFilename = 'image.jpg';
                if (pickedImage != null) {
                  imageBytes = await pickedImage!.readAsBytes();
                  final n = pickedImage!.name;
                  imageFilename = n.isNotEmpty ? n : 'image.jpg';
                }

                try {
                  await ApiService.putWithImage(
                    '${AppConstants.menuItems}/${item['id']}',
                    name: nameController.text,
                    price: double.tryParse(priceController.text) ?? 0,
                    categoryId: selectedCategoryId,
                    stationIds: selectedStationIds.toList(),
                    isActive: item['is_active'] ?? true,
                    imageBytes: imageBytes,
                    imageFilename: imageFilename,
                  );
                  if (context.mounted) Navigator.pop(context);
                  _loadData();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: Text(tr('Saqlash'), style: TextStyle(color: AppTheme.text)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDishCard(dynamic item) {
    final itemId = item['id'] as int;
    final cost = _costs[itemId];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.accentSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: item['image_url'] != null
                ? Image.network(
                    '${AppConstants.imageBase}${item['image_url']}',
                    width: 54, height: 54, fit: BoxFit.cover,
                    errorBuilder: (c, e, s) =>
                        Icon(Icons.restaurant, color: AppTheme.accent, size: 40),
                  )
                : Icon(Icons.restaurant, color: AppTheme.accent, size: 40),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['name'].toString(),
                    style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                if (cost != null) ...[
                  Text('${tr('Tannarx')}: ${cost['cost']} ${tr('so\'m')}',
                      style: TextStyle(color: Colors.orange.shade800, fontSize: 12)),
                  Text('${tr('Foyda')}: ${cost['profit']} ${tr('so\'m')}  (${cost['profit_percent']}%)',
                      style: TextStyle(
                        color: (cost['profit'] as num) >= 0 ? Colors.green.shade700 : Colors.red,
                        fontSize: 12,
                      )),
                ] else
                  Text(tr('Tannarx hisoblanmoqda...'),
                      style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${item['price']} ${tr('so\'m')}',
                  style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item['type'] != 'product') ...[
                    GestureDetector(
                      onTap: () => _showRecipeDialog(item),
                      child: Text(tr('Retsept'),
                          style: TextStyle(color: Colors.blue, fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                  ],
                  GestureDetector(
                    onTap: () => _showEditItemDialog(item),
                    child: Icon(Icons.edit, color: AppTheme.accent, size: 16),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // SKLAD TANLASH — gorizontal chip tugmalar
  Widget _buildWarehouseSelector() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ..._warehouses.map((w) {
            final id = w['id'] as int;
            final selected = id == _selectedWarehouseId;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
              child: GestureDetector(
                onTap: () => _selectWarehouse(id),
                onLongPress: () => _showWarehouseOptions(Map<String, dynamic>.from(w)),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.accent : AppTheme.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: selected ? AppTheme.accent : AppTheme.textSoft.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warehouse,
                          size: 16,
                          color: selected ? AppTheme.text : AppTheme.textSoft),
                      const SizedBox(width: 6),
                      Text(
                        w['name']?.toString() ?? '',
                        style: TextStyle(
                          color: selected ? AppTheme.text : AppTheme.textSoft,
                          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          // + Yangi sklad
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: GestureDetector(
              onTap: _showAddWarehouseDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.accent.withValues(alpha: 0.6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 16, color: AppTheme.accent),
                    SizedBox(width: 4),
                    Text(tr('Yangi sklad'),
                        style: TextStyle(color: AppTheme.accent, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
          // Retseptdan biriktirish
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: GestureDetector(
              onTap: _showAssignFromRecipeDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.sync, size: 16, color: Colors.blueAccent),
                    SizedBox(width: 4),
                    Text(tr('Retseptdan biriktirish'),
                        style: TextStyle(color: Colors.blueAccent, fontSize: 13)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Retsept bo'yicha ingredientlarni tanlangan skladga biriktirish
  void _showAssignFromRecipeDialog() {
    if (_selectedWarehouseId == null) return;
    final whName = _selectedWarehouseName;
    final categoryController = TextEditingController();
    final nameController = TextEditingController();
    // Sklad nomiga qarab aqlli oldindan to'ldirish
    final lower = whName.toLowerCase();
    if (lower.contains('shashlik') || lower.contains('шашлык')) {
      categoryController.text = 'Шашлык';
    } else if (lower.contains('somsa') || lower.contains('сомса')) {
      nameController.text = 'сомса';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text('$whName — ${tr('retseptdan biriktirish')}',
            style: TextStyle(color: AppTheme.text, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              tr('Tanlangan taomlar retseptidagi ingredientlar shu skladga biriktiriladi. Kamida bittasini to\'ldiring.'),
              style: TextStyle(color: AppTheme.textSoft, fontSize: 12),
            ),
            const SizedBox(height: 12),
            _buildTextField(categoryController, tr('Kategoriya nomi (masalan: Шашлык)'), Icons.folder_outlined),
            const SizedBox(height: 12),
            _buildTextField(nameController, tr('Taom nomi qismi (masalan: сомса)'), Icons.restaurant_menu),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
            onPressed: () async {
              final cat = categoryController.text.trim();
              final nm = nameController.text.trim();
              if (cat.isEmpty && nm.isEmpty) return;
              final res = await ApiService.post(AppConstants.stockAssignFromRecipe, {
                'warehouse_id': _selectedWarehouseId,
                'category_name': cat,
                'name_like': nm,
              });
              Navigator.pop(context);
              final count = (res is Map && res['count'] != null) ? res['count'] : 0;
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('$count ${tr('ta ingredient biriktirildi')}')),
                );
              }
              await _reloadIngredients();
            },
            child: Text(tr('Biriktirish'), style: TextStyle(color: AppTheme.text)),
          ),
        ],
      ),
    );
  }

  Widget _buildSkaldTab() {
    final filtered = _searchQuery.isEmpty
        ? _ingredients
        : _ingredients.where((i) {
            final name = (i['name'] as String? ?? '').toLowerCase();
            return name.contains(_searchQuery.toLowerCase());
          }).toList();

    final Map<String, List<dynamic>> grouped = {};
    for (final ing in filtered) {
      final cat = (ing['category'] as String?) ?? 'Бошқалар';
      grouped.putIfAbsent(cat, () => []).add(ing);
    }

    const categoryOrder = ['Продукция', 'Десерт', 'Холодные напитки', 'Ингредиенты', 'П/Ф'];
    final sortedCategories = grouped.keys.toList()
      ..sort((a, b) {
        final ai = categoryOrder.indexOf(a);
        final bi = categoryOrder.indexOf(b);
        if (ai == -1 && bi == -1) return a.compareTo(b);
        if (ai == -1) return 1;
        if (bi == -1) return -1;
        return ai.compareTo(bi);
      });

    // Qidiruv aktiv bo'lsa natijali kategoriyalar avtomatik ochiladi
    final bool searchActive = _searchQuery.isNotEmpty;

    final List<Widget> listItems = [];
    for (final cat in sortedCategories) {
      final isExpanded = searchActive || _expandedCategories.contains(cat);
      listItems.add(_buildCategoryHeader(
        cat,
        grouped[cat]!.length,
        isExpanded: isExpanded,
        onTap: () => setState(() {
          if (_expandedCategories.contains(cat)) {
            _expandedCategories.remove(cat);
          } else {
            _expandedCategories.add(cat);
          }
        }),
      ));
      if (isExpanded) {
        for (final ing in grouped[cat]!) {
          listItems.add(_buildIngredientTile(ing));
        }
      }
    }

    return Column(
      children: [
        _buildWarehouseSelector(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            style: TextStyle(color: AppTheme.text),
            decoration: InputDecoration(
              hintText: tr('Mahsulot nomini qidiring...'),
              hintStyle: TextStyle(color: AppTheme.textSoft),
              prefixIcon: Icon(Icons.search, color: AppTheme.accent),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, color: AppTheme.textSoft),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: AppTheme.card,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.textSoft)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.accent)),
            ),
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    _searchQuery.isEmpty ? tr('Sklad bo\'sh') : tr('Natija topilmadi'),
                    style: TextStyle(color: AppTheme.textSoft),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: listItems,
                ),
        ),
      ],
    );
  }

  Widget _buildCategoryHeader(String category, int count, {required bool isExpanded, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isExpanded
                ? AppTheme.accent.withValues(alpha: 0.5)
                : AppTheme.accent.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 20,
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                category,
                style: TextStyle(color: AppTheme.text, fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
            Text('($count)', style: TextStyle(color: AppTheme.textSoft, fontSize: 13)),
            const SizedBox(width: 8),
            Icon(
              isExpanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
              color: AppTheme.accent,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  static const _retailCategories = ['Продукция', 'Десерт', 'Холодные напитки'];

  Widget _buildIngredientTile(Map<String, dynamic> ing) {
    final stock = double.tryParse(ing['stock_quantity'].toString()) ?? 0;
    final min = double.tryParse(ing['min_quantity'].toString()) ?? 0;
    final price = double.tryParse(ing['price_per_unit'].toString()) ?? 0;
    final isLow = min > 0 && stock <= min;
    final category = ing['category'] as String? ?? '';
    final isRetail = _retailCategories.contains(category);
    final sellingPrice = double.tryParse(ing['selling_price']?.toString() ?? '0') ?? 0;
    final profit = sellingPrice - price;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isLow ? Colors.red : Colors.transparent),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.inventory, color: isLow ? Colors.red : AppTheme.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ing['name'], style: TextStyle(color: isLow ? Colors.red : AppTheme.text, fontSize: 15, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text('Min: $min ${ing['unit']}', style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
                if (isRetail) ...[
                  Text('${tr('Kirim')}: ${price.toStringAsFixed(0)} ${tr('so\'m')}', style: TextStyle(color: Colors.blue, fontSize: 12)),
                  Text('${tr('Sotish')}: ${sellingPrice.toStringAsFixed(0)} ${tr('so\'m')}', style: TextStyle(color: Colors.orange, fontSize: 12)),
                  if (sellingPrice > 0)
                    Text(
                      '${tr('Foyda')}: ${profit.toStringAsFixed(0)} ${tr('so\'m')}',
                      style: TextStyle(color: profit >= 0 ? Colors.green : Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                ] else
                  Text('${tr('Narx')}: ${price.toStringAsFixed(0)} ${tr('so\'m')}/${ing['unit']}', style: TextStyle(color: Colors.blue, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$stock ${ing['unit']}', style: TextStyle(color: isLow ? Colors.red : Colors.green, fontWeight: FontWeight.bold, fontSize: 15)),
              if (isLow) Text(tr('KAM QOLDI!'), style: TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // П/Ф — "Tayyorlash" (ishlab chiqarish): P/F +N, xom masaliqlar -retsept
                  if (category == 'П/Ф') ...[
                    GestureDetector(
                      onTap: () => _showProducePfDialog(ing),
                      child: Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(tr('Tayyorlash'), style: const TextStyle(color: Colors.purple, fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  GestureDetector(
                    onTap: () => _showIncomingDialog(ing),
                    child: Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(tr('+ Kirim'), style: TextStyle(color: Colors.green, fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _showEditIngredientDialog(ing),
                    child: Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.edit, color: AppTheme.accent, size: 16),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _showStockHistoryDialog(ing),
                    child: Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.textSoft.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.history, color: AppTheme.textSoft, size: 16),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _confirmMergeIngredient(ing),
                    child: Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.call_merge, color: Colors.orange, size: 16),
                    ),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _confirmDeleteIngredient(ing),
                    child: Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.delete_outline, color: Colors.red, size: 16),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _confirmDeleteIngredient(Map<String, dynamic> ing) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('O\'chirishni tasdiqlang'), style: TextStyle(color: AppTheme.text)),
        content: Text(
          '"${ing['name']}" ${tr('mahsulotini o\'chirmoqchimisiz?')}\n\n${tr('Faqat ombor bo\'sh (0) bo\'lsa o\'chiriladi.')}',
          style: TextStyle(color: AppTheme.textSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context);
              try {
                final result = await ApiService.delete('${AppConstants.stock}/${ing['id']}');
                if (context.mounted) {
                  final msg = result is Map ? result['message'] ?? tr('O\'chirildi!') : tr('O\'chirildi!');
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(msg), backgroundColor: Colors.red),
                  );
                }
                _loadData();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: Text(tr('O\'chirish'), style: TextStyle(color: AppTheme.text)),
          ),
        ],
      ),
    );
  }

  // DUBLIKATNI BIRLASHTIRISH (merge): "ing" ni boshqa mahsulot ichiga qo'shish.
  // Ishlatilayotgan dublikatni o'chirib bo'lmaydi — shu yo'l bilan tozalanadi.
  void _confirmMergeIngredient(Map<String, dynamic> ing) {
    final targets = _ingredients.where((x) => x['id'] != ing['id']).toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Birlashtirish uchun boshqa mahsulot yo\'q'))));
      return;
    }
    final searchC = TextEditingController();
    showDialog(
      context: context,
      builder: (dctx) => StatefulBuilder(builder: (dctx, setSt) {
        final q = searchC.text.trim().toLowerCase();
        final shown = q.isEmpty ? targets : targets.where((x) => (x['name']?.toString() ?? '').toLowerCase().contains(q)).toList();
        return AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text('«${ing['name']}» — ${tr('birlashtirish')}', style: TextStyle(color: AppTheme.text, fontSize: 15)),
          content: SizedBox(
            width: 360,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(tr('Qaysi mahsulot ichiga qo\'shilsin? Retseptlar o\'shanga o\'tadi, qoldiq qo\'shiladi (minus saqlanadi), bu yozuv o\'chadi.'),
                  style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
              const SizedBox(height: 10),
              TextField(
                controller: searchC,
                onChanged: (_) => setSt(() {}),
                style: TextStyle(color: AppTheme.text),
                decoration: InputDecoration(
                  hintText: tr('Qidirish...'),
                  hintStyle: TextStyle(color: AppTheme.textSoft),
                  prefixIcon: Icon(Icons.search, size: 18, color: AppTheme.textSoft),
                  isDense: true,
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.accent)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 280,
                child: shown.isEmpty
                    ? Center(child: Text(tr('Natija topilmadi'), style: TextStyle(color: AppTheme.textSoft)))
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (_, i) {
                          final t = shown[i] as Map<String, dynamic>;
                          return ListTile(
                            dense: true,
                            title: Text(t['name']?.toString() ?? '', style: TextStyle(color: AppTheme.text, fontSize: 13)),
                            subtitle: Text('${tr('Qoldiq')}: ${t['stock_quantity']}', style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
                            trailing: Icon(Icons.call_merge, color: Colors.orange, size: 18),
                            onTap: () { Navigator.pop(dctx); _doMerge(ing, t); },
                          );
                        },
                      ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
          ],
        );
      }),
    );
  }

  Future<void> _doMerge(Map<String, dynamic> src, Map<String, dynamic> target) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (cctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('Tasdiqlang'), style: TextStyle(color: AppTheme.text)),
        content: Text('«${src['name']}» → «${target['name']}»\n\n${tr('Birlashtirilsinmi? Ortga qaytarib bo\'lmaydi.')}',
            style: TextStyle(color: AppTheme.textSoft)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(cctx, false), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(cctx, true),
            child: Text(tr('Birlashtirish'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final res = await ApiService.post('${AppConstants.stock}/${src['id']}/merge', {'target_id': target['id']});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text((res is Map ? res['message'] : null)?.toString() ?? tr('Birlashtirildi')),
          backgroundColor: Colors.green));
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // P/F TAYYORLASH — oshpaz necha birlik tayyorlaganini kiritadi:
  // P/F qoldig'i +N, retseptidagi xom masaliqlar -N*brutto (backend hisoblaydi)
  void _showProducePfDialog(Map<String, dynamic> ing) {
    final qtyC = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text('${ing['name']} — ${tr('Tayyorlash')}',
            style: TextStyle(color: AppTheme.text, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('Qancha tayyorlandi? Xom masaliqlar retsept bo\'yicha skladdan ayriladi.'),
                style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: qtyC,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: TextStyle(color: AppTheme.text),
              decoration: InputDecoration(
                labelText: '${tr('Miqdori')} (${ing['unit']})',
                labelStyle: TextStyle(color: AppTheme.textSoft),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.purple)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
            onPressed: () async {
              final qty = double.tryParse(qtyC.text.trim().replaceAll(',', '.')) ?? 0;
              if (qty <= 0) return;
              final nav = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              try {
                final res = await ApiService.post('${AppConstants.stock}/produce', {
                  'ingredient_id': ing['id'],
                  'quantity': qty,
                }, idempotencyKey: ApiService.newIdempotencyKey());
                nav.pop();
                if (res is Map && res['ok'] == true) {
                  messenger.showSnackBar(SnackBar(
                      content: Text('${ing['name']}: +$qty ${ing['unit']}'),
                      backgroundColor: Colors.green));
                  _loadData();
                } else {
                  messenger.showSnackBar(SnackBar(
                      content: Text((res is Map ? res['message'] : null)?.toString() ?? tr('Xato')),
                      backgroundColor: Colors.red));
                }
              } catch (e) {
                messenger.showSnackBar(
                    SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
              }
            },
            child: Text(tr('Tayyorlash'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // Sklad mahsulotini TAHRIRLASH — sabab majburiy, tarixga yoziladi
  void _showEditIngredientDialog(Map<String, dynamic> ing) {
    final category = ing['category'] as String? ?? '';
    final isRetail = _retailCategories.contains(category);
    final nameC = TextEditingController(text: ing['name']?.toString() ?? '');
    final unitC = TextEditingController(text: ing['unit']?.toString() ?? '');
    final minC = TextEditingController(
        text: (double.tryParse(ing['min_quantity'].toString()) ?? 0).toString());
    final priceC = TextEditingController(
        text: (double.tryParse(ing['price_per_unit'].toString()) ?? 0).toStringAsFixed(0));
    final sellC = TextEditingController(
        text: (double.tryParse(ing['selling_price']?.toString() ?? '0') ?? 0).toStringAsFixed(0));
    final stockC = TextEditingController(
        text: (double.tryParse(ing['stock_quantity'].toString()) ?? 0).toString());
    final reasonC = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text('${ing['name']} — ${tr('Mahsulotni tahrirlash')}',
            style: TextStyle(color: AppTheme.text, fontSize: 16)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTextField(nameC, tr('Nomi'), Icons.label_outline),
              const SizedBox(height: 10),
              _buildTextField(unitC, tr('Birlik'), Icons.straighten),
              const SizedBox(height: 10),
              _buildTextField(minC, tr('Minimal miqdor'), Icons.warning_amber, isNumber: true),
              const SizedBox(height: 10),
              _buildTextField(priceC, tr('Kirim narxi'), Icons.monetization_on, isNumber: true),
              if (isRetail) ...[
                const SizedBox(height: 10),
                _buildTextField(sellC, tr('Sotish narxi'), Icons.sell, isNumber: true),
              ],
              const SizedBox(height: 10),
              _buildTextField(stockC, tr('Qoldiq (tuzatish)'), Icons.inventory_2, isNumber: true),
              const SizedBox(height: 14),
              // --- SABAB (majburiy) ---
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.edit_note, color: Colors.orange, size: 18),
                      const SizedBox(width: 6),
                      Text(tr('Sabab (majburiy)'),
                          style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 13)),
                    ]),
                    const SizedBox(height: 8),
                    TextField(
                      controller: reasonC,
                      style: TextStyle(color: AppTheme.text),
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: tr('Nima uchun o\'zgartiryapsiz?'),
                        hintStyle: TextStyle(color: AppTheme.textSoft, fontSize: 13),
                        filled: true,
                        fillColor: AppTheme.bg,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
            onPressed: () async {
              final reason = reasonC.text.trim();
              final nav = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);
              if (reason.isEmpty) {
                messenger.showSnackBar(
                  SnackBar(content: Text(tr('Sabab yozish shart!')), backgroundColor: Colors.orange),
                );
                return;
              }
              try {
                final res = await ApiService.put('${AppConstants.stock}/${ing['id']}/edit', {
                  'name': nameC.text.trim(),
                  'unit': unitC.text.trim(),
                  'min_quantity': minC.text.trim(),
                  'price_per_unit': priceC.text.trim(),
                  if (isRetail) 'selling_price': sellC.text.trim(),
                  'stock_quantity': stockC.text.trim(),
                  'reason': reason,
                });
                nav.pop();
                final msg = res is Map ? (res['message'] ?? tr('O\'zgartirildi!')) : tr('O\'zgartirildi!');
                messenger.showSnackBar(
                  SnackBar(content: Text(msg.toString()), backgroundColor: Colors.green),
                );
                _loadData();
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red),
                );
              }
            },
            child: Text(tr('Saqlash'), style: TextStyle(color: AppTheme.text)),
          ),
        ],
      ),
    );
  }

  // Mahsulot o'zgarishlar tarixi (kim / nima / nega)
  void _showStockHistoryDialog(Map<String, dynamic> ing) async {
    List<dynamic> history = [];
    try {
      final res = await ApiService.get('${AppConstants.stock}/${ing['id']}/history');
      history = res is List ? res : [];
    } catch (_) {}
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text('${ing['name']} — ${tr('O\'zgarishlar tarixi')}',
            style: TextStyle(color: AppTheme.text, fontSize: 16)),
        content: SizedBox(
          width: 440,
          child: history.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(tr('Tarix bo\'sh'), style: TextStyle(color: AppTheme.textSoft)),
                )
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: history.map((h) {
                      final ts = (h['created_at']?.toString() ?? '').replaceFirst('T', ' ');
                      final when = ts.length >= 16 ? ts.substring(0, 16) : ts;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.bg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(Icons.person, size: 13, color: AppTheme.textSoft),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text('${h['user_name'] ?? '—'}  •  $when',
                                    style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
                              ),
                            ]),
                            const SizedBox(height: 4),
                            Text(h['changes']?.toString() ?? '',
                                style: TextStyle(color: AppTheme.text, fontSize: 13)),
                            const SizedBox(height: 4),
                            Text('${tr('Sabab')}: ${h['reason'] ?? ''}',
                                style: const TextStyle(
                                    color: Colors.orange, fontSize: 12, fontStyle: FontStyle.italic)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
  }

  Widget _incToggleBox(String label, bool sel) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: sel ? AppTheme.accent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: sel ? AppTheme.accent : AppTheme.border),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(color: sel ? AppTheme.accent : AppTheme.textSoft, fontWeight: sel ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
      );

  void _showIncomingDialog(Map<String, dynamic> ingredient) {
    final quantityController = TextEditingController();
    final priceController = TextEditingController();
    final sellingPriceController = TextEditingController(
      text: ingredient['selling_price'] != null &&
              ingredient['selling_price'].toString() != '0'
          ? ingredient['selling_price'].toString()
          : '',
    );
    final noteController = TextEditingController();
    final sourceController = TextEditingController();
    String method = 'cash';
    bool fromKassa = true;
    bool saving = false; // kirim yuborilmoqda — ikki marta bosishdan himoya
    final existingSellingPrice =
        double.tryParse(ingredient['selling_price']?.toString() ?? '0') ?? 0;
    bool isSotuvga = existingSellingPrice > 0;
    int? selectedCategoryId =
        _categories.isNotEmpty ? _categories[0]['id'] as int : null;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text('${ingredient['name']} — ${tr('kirim')}',
              style: TextStyle(color: AppTheme.text)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTextField(
                  quantityController,
                  '${tr('Miqdori')} (${ingredient['unit']})',
                  Icons.numbers,
                  isNumber: true,
                ),
                const SizedBox(height: 12),
                _buildTextField(
                  priceController,
                  '${tr('Kirish narxi')} (${tr('so\'m')}/${ingredient['unit']})',
                  Icons.monetization_on,
                  isNumber: true,
                  onTap: () => priceController.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: priceController.text.length),
                ),
                const SizedBox(height: 16),
                // ---- Ishlatilish maqsadi ----
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppTheme.accent.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('Bu mahsulot qanday ishlatiladi?'),
                        style: TextStyle(
                            color: AppTheme.text,
                            fontSize: 13,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      RadioListTile<bool>(
                        value: false,
                        groupValue: isSotuvga,
                        activeColor: AppTheme.accent,
                        contentPadding: EdgeInsets.zero,
                        title: Text(tr('Oshxona uchun ingredient'),
                            style: TextStyle(color: AppTheme.text, fontSize: 13)),
                        subtitle: Text(tr('Retseptlarda ishlatiladi'),
                            style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
                        onChanged: (v) =>
                            setStateDialog(() => isSotuvga = v ?? false),
                      ),
                      RadioListTile<bool>(
                        value: true,
                        groupValue: isSotuvga,
                        activeColor: AppTheme.accent,
                        contentPadding: EdgeInsets.zero,
                        title: Text(tr('Sotuvga chiqarish'),
                            style: TextStyle(color: AppTheme.text, fontSize: 13)),
                        subtitle: Text(tr('To\'g\'ridan mijozga sotiladi'),
                            style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
                        onChanged: (v) =>
                            setStateDialog(() => isSotuvga = v ?? false),
                      ),
                    ],
                  ),
                ),
                if (isSotuvga) ...[
                  const SizedBox(height: 12),
                  _buildTextField(
                    sellingPriceController,
                    tr('Sotish narxi (so\'m)'),
                    Icons.sell,
                    isNumber: true,
                    onTap: () => sellingPriceController.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: sellingPriceController.text.length),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: selectedCategoryId,
                    dropdownColor: AppTheme.card,
                    style: TextStyle(color: AppTheme.text),
                    decoration: _inputDecoration(tr('Menyu kategoriyasi'), Icons.category),
                    items: _categories.map((c) => DropdownMenuItem<int>(
                      value: c['id'] as int,
                      child: Text(c['name'] as String,
                          style: TextStyle(color: AppTheme.text)),
                    )).toList(),
                    onChanged: (v) =>
                        setStateDialog(() => selectedCategoryId = v),
                  ),
                ],
                const SizedBox(height: 12),
                _buildTextField(noteController, tr('Izoh (ixtiyoriy)'), Icons.note),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: GestureDetector(
                    onTap: () => setStateDialog(() => method = 'cash'),
                    child: _incToggleBox(tr('Naqd'), method == 'cash'),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: GestureDetector(
                    onTap: () => setStateDialog(() => method = 'card'),
                    child: _incToggleBox(tr('Karta'), method == 'card'),
                  )),
                ]),
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: Text(tr('Pul manbasi'), style: TextStyle(color: AppTheme.textSoft, fontSize: 12))),
                const SizedBox(height: 4),
                Row(children: [
                  Expanded(child: GestureDetector(
                    onTap: () => setStateDialog(() => fromKassa = true),
                    child: _incToggleBox(tr('Kassadan'), fromKassa),
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: GestureDetector(
                    onTap: () => setStateDialog(() => fromKassa = false),
                    child: _incToggleBox(tr('Boshqa joydan'), !fromKassa),
                  )),
                ]),
                if (!fromKassa) ...[
                  const SizedBox(height: 8),
                  _buildTextField(sourceController, tr('Qayerdan'), Icons.account_balance_wallet),
                  const SizedBox(height: 2),
                  Align(alignment: Alignment.centerLeft, child: Text(tr('Kassadan pul yechilmaydi'), style: const TextStyle(color: Colors.teal, fontSize: 11))),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: saving ? null : () async {
                if (quantityController.text.isEmpty ||
                    priceController.text.isEmpty) return;
                final qty = double.tryParse(quantityController.text) ?? 0;
                final price = double.tryParse(priceController.text) ?? 0;
                final total = qty * price;
                final sellingPrice = isSotuvga
                    ? (double.tryParse(sellingPriceController.text) ?? 0)
                    : 0.0;

                setStateDialog(() => saving = true);
                try {
                  // Idempotency-Key — kirim (kassa chiqimi) retry'da ikki marta yozilmasligi uchun
                  await ApiService.post(AppConstants.stockIncoming, {
                    'ingredient_id': ingredient['id'],
                    'quantity': qty,
                    'price_per_unit': price,
                    'note': noteController.text,
                    'selling_price': sellingPrice,
                    'method': method,
                    'from_kassa': fromKassa,
                    'source': fromKassa ? null : (sourceController.text.trim().isEmpty ? null : sourceController.text.trim()),
                  }, idempotencyKey: ApiService.newIdempotencyKey());

                  if (isSotuvga && selectedCategoryId != null && sellingPrice > 0) {
                    try {
                      await ApiService.postWithImage(
                        AppConstants.menuItems,
                        name: ingredient['name'] as String,
                        price: sellingPrice,
                        categoryId: selectedCategoryId,
                        type: 'product',
                        ingredientId: ingredient['id'] as int,
                      );
                    } catch (_) {}
                  }

                  if (context.mounted) Navigator.pop(context);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            '${tr('Qabul qilindi! Jami:')} ${total.toStringAsFixed(0)} ${tr('so\'m')}'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                  _loadData();
                } finally {
                  if (context.mounted) setStateDialog(() => saving = false);
                }
              },
              child:
                  Text(tr('Qabul qilish'), style: TextStyle(color: AppTheme.onAccent)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lowStock = _ingredients.where((i) {
      final stock = double.tryParse(i['stock_quantity'].toString()) ?? 0;
      final min = double.tryParse(i['min_quantity'].toString()) ?? 0;
      return min > 0 && stock <= min;
    }).toList();

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.card,
        automaticallyImplyLeading: false,
        title: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.accent,
          labelColor: AppTheme.accent,
          unselectedLabelColor: AppTheme.textSoft,
          tabs: [
            Tab(text: tr('Kategoriyalar')),
            Tab(text: tr('Taomlar')),
            Tab(text: tr('Sklad')),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.print, color: AppTheme.accent),
            tooltip: tr('Bo\'limlar / Printerlar'),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PrintStationsScreen()),
              );
              _loadData();
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : Column(
        children: [
          if (lowStock.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.red.withOpacity(0.2),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${tr('Kam qoldi')}: ${lowStock.map((i) => '${i['name']} (${i['stock_quantity']} ${i['unit']})').join(', ')}',
                      style: TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Kategoriyalar
                Builder(builder: (context) {
                  final catQuery = _catSearchQuery.toLowerCase();
                  final isSearching = _catSearchQuery.isNotEmpty;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: TextField(
                          controller: _catSearchController,
                          style: TextStyle(color: AppTheme.text),
                          decoration: InputDecoration(
                            hintText: tr('Taom nomini qidiring...'),
                            hintStyle: TextStyle(color: AppTheme.textSoft),
                            prefixIcon: Icon(Icons.search, color: AppTheme.accent),
                            suffixIcon: _catSearchQuery.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.clear, color: AppTheme.textSoft),
                                    onPressed: () {
                                      _catSearchController.clear();
                                      setState(() => _catSearchQuery = '');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: AppTheme.card,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.textSoft)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.accent)),
                          ),
                          onChanged: (v) => setState(() => _catSearchQuery = v),
                        ),
                      ),
                      Expanded(
                        child: _categories.isEmpty
                            ? Center(child: Text(tr('Kategoriyalar yo\'q'), style: TextStyle(color: AppTheme.textSoft)))
                            : ListView(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                children: _categories.map((cat) {
                                  final catId = cat['id'].toString();
                                  final catName = cat['name'].toString();
                                  final allCatItems = _items
                                      .where((item) => item['category_id'].toString() == catId)
                                      .toList();
                                  final catItems = isSearching
                                      ? allCatItems.where((item) => item['name']
                                          .toString()
                                          .toLowerCase()
                                          .contains(catQuery))
                                          .toList()
                                      : allCatItems;
                                  if (isSearching && catItems.isEmpty) return const SizedBox.shrink();
                                  final isExpanded = isSearching || _expandedCategories.contains(catId);
                    return Column(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.card,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => setState(() {
                              if (isExpanded) {
                                _expandedCategories.remove(catId);
                              } else {
                                _expandedCategories.add(catId);
                              }
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  Icon(Icons.category, color: AppTheme.accent),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      '$catName (${catItems.length})',
                                      style: TextStyle(
                                        color: AppTheme.text,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.edit, color: Colors.blue, size: 20),
                                    tooltip: tr('Tahrirlash'),
                                    onPressed: () => _showEditCategoryDialog(cat),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                    tooltip: tr('O\'chirish'),
                                    onPressed: () => _confirmDeleteCategory(cat),
                                  ),
                                  Icon(
                                    isExpanded ? Icons.expand_more : Icons.chevron_right,
                                    color: AppTheme.accent,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (isExpanded)
                          ...catItems.map((item) => Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                decoration: BoxDecoration(
                                  color: AppTheme.accentSoft,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: ListTile(
                                  leading: item['image_url'] != null
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.network(
                                            '${AppConstants.imageBase}${item['image_url']}',
                                            width: 46,
                                            height: 46,
                                            fit: BoxFit.cover,
                                            errorBuilder: (c, e, s) => Icon(
                                                Icons.restaurant,
                                                color: AppTheme.accent,
                                                size: 36),
                                          ),
                                        )
                                      : Icon(Icons.restaurant,
                                          color: AppTheme.accent, size: 36),
                                  title: Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          item['name'].toString(),
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              color: item['available'] == false
                                                  ? AppTheme.textSoft
                                                  : AppTheme.text,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      if (item['available'] == false) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.red.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: const Text('СТОП',
                                              style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ],
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        "${item['price']} ${tr('so\'m')}",
                                        style: TextStyle(
                                            color: AppTheme.accent,
                                            fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: () => _toggleAvailable(item),
                                        child: Icon(
                                            item['available'] == false ? Icons.block : Icons.check_circle,
                                            color: item['available'] == false ? Colors.red : Colors.green,
                                            size: 20),
                                      ),
                                      const SizedBox(width: 8),
                                      // Kunlik kuzat (somsa kabi): yoqilsa binafsha
                                      GestureDetector(
                                        onTap: () => _toggleDailyTrack(item),
                                        child: Icon(
                                            item['daily_tracked'] == true ? Icons.event_available : Icons.event_note,
                                            color: item['daily_tracked'] == true ? Colors.purple : AppTheme.textSoft,
                                            size: 20),
                                      ),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: () => _showEditItemDialog(item),
                                        child: Icon(Icons.edit,
                                            color: Colors.blue, size: 18),
                                      ),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: () => _confirmDeleteMenuItem(item),
                                        child: Icon(Icons.delete_outline,
                                            color: Colors.red, size: 18),
                                      ),
                                    ],
                                  ),
                                ),
                              )),
                        const SizedBox(height: 8),
                      ],
                    );
                                }).toList(),
                              ),
                      ),
                    ],
                  );
                }),
                // Taomlar
                Builder(builder: (context) {
                  final searchActive = _itemSearchQuery.isNotEmpty;
                  final filteredItems = searchActive
                      ? _items.where((item) => item['name']
                          .toString()
                          .toLowerCase()
                          .contains(_itemSearchQuery.toLowerCase()))
                          .toList()
                      : _items;

                  final Map<String, List<dynamic>> grouped = {};
                  for (final item in filteredItems) {
                    final cat = (item['category_name'] as String?) ?? 'Boshqalar';
                    grouped.putIfAbsent(cat, () => []).add(item);
                  }

                  final List<Widget> listItems = [];
                  for (final cat in grouped.keys) {
                    final isExpanded = searchActive || _expandedMenuCategories.contains(cat);
                    listItems.add(_buildCategoryHeader(
                      cat,
                      grouped[cat]!.length,
                      isExpanded: isExpanded,
                      onTap: () => setState(() {
                        if (_expandedMenuCategories.contains(cat)) {
                          _expandedMenuCategories.remove(cat);
                        } else {
                          _expandedMenuCategories.add(cat);
                        }
                      }),
                    ));
                    if (isExpanded) {
                      for (final item in grouped[cat]!) {
                        listItems.add(_buildDishCard(item));
                      }
                    }
                  }

                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: TextField(
                          controller: _itemSearchController,
                          style: TextStyle(color: AppTheme.text),
                          decoration: InputDecoration(
                            hintText: tr('Taom nomini qidiring...'),
                            hintStyle: TextStyle(color: AppTheme.textSoft),
                            prefixIcon: Icon(Icons.search, color: AppTheme.accent),
                            suffixIcon: _itemSearchQuery.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.clear, color: AppTheme.textSoft),
                                    onPressed: () {
                                      _itemSearchController.clear();
                                      setState(() => _itemSearchQuery = '');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: AppTheme.card,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.textSoft)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.accent)),
                          ),
                          onChanged: (v) => setState(() => _itemSearchQuery = v),
                        ),
                      ),
                      Expanded(
                        child: filteredItems.isEmpty
                            ? Center(
                                child: Text(
                                  _items.isEmpty ? tr('Taomlar yo\'q') : tr('Natija topilmadi'),
                                  style: TextStyle(color: AppTheme.textSoft),
                                ),
                              )
                            : ListView(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                children: listItems,
                              ),
                      ),
                    ],
                  );
                }),
                // Sklad
                _buildSkaldTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.accent,
        onPressed: () {
          final tab = _tabController.index;
          if (tab == 0) _showAddCategoryDialog();
          if (tab == 1) _showAddItemDialog();
          if (tab == 2) _showAddIngredientDialog();
        },
        child: Icon(Icons.add, color: AppTheme.text),
      ),
    );
  }
}

// ===== XODIMLAR BO'LIMI =====
class StaffSection extends StatefulWidget {
  const StaffSection({super.key});

  @override
  State<StaffSection> createState() => _StaffSectionState();
}

class _StaffSectionState extends State<StaffSection> {
  List<dynamic> _users = [];
  bool _isLoading = true;

  // Lavozimlar (rollar) — backenddan yuklanadi, admin yangi qo'sha oladi
  List<Map<String, dynamic>> _roles = [];

  final List<Map<String, dynamic>> _salaryTypes = [
    {'value': 'monthly', 'label': tr('Oylik (belgilangan summa)')},
    {'value': 'daily', 'label': tr('Kunlik')},
    {'value': 'hourly', 'label': tr('Soatlik')},
    {'value': 'percent', 'label': tr('Savdodan foiz (%)')},
    {'value': 'percent_total', 'label': tr('Jami tushumdan foiz (%)')},
    {'value': 'piece', 'label': tr('Dona uchun (sdelnaya)')},
  ];

  @override
  void initState() {
    super.initState();
    _loadRoles();
    _loadUsers();
  }

  // Xodimni Hikvision qurilmasiga qo'shish (Employee No = Face ID raqami). Yuz keyin qurilmada olinadi.
  Future<void> _enrollToDevice(String faceId, String name) async {
    final messenger = ScaffoldMessenger.of(context);
    if (faceId.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(tr('Avval Face ID raqamini kiriting!')), backgroundColor: Colors.red),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text(tr('Qurilmaga yuborilmoqda...')), duration: const Duration(seconds: 1)),
    );
    try {
      final res = await ApiService.post(AppConstants.hikvisionEnroll, {'employeeNo': faceId, 'name': name});
      final ok = res is Map && res['ok'] == true;
      final msg = res is Map ? (res['message']?.toString() ?? '') : tr('Xato');
      messenger.showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: ok ? Colors.green : Colors.red,
        duration: const Duration(seconds: 5),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _loadRoles() async {
    try {
      final data = await ApiService.get(AppConstants.roles);
      if (data is List) {
        setState(() => _roles = data.map((r) => {'id': r['id'], 'name': r['name']}).toList());
      }
    } catch (_) {}
  }

  // Yangi lavozim qo'shish (masalan: elektrik) — qo'shgach uni tanlaydi
  Future<void> _promptNewRole(void Function(int) onCreated) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('Yangi lavozim'), style: TextStyle(color: AppTheme.text)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: AppTheme.text),
          decoration: _inputDecoration(tr('Lavozim nomi (masalan: elektrik)'), Icons.work),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Qo\'shish'), style: TextStyle(color: AppTheme.text)),
          ),
        ],
      ),
    );
    if (ok != true || ctrl.text.trim().isEmpty) return;
    try {
      final res = await ApiService.post(AppConstants.roles, {'name': ctrl.text.trim()});
      await _loadRoles();
      if (res is Map && res['id'] != null) onCreated(res['id'] as int);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.get(AppConstants.users);
      setState(() => _users = data is List ? data : []);
    } catch (e) {
      debugPrint('Xato: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: AppTheme.textSoft),
      prefixIcon: Icon(icon, color: AppTheme.accent),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.textSoft)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.accent)),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {bool isPassword = false, bool isNumber = false}) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: TextStyle(color: AppTheme.text),
      decoration: _inputDecoration(label, icon),
    );
  }

  // Vaqt tanlash maydoni (HH:MM) — ish boshlanishi/tugashi uchun
  Widget _buildTimeField(BuildContext ctx, String label, String value, ValueChanged<String> onPicked) {
    return InkWell(
      onTap: () async {
        final parts = value.split(':');
        final initial = TimeOfDay(
          hour: int.tryParse(parts.isNotEmpty ? parts[0] : '9') ?? 9,
          minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
        );
        final picked = await showTimePicker(
          context: ctx,
          initialTime: initial,
          builder: (c, w) => Theme(
            data: ThemeData.dark().copyWith(
              colorScheme: ColorScheme.dark(primary: AppTheme.accent),
            ),
            child: w!,
          ),
        );
        if (picked != null) {
          final hh = picked.hour.toString().padLeft(2, '0');
          final mm = picked.minute.toString().padLeft(2, '0');
          onPicked('$hh:$mm');
        }
      },
      child: InputDecorator(
        decoration: _inputDecoration(label, Icons.access_time),
        child: Text(value, style: TextStyle(color: AppTheme.text)),
      ),
    );
  }

  void _showAddUserDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final passwordController = TextEditingController();
    final salaryController = TextEditingController();
    final percentController = TextEditingController();
    final tierThresholdController = TextEditingController(); // progressiv: kunlik chegara
    final tierValueController = TextEditingController();     // progressiv: oshgan foiz
    final faceIdController = TextEditingController();
    final lateFineController = TextEditingController(text: '0');
    final salaryDayController = TextEditingController(text: '1');
    final salaryPeriodController = TextEditingController(text: '30');
    int? selectedRoleId = _roles.isEmpty
        ? null
        : (_roles.firstWhere((r) => r['name'] == 'waiter', orElse: () => _roles.first)['id'] as int);
    String selectedSalaryType = 'monthly';
    String workStart = '09:00';
    String workEnd = '22:00';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text(tr('Xodim qo\'shish'), style: TextStyle(color: AppTheme.text)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTextField(nameController, tr('Ism familiya'), Icons.person),
                const SizedBox(height: 12),
                _buildTextField(phoneController, tr('Telefon raqam'), Icons.phone),
                const SizedBox(height: 12),
                _buildTextField(passwordController, tr('Parol'), Icons.lock, isPassword: true),
                const SizedBox(height: 12),
                _buildTextField(faceIdController, tr('Face ID raqami'), Icons.face),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _enrollToDevice(faceIdController.text.trim(), nameController.text.trim()),
                    icon: Icon(Icons.sensor_occupied, size: 18, color: AppTheme.accent),
                    label: Text(tr('Qurilmaga qo\'shish (Face ID)'), style: TextStyle(color: AppTheme.accent)),
                    style: OutlinedButton.styleFrom(side: BorderSide(color: AppTheme.border)),
                  ),
                ),
                const SizedBox(height: 4),
                Text(tr('* Face ID — xodimning kirish/chiqish kartasi raqami'), style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: selectedRoleId,
                  dropdownColor: AppTheme.card,
                  style: TextStyle(color: AppTheme.text),
                  decoration: _inputDecoration(tr('Lavozim'), Icons.work),
                  items: [
                    ..._roles.map((r) => DropdownMenuItem<int>(
                      value: r['id'] as int,
                      child: Text(_getRoleLabel(r['name']?.toString() ?? ''), style: TextStyle(color: AppTheme.text)),
                    )),
                    DropdownMenuItem<int>(
                      value: -1,
                      child: Text(tr('＋ Yangi lavozim...'), style: TextStyle(color: AppTheme.accent)),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == -1) {
                      _promptNewRole((id) => setStateDialog(() => selectedRoleId = id));
                    } else {
                      setStateDialog(() => selectedRoleId = v);
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedSalaryType,
                  dropdownColor: AppTheme.card,
                  style: TextStyle(color: AppTheme.text),
                  decoration: _inputDecoration(tr('Maosh turi'), Icons.attach_money),
                  items: _salaryTypes.map((s) => DropdownMenuItem<String>(
                    value: s['value'],
                    child: Text(s['label'], style: TextStyle(color: AppTheme.text, fontSize: 13)),
                  )).toList(),
                  onChanged: (v) => setStateDialog(() => selectedSalaryType = v!),
                ),
                const SizedBox(height: 12),
                if (selectedSalaryType.startsWith('percent')) ...[
                  _buildTextField(percentController, tr('Foiz miqdori (%)'), Icons.percent, isNumber: true),
                  const SizedBox(height: 4),
                  Text(tr('* Masalan: 10 — har 100 000 so\'m savdodan 10 000 so\'m oladi'), style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
                ] else ...[
                  _buildTextField(salaryController, tr('Maosh miqdori (so\'m)'), Icons.monetization_on, isNumber: true),
                ],
                if (selectedSalaryType == 'percent') ...[
                  const SizedBox(height: 10),
                  Text(tr('Progressiv (ixtiyoriy): kunlik savdo chegaradan oshsa — oshgan foiz ishlaydi'),
                      style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: _buildTextField(tierThresholdController, tr('Kunlik chegara (so\'m)'), Icons.trending_up, isNumber: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTextField(tierValueController, tr('Oshgan foiz (%)'), Icons.percent, isNumber: true)),
                  ]),
                ],
                if (selectedSalaryType == 'piece') ...[
                  const SizedBox(height: 8),
                  Text(tr('* Dona stavkalarni xodimni saqlagach — tahrirlashda "Dona stavkalar" tugmasidan qo\'shasiz'),
                      style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
                ],
                const SizedBox(height: 12),
                // Ish vaqti (smena)
                Row(
                  children: [
                    Expanded(
                      child: _buildTimeField(context, tr('Ish boshlanishi'), workStart,
                          (v) => setStateDialog(() => workStart = v)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildTimeField(context, tr('Ish tugashi'), workEnd,
                          (v) => setStateDialog(() => workEnd = v)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildTextField(lateFineController, tr('Kechikish jarimasi (so\'m / daqiqa)'), Icons.money_off, isNumber: true),
                const SizedBox(height: 4),
                Text(tr('* 1 daqiqa kech qolsa shu summa jarima yoziladi'), style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
                const SizedBox(height: 12),
                _buildTextField(salaryPeriodController, tr('Necha kunda oylik (kun)'), Icons.event_repeat, isNumber: true),
                const SizedBox(height: 4),
                Text(tr('* Masalan: 30 = oylik, 10 = har 10 kunda'), style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
              onPressed: () async {
                if (nameController.text.isEmpty || phoneController.text.isEmpty || passwordController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(tr('Ism, telefon va parolni to\'ldiring!')), backgroundColor: Colors.red),
                  );
                  return;
                }
                if (selectedRoleId == null || selectedRoleId == -1) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(tr('Lavozimni tanlang!')), backgroundColor: Colors.red),
                  );
                  return;
                }
                double salaryValue = selectedSalaryType.startsWith('percent')
                    ? double.tryParse(percentController.text) ?? 0
                    : double.tryParse(salaryController.text) ?? 0;
                try {
                  final res = await ApiService.post(AppConstants.users, {
                    'full_name': nameController.text,
                    'phone': phoneController.text,
                    'password': passwordController.text,
                    'role_id': selectedRoleId,
                    'face_id': faceIdController.text.isEmpty ? null : faceIdController.text,
                    'salary_type': selectedSalaryType,
                    'salary_value': salaryValue,
                    'salary_tier_threshold': double.tryParse(tierThresholdController.text) ?? 0,
                    'salary_tier_value': double.tryParse(tierValueController.text) ?? 0,
                    'work_start': workStart,
                    'work_end': workEnd,
                    'late_fine_per_minute': double.tryParse(lateFineController.text) ?? 0,
                    'salary_day': int.tryParse(salaryDayController.text) ?? 1,
                    'salary_period_days': int.tryParse(salaryPeriodController.text) ?? 30,
                  });
                  // Server xato qaytarsa (id yo'q) — ko'rsatamiz, dialog yopilmaydi
                  if (res is Map && res['id'] == null && res['message'] != null) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Xato: ${res['message']}'), backgroundColor: Colors.red),
                      );
                    }
                    return;
                  }
                  if (context.mounted) Navigator.pop(context);
                  _loadUsers();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: Text(tr('Saqlash'), style: TextStyle(color: AppTheme.text)),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditUserDialog(Map<String, dynamic> user) {
    final nameController = TextEditingController(text: user['full_name'] ?? '');
    final phoneController = TextEditingController(text: user['phone'] ?? '');
    final passwordController = TextEditingController();
    final faceIdController = TextEditingController(text: user['face_id'] ?? '');
    final lateFineController = TextEditingController(
      text: (double.tryParse(user['late_fine_per_minute']?.toString() ?? '0') ?? 0).toStringAsFixed(0),
    );
    final salaryDayController = TextEditingController(
      text: ((user['salary_day'] as num?)?.toInt() ?? 1).toString(),
    );
    final salaryPeriodController = TextEditingController(
      text: ((user['salary_period_days'] as num?)?.toInt() ?? 30).toString(),
    );
    String workStart = (user['work_start']?.toString() ?? '09:00');
    String workEnd = (user['work_end']?.toString() ?? '22:00');

    int? selectedRoleId = _roles.isEmpty
        ? null
        : (_roles.firstWhere((r) => r['name'] == user['role_name'], orElse: () => _roles.first)['id'] as int);

    String selectedSalaryType = user['salary_type'] ?? 'monthly';
    final salaryController = TextEditingController(
      text: !selectedSalaryType.startsWith('percent') ? (user['salary_value'] ?? 0).toString() : '',
    );
    final percentController = TextEditingController(
      text: selectedSalaryType.startsWith('percent') ? (user['salary_value'] ?? 0).toString() : '',
    );
    final tierThresholdController = TextEditingController(
      text: ((double.tryParse(user['salary_tier_threshold']?.toString() ?? '0') ?? 0) > 0)
          ? (double.tryParse(user['salary_tier_threshold'].toString()) ?? 0).toStringAsFixed(0) : '',
    );
    final tierValueController = TextEditingController(
      text: ((double.tryParse(user['salary_tier_value']?.toString() ?? '0') ?? 0) > 0)
          ? (double.tryParse(user['salary_tier_value'].toString()) ?? 0).toStringAsFixed(0) : '',
    );

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text(tr('Xodimni tahrirlash'), style: TextStyle(color: AppTheme.text)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTextField(nameController, tr('Ism familiya'), Icons.person),
                const SizedBox(height: 12),
                _buildTextField(phoneController, tr('Telefon raqam'), Icons.phone),
                const SizedBox(height: 12),
                _buildTextField(passwordController, tr('Yangi parol (ixtiyoriy)'), Icons.lock, isPassword: true),
                const SizedBox(height: 4),
                Text(tr('* Bo\'sh qolsa parol o\'zgarmaydi'), style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
                const SizedBox(height: 12),
                _buildTextField(faceIdController, tr('Face ID raqami'), Icons.face),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _enrollToDevice(faceIdController.text.trim(), nameController.text.trim()),
                    icon: Icon(Icons.sensor_occupied, size: 18, color: AppTheme.accent),
                    label: Text(tr('Qurilmaga qo\'shish (Face ID)'), style: TextStyle(color: AppTheme.accent)),
                    style: OutlinedButton.styleFrom(side: BorderSide(color: AppTheme.border)),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: selectedRoleId,
                  dropdownColor: AppTheme.card,
                  style: TextStyle(color: AppTheme.text),
                  decoration: _inputDecoration(tr('Lavozim'), Icons.work),
                  items: [
                    ..._roles.map((r) => DropdownMenuItem<int>(
                      value: r['id'] as int,
                      child: Text(_getRoleLabel(r['name']?.toString() ?? ''), style: TextStyle(color: AppTheme.text)),
                    )),
                    DropdownMenuItem<int>(
                      value: -1,
                      child: Text(tr('＋ Yangi lavozim...'), style: TextStyle(color: AppTheme.accent)),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == -1) {
                      _promptNewRole((id) => setStateDialog(() => selectedRoleId = id));
                    } else {
                      setStateDialog(() => selectedRoleId = v);
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedSalaryType,
                  dropdownColor: AppTheme.card,
                  style: TextStyle(color: AppTheme.text),
                  decoration: _inputDecoration(tr('Maosh turi'), Icons.attach_money),
                  items: _salaryTypes.map((s) => DropdownMenuItem<String>(
                    value: s['value'] as String,
                    child: Text(s['label'] as String, style: TextStyle(color: AppTheme.text, fontSize: 13)),
                  )).toList(),
                  onChanged: (v) => setStateDialog(() => selectedSalaryType = v!),
                ),
                const SizedBox(height: 12),
                if (selectedSalaryType.startsWith('percent')) ...[
                  _buildTextField(percentController, tr('Foiz miqdori (%)'), Icons.percent, isNumber: true),
                ] else ...[
                  _buildTextField(salaryController, tr('Maosh miqdori (so\'m)'), Icons.monetization_on, isNumber: true),
                ],
                if (selectedSalaryType == 'percent') ...[
                  const SizedBox(height: 10),
                  Text(tr('Progressiv (ixtiyoriy): kunlik savdo chegaradan oshsa — oshgan foiz ishlaydi'),
                      style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(child: _buildTextField(tierThresholdController, tr('Kunlik chegara (so\'m)'), Icons.trending_up, isNumber: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTextField(tierValueController, tr('Oshgan foiz (%)'), Icons.percent, isNumber: true)),
                  ]),
                ],
                if (selectedSalaryType == 'piece') ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _showPieceRatesDialog(user['id'] as int, user['full_name']?.toString() ?? ''),
                      icon: Icon(Icons.restaurant_menu, size: 18, color: AppTheme.accent),
                      label: Text(tr('Dona stavkalar (taomlar)'), style: TextStyle(color: AppTheme.accent)),
                      style: OutlinedButton.styleFrom(side: BorderSide(color: AppTheme.border)),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildTimeField(context, tr('Ish boshlanishi'), workStart,
                          (v) => setStateDialog(() => workStart = v)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildTimeField(context, tr('Ish tugashi'), workEnd,
                          (v) => setStateDialog(() => workEnd = v)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildTextField(lateFineController, tr('Kechikish jarimasi (so\'m / daqiqa)'), Icons.money_off, isNumber: true),
                const SizedBox(height: 4),
                Text(tr('* 1 daqiqa kech qolsa shu summa jarima yoziladi'), style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
                const SizedBox(height: 12),
                _buildTextField(salaryPeriodController, tr('Necha kunda oylik (kun)'), Icons.event_repeat, isNumber: true),
                const SizedBox(height: 4),
                Text(tr('* Masalan: 30 = oylik, 10 = har 10 kunda'), style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
              onPressed: () async {
                if (nameController.text.isEmpty || phoneController.text.isEmpty) return;
                final double salaryValue = selectedSalaryType.startsWith('percent')
                    ? double.tryParse(percentController.text) ?? 0
                    : double.tryParse(salaryController.text) ?? 0;

                final data = <String, dynamic>{
                  'full_name': nameController.text,
                  'phone': phoneController.text,
                  'role_id': selectedRoleId,
                  'face_id': faceIdController.text.isEmpty ? null : faceIdController.text,
                  'salary_type': selectedSalaryType,
                  'salary_value': salaryValue,
                  'salary_tier_threshold': double.tryParse(tierThresholdController.text) ?? 0,
                  'salary_tier_value': double.tryParse(tierValueController.text) ?? 0,
                  'is_active': user['is_active'] ?? true,
                  'work_start': workStart,
                  'work_end': workEnd,
                  'late_fine_per_minute': double.tryParse(lateFineController.text) ?? 0,
                  'salary_day': int.tryParse(salaryDayController.text) ?? 1,
                  'salary_period_days': int.tryParse(salaryPeriodController.text) ?? 30,
                };
                if (passwordController.text.isNotEmpty) {
                  data['password'] = passwordController.text;
                }

                try {
                  await ApiService.put('${AppConstants.users}/${user['id']}', data);
                  if (context.mounted) Navigator.pop(context);
                  _loadUsers();
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: Text(tr('Saqlash'), style: TextStyle(color: AppTheme.text)),
            ),
          ],
        ),
      ),
    );
  }

  // Sdelnaya: xodim uchun taomlarga 1-dona stavkasi belgilash (POST /reports/piece-rates)
  Future<void> _showPieceRatesDialog(int userId, String userName) async {
    List<dynamic> menu = [];
    final Map<int, TextEditingController> rateCtrls = {};
    String search = '';
    try {
      final m = await ApiService.get(AppConstants.menuItems);
      menu = (m is List) ? m : [];
      final existing = await ApiService.get('/reports/piece-rates?user_id=$userId');
      final Map<int, num> exMap = {};
      if (existing is List) {
        for (final e in existing) {
          final mid = (e['menu_item_id'] as num?)?.toInt();
          if (mid != null) exMap[mid] = (e['rate'] as num?) ?? 0;
        }
      }
      for (final it in menu) {
        final id = (it['id'] as num?)?.toInt();
        if (id == null) continue;
        rateCtrls[id] = TextEditingController(
          text: (exMap[id] != null && exMap[id]! > 0) ? exMap[id]!.toStringAsFixed(0) : '',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
      }
      return;
    }
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) {
          final filtered = menu.where((it) => search.isEmpty ||
              (it['name']?.toString().toLowerCase() ?? '').contains(search.toLowerCase())).toList();
          return AlertDialog(
            backgroundColor: AppTheme.card,
            title: Text('${tr('Dona stavkalar')}: $userName', style: TextStyle(color: AppTheme.text, fontSize: 16)),
            content: SizedBox(
              width: 420,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(tr('Har taom uchun 1 dona stavkasi (so\'m). Bo\'sh = hisoblanmaydi.'),
                    style: TextStyle(color: AppTheme.textSoft, fontSize: 11.5)),
                const SizedBox(height: 8),
                TextField(
                  onChanged: (v) => setSt(() => search = v),
                  style: TextStyle(color: AppTheme.text),
                  decoration: InputDecoration(
                    hintText: tr('Qidirish...'),
                    hintStyle: TextStyle(color: AppTheme.textSoft),
                    prefixIcon: Icon(Icons.search, color: AppTheme.textSoft, size: 20),
                    isDense: true,
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.accent)),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 340,
                  width: 420,
                  child: filtered.isEmpty
                      ? Center(child: Text(tr('Taom yo\'q'), style: TextStyle(color: AppTheme.textSoft)))
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final it = filtered[i];
                            final id = (it['id'] as num).toInt();
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(children: [
                                Expanded(
                                    child: Text(it['name']?.toString() ?? '',
                                        maxLines: 1, overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: AppTheme.text, fontSize: 13))),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 120,
                                  child: TextField(
                                    controller: rateCtrls[id],
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    style: TextStyle(color: AppTheme.text, fontSize: 13),
                                    decoration: InputDecoration(
                                      hintText: tr('stavka'),
                                      hintStyle: TextStyle(color: AppTheme.textSoft, fontSize: 12),
                                      isDense: true,
                                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.accent)),
                                    ),
                                  ),
                                ),
                              ]),
                            );
                          },
                        ),
                ),
              ]),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx),
                  child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
                onPressed: () async {
                  final rates = <Map<String, dynamic>>[];
                  rateCtrls.forEach((id, c) {
                    final r = double.tryParse(c.text.trim()) ?? 0;
                    if (r > 0) rates.add({'menu_item_id': id, 'rate': r});
                  });
                  try {
                    await ApiService.post('/reports/piece-rates', {'user_id': userId, 'rates': rates});
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('${tr('Saqlandi')}: ${rates.length} ${tr('taom')}'),
                          backgroundColor: Colors.green));
                    }
                  } catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
                    }
                  }
                },
                child: Text(tr('Saqlash'), style: TextStyle(color: AppTheme.onAccent)),
              ),
            ],
          );
        },
      ),
    );
  }

  String _getSalaryTypeLabel(String type) {
    switch (type) {
      case 'monthly': return tr('Oylik');
      case 'daily': return tr('Kunlik');
      case 'hourly': return tr('Soatlik');
      case 'percent': return tr('Foiz');
      case 'percent_total': return tr('Jami tushumdan foiz');
      case 'piece': return tr('Dona uchun');
      default: return type;
    }
  }

  String _getRoleLabel(String role) {
    switch (role) {
      case 'admin': return tr('Admin');
      case 'waiter': return tr('Ofitsant');
      case 'chef': return tr('Oshpaz');
      case 'cashier': return tr('Kassir');
      case 'cleaner': return tr('Sanitarka');
      default: return role.isEmpty ? role : role[0].toUpperCase() + role.substring(1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : _users.isEmpty
          ? Center(child: Text(tr('Xodimlar yo\'q'), style: TextStyle(color: AppTheme.textSoft)))
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _users.length,
        itemBuilder: (context, index) {
          final user = _users[index];
          final salaryType = user['salary_type'] ?? '';
          final salaryValue = user['salary_value'] ?? 0;
          final salaryText = (salaryType as String).startsWith('percent') ? '$salaryValue%' : '$salaryValue ${tr('so\'m')}';
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.textSoft.withOpacity(0.2)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppTheme.accent,
                  child: Text(user['full_name'][0].toUpperCase(), style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user['full_name'], style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(user['phone'] ?? '', style: TextStyle(color: AppTheme.textSoft, fontSize: 13)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                            child: Text(_getRoleLabel(user['role_name'] ?? ''), style: TextStyle(color: AppTheme.accent, fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                          Text('${_getSalaryTypeLabel(salaryType)} | $salaryText', style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
                        ],
                      ),
                      if (user['face_id'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Icon(Icons.face, color: Colors.green, size: 14),
                              const SizedBox(width: 4),
                              Text('Face ID: ${user['face_id']}', style: TextStyle(color: Colors.green, fontSize: 12)),
                            ],
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            Icon(Icons.access_time, color: Colors.orangeAccent, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              '${tr('Ish')}: ${user['work_start'] ?? '09:00'}–${user['work_end'] ?? '22:00'}'
                              '${(double.tryParse(user['late_fine_per_minute']?.toString() ?? '0') ?? 0) > 0 ? '  •  ${tr('jarima')} ${(double.tryParse(user['late_fine_per_minute'].toString()) ?? 0).toStringAsFixed(0)} ${tr('so\'m')}/${tr('daq')}' : ''}',
                              style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(user['is_active'] == true ? Icons.check_circle : Icons.cancel,
                        color: user['is_active'] == true ? Colors.green : Colors.red),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () => _showEditUserDialog(user),
                      child: Icon(Icons.edit, color: Colors.blue, size: 20),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.accent,
        onPressed: _showAddUserDialog,
        child: Icon(Icons.add, color: AppTheme.text),
      ),
    );
  }
}

// ===== BO'LIMLAR / PRINTERLAR =====
class PrintStationsScreen extends StatefulWidget {
  const PrintStationsScreen({super.key});

  @override
  State<PrintStationsScreen> createState() => _PrintStationsScreenState();
}

class _PrintStationsScreenState extends State<PrintStationsScreen> {
  List<dynamic> _stations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.get(AppConstants.stations);
      setState(() {
        _stations = data is List ? data : [];
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  // Kompdagi printerlar ro'yxati: backend (asosiy — telefondan ham ishlaydi) + klient (desktop)
  Future<List<String>> _fetchPrinters() async {
    final set = <String>{};
    try {
      final data = await ApiService.get(AppConstants.printersList);
      if (data is List) set.addAll(data.map((e) => e.toString()).where((s) => s.isNotEmpty));
    } catch (_) {}
    try {
      final printers = await Printing.listPrinters();
      set.addAll(printers.map((p) => p.name).where((n) => n.isNotEmpty));
    } catch (_) {}
    return set.toList();
  }

  // Sinov chekini yuborish (snackbarsiz, natija qaytaradi)
  Future<bool> _sendTest({String? printerName, String? printerIp, int? printerPort, String? label}) async {
    try {
      final res = await ApiService.post(AppConstants.printTest, {
        if (printerName != null) 'printer_name': printerName,
        if (printerIp != null) 'printer_ip': printerIp,
        if (printerPort != null) 'printer_port': printerPort,
        if (label != null) 'label': label,
      });
      return res is Map && res['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  // Bitta printerga sinov cheki + natija snackbar
  Future<void> _testPrint({String? printerName, String? printerIp, int? printerPort, String? label}) async {
    final who = label ?? printerName ?? printerIp ?? '';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${tr('Sinov cheki yuborilmoqda')}: $who...'),
      duration: const Duration(milliseconds: 900),
    ));
    final ok = await _sendTest(printerName: printerName, printerIp: printerIp, printerPort: printerPort, label: label);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? '✅ ${tr('Chek chiqdi')}: $who'
          : '❌ ${tr('Chiqmadi')}: $who (${tr('printer o\'chiq yoki ulanmagan')})'),
      backgroundColor: ok ? Colors.green : Colors.red,
      duration: const Duration(seconds: 3),
    ));
  }

  // BARCHA o'rnatilgan printerlarga sinov — har biri o'z nomini chop etadi (qaysi qaysi ekanini aniqlash)
  Future<void> _testAllPrinters() async {
    final printers = await _fetchPrinters();
    if (!mounted) return;
    if (printers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Printer topilmadi'))));
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('Printerlarni aniqlash'), style: TextStyle(color: AppTheme.text)),
        content: Text(
          '${printers.length} ${tr('ta printerga sinov cheki chiqadi. Har bir chekda printer nomi yoziladi — qaysi joydan (oshxona/bar...) chiqqanini ko\'rib, o\'sha printerni belgilab oling.')}',
          style: TextStyle(color: AppTheme.textSoft),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Chiqarish'), style: TextStyle(color: AppTheme.text)),
          ),
        ],
      ),
    );
    if (go != true) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${printers.length} ${tr('printerga sinov yuborilmoqda...')}'),
      duration: const Duration(seconds: 2),
    ));
    int ok = 0;
    for (final name in printers) {
      if (await _sendTest(printerName: name, label: name)) ok++;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('✅ $ok / ${printers.length} ${tr('printerdan chek chiqdi. Qaysi joydan chiqqanini ko\'rib belgilang!')}'),
      backgroundColor: Colors.green,
      duration: const Duration(seconds: 5),
    ));
  }

  Future<void> _showForm({Map<String, dynamic>? station}) async {
    final isEdit = station != null;
    final nameCtrl = TextEditingController(text: station?['name']?.toString() ?? '');
    final ipCtrl = TextEditingController(text: station?['printer_ip']?.toString() ?? '');
    final portCtrl = TextEditingController(text: (station?['printer_port'] ?? 9100).toString());

    // Ulanish turi: 'net' (IP) | 'usb' (Windows printer) | 'none' (faylga)
    final ipVal = station?['printer_ip']?.toString() ?? '';
    final nameVal = station?['printer_name']?.toString() ?? '';
    String connType = ipVal.isNotEmpty ? 'net' : (nameVal.isNotEmpty ? 'usb' : 'none');
    String? selectedPrinter = nameVal.isNotEmpty ? nameVal : null;

    // O'rnatilgan (USB/Windows) printerlar ro'yxati — backenddan (komp), telefondan ham ishlaydi
    List<String> printerNames = await _fetchPrinters();
    if (selectedPrinter != null && !printerNames.contains(selectedPrinter)) {
      printerNames.insert(0, selectedPrinter);
    }
    selectedPrinter ??= printerNames.isNotEmpty ? printerNames.first : null;

    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: AppTheme.textSoft),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.textSoft)),
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.accent)),
        );

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setSt) => AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text(isEdit ? tr('Bo\'limni tahrirlash') : tr('Yangi bo\'lim'),
              style: TextStyle(color: AppTheme.text)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameCtrl, style: TextStyle(color: AppTheme.text), decoration: deco(tr('Bo\'lim nomi (masalan: Oshxona)'))),
                const SizedBox(height: 12),
                // Ulanish turi
                DropdownButtonFormField<String>(
                  value: connType,
                  dropdownColor: AppTheme.card,
                  style: TextStyle(color: AppTheme.text),
                  decoration: deco(tr('Printer ulanishi')),
                  items: [
                    DropdownMenuItem(value: 'net', child: Text(tr('Tarmoq (IP)'), style: TextStyle(color: AppTheme.text))),
                    DropdownMenuItem(value: 'usb', child: Text(tr('USB printer'), style: TextStyle(color: AppTheme.text))),
                    DropdownMenuItem(value: 'none', child: Text(tr('Yo\'q (faylga)'), style: TextStyle(color: AppTheme.text))),
                  ],
                  onChanged: (v) => setSt(() => connType = v ?? 'none'),
                ),
                const SizedBox(height: 12),
                if (connType == 'net') ...[
                  TextField(controller: ipCtrl, style: TextStyle(color: AppTheme.text), decoration: deco(tr('Printer IP (masalan: 192.168.1.50)'))),
                  const SizedBox(height: 12),
                  TextField(controller: portCtrl, style: TextStyle(color: AppTheme.text), keyboardType: TextInputType.number, decoration: deco(tr('Port (odatda 9100)'))),
                ] else if (connType == 'usb') ...[
                  if (printerNames.isEmpty)
                    Text(tr('Printer topilmadi. USB printerni ulab, ilovani qayta oching.'),
                        style: TextStyle(color: Colors.orange, fontSize: 12))
                  else
                    DropdownButtonFormField<String>(
                      value: selectedPrinter,
                      isExpanded: true,
                      dropdownColor: AppTheme.card,
                      style: TextStyle(color: AppTheme.text),
                      decoration: deco(tr('USB printer')),
                      items: printerNames.map((n) => DropdownMenuItem<String>(
                        value: n,
                        child: Text(n, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppTheme.text)),
                      )).toList(),
                      onChanged: (v) => setSt(() => selectedPrinter = v),
                    ),
                ] else ...[
                  Text(tr('Chek faylga yoziladi (backend/tickets) — printer kelguncha sinov uchun.'),
                      style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
                ],
                if (connType != 'none') ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: Icon(Icons.receipt_long, size: 18, color: AppTheme.accent),
                      label: Text(tr('Bu printerni sinab ko\'rish'), style: TextStyle(color: AppTheme.accent)),
                      style: OutlinedButton.styleFrom(side: BorderSide(color: AppTheme.accent)),
                      onPressed: () {
                        final label = nameCtrl.text.trim();
                        if (connType == 'net') {
                          final ip = ipCtrl.text.trim();
                          if (ip.isEmpty) return;
                          _testPrint(printerIp: ip, printerPort: int.tryParse(portCtrl.text.trim()) ?? 9100, label: label.isNotEmpty ? label : ip);
                        } else if (connType == 'usb' && selectedPrinter != null) {
                          _testPrint(printerName: selectedPrinter, label: label.isNotEmpty ? label : selectedPrinter);
                        }
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('Saqlash'), style: TextStyle(color: AppTheme.text)),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;
    if (nameCtrl.text.trim().isEmpty) return;
    final body = {
      'name': nameCtrl.text.trim(),
      'printer_ip': connType == 'net' && ipCtrl.text.trim().isNotEmpty ? ipCtrl.text.trim() : null,
      'printer_port': int.tryParse(portCtrl.text.trim()) ?? 9100,
      'printer_name': connType == 'usb' ? selectedPrinter : null,
    };
    try {
      if (isEdit) {
        await ApiService.put('${AppConstants.stations}/${station['id']}', body);
      } else {
        await ApiService.post(AppConstants.stations, body);
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> s) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('O\'chirish'), style: TextStyle(color: AppTheme.text)),
        content: Text('${s['name']} ${tr('bo\'limini o\'chirasizmi?')}', style: TextStyle(color: AppTheme.textSoft)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('O\'chirish'), style: TextStyle(color: AppTheme.text)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ApiService.delete('${AppConstants.stations}/${s['id']}');
      _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.card,
        title: Text(tr('Bo\'limlar / Printerlar'), style: TextStyle(color: AppTheme.text)),
        iconTheme: IconThemeData(color: AppTheme.text),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('Har bo\'limga o\'z printerini belgilang — taom shu bo\'lim printeridan chiqadi. '
                        'Qaysi printer qayerda ekanini bilish uchun "Printerlarni aniqlash"ni bosing: '
                        'har bir printer o\'z nomini chop etadi.'),
                        style: TextStyle(color: AppTheme.textSoft, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.print, size: 18),
                          label: Text(tr('Printerlarni aniqlash (hammasiga sinov chek)')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.accent,
                            foregroundColor: AppTheme.onAccent,
                          ),
                          onPressed: _testAllPrinters,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _stations.isEmpty
                      ? Center(child: Text(tr('Bo\'lim yo\'q'), style: TextStyle(color: AppTheme.textSoft)))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _stations.length,
                          itemBuilder: (context, index) {
                            final s = _stations[index] as Map<String, dynamic>;
                            final ip = s['printer_ip']?.toString();
                            final pname = s['printer_name']?.toString();
                            final hasIp = (ip != null && ip.isNotEmpty) || (pname != null && pname.isNotEmpty);
                            final connLabel = (ip != null && ip.isNotEmpty)
                                ? 'IP: $ip : ${s['printer_port'] ?? 9100}'
                                : (pname != null && pname.isNotEmpty)
                                    ? 'USB: $pname'
                                    : tr('Printer belgilanmagan (faylga)');
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: AppTheme.card,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: hasIp ? Colors.green.withValues(alpha: 0.5) : Colors.orange.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.print, color: hasIp ? Colors.green : Colors.orange),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(s['name']?.toString() ?? '',
                                            style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 15)),
                                        const SizedBox(height: 2),
                                        Text(
                                          connLabel,
                                          style: TextStyle(color: hasIp ? Colors.green : Colors.orange, fontSize: 13),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.receipt_long,
                                        color: hasIp ? AppTheme.accent : AppTheme.textSoft.withValues(alpha: 0.4), size: 20),
                                    tooltip: tr('Sinov cheki'),
                                    onPressed: hasIp
                                        ? () {
                                            if (ip != null && ip.isNotEmpty) {
                                              _testPrint(printerIp: ip, printerPort: int.tryParse('${s['printer_port'] ?? 9100}') ?? 9100, label: s['name']?.toString());
                                            } else if (pname != null && pname.isNotEmpty) {
                                              _testPrint(printerName: pname, label: s['name']?.toString());
                                            }
                                          }
                                        : null,
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.edit, color: AppTheme.textSoft, size: 20),
                                    onPressed: () => _showForm(station: s),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete, color: Colors.red, size: 20),
                                    onPressed: () => _delete(s),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.accent,
        onPressed: () => _showForm(),
        child: Icon(Icons.add, color: AppTheme.text),
      ),
    );
  }
}

// ===== HISOBOT BO'LIMI (ishchilar davomati) =====
class ReportSection extends StatefulWidget {
  const ReportSection({super.key});

  @override
  State<ReportSection> createState() => _ReportSectionState();
}

class _ReportSectionState extends State<ReportSection> {
  int _subTab = 0; // 0 = moliyaviy, 1 = davomat

  // ── Moliyaviy ──
  bool _finLoading = true;
  String _period = 'today';
  Map<String, dynamic>? _fin;

  // ── Davomat ──
  bool _attLoading = true;
  DateTime _date = DateTime.now();
  Map<String, dynamic>? _report;

  @override
  void initState() {
    super.initState();
    _loadFinancial();
    _loadAttendance();
  }

  String get _dateStr =>
      '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  Future<void> _loadFinancial() async {
    setState(() => _finLoading = true);
    try {
      final data = await ApiService.get('${AppConstants.reportSummary}?period=$_period');
      if (mounted) setState(() {
        _fin = data is Map<String, dynamic> ? data : null;
        _finLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _finLoading = false);
    }
  }

  Future<void> _loadAttendance() async {
    setState(() => _attLoading = true);
    try {
      final data = await ApiService.get('${AppConstants.attendanceReport}?date=$_dateStr');
      if (mounted) setState(() {
        _report = data is Map<String, dynamic> ? data : null;
        _attLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _attLoading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2023),
      lastDate: DateTime(2100),
      builder: (c, w) => Theme(
        data: ThemeData.dark().copyWith(colorScheme: ColorScheme.dark(primary: AppTheme.accent)),
        child: w!,
      ),
    );
    if (picked != null) {
      setState(() => _date = picked);
      _loadAttendance();
    }
  }

  String _money(num v) {
    final neg = v < 0;
    final s = v.abs().toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return (neg ? '-' : '') + buf.toString();
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'admin': return tr('Admin');
      case 'waiter': return tr('Ofitsant');
      case 'chef': return tr('Oshpaz');
      case 'cashier': return tr('Kassir');
      case 'cleaner': return tr('Sanitarka');
      default: return role.isEmpty ? role : role[0].toUpperCase() + role.substring(1);
    }
  }

  String get _periodLabel {
    switch (_period) {
      case 'week': return tr('Hafta');
      case 'month': return tr('Oy');
      default: return tr('Bugun');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.bar_chart, color: AppTheme.accent),
                    const SizedBox(width: 8),
                    Text(tr('Hisobot'),
                        style: TextStyle(color: AppTheme.text, fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (_subTab == 0 && _fin != null)
                      IconButton(
                        icon: Icon(Icons.picture_as_pdf, color: AppTheme.accent),
                        tooltip: tr('PDF hisobot'),
                        onPressed: _generatePdf,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _subTabChip(tr('Moliyaviy'), 0),
                    const SizedBox(width: 8),
                    _subTabChip(tr('Davomat'), 1),
                  ],
                ),
                const SizedBox(height: 8),
                if (_subTab == 0)
                  Row(
                    children: [
                      _periodChip(tr('Bugun'), 'today'),
                      _periodChip(tr('Hafta'), 'week'),
                      _periodChip(tr('Oy'), 'month'),
                    ],
                  )
                else
                  Row(
                    children: [
                      const Spacer(),
                      GestureDetector(
                        onTap: _pickDate,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.card,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.accent),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today, color: AppTheme.accent, size: 16),
                              const SizedBox(width: 6),
                              Text(_dateStr, style: TextStyle(color: AppTheme.text, fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Expanded(child: _subTab == 0 ? _financialBody() : _attendanceBody()),
        ],
      ),
    );
  }

  Widget _subTabChip(String label, int tab) {
    final sel = _subTab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _subTab = tab),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: sel ? AppTheme.accent : AppTheme.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? AppTheme.accent : AppTheme.border),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: sel ? Colors.white : AppTheme.textSoft,
                  fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13)),
        ),
      ),
    );
  }

  Widget _periodChip(String label, String value) {
    final sel = _period == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () {
          setState(() => _period = value);
          _loadFinancial();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: sel ? AppTheme.accent : AppTheme.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: sel ? AppTheme.accent : AppTheme.border),
          ),
          child: Text(label,
              style: TextStyle(color: sel ? Colors.white : AppTheme.textSoft, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      ),
    );
  }

  // ── MOLIYAVIY ──
  Widget _financialBody() {
    if (_finLoading) return Center(child: CircularProgressIndicator(color: AppTheme.accent));
    if (_fin == null) return Center(child: Text(tr('Ma\'lumot yo\'q'), style: TextStyle(color: AppTheme.textSoft)));
    final d = _fin!;
    double n(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0;
    final pay = (d['payments'] as Map?) ?? {};
    final top = (d['top_items'] as List?) ?? [];
    final waiters = (d['waiter_sales'] as List?) ?? [];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Row(
          children: [
            _statCard(tr('Savdo'), _money(n(d['sales'])), AppTheme.accent, icon: Icons.trending_up, onTap: () => _showDetail('sales')),
            const SizedBox(width: 10),
            _statCard(tr('Harajat'), _money(n(d['expenses'])), Colors.red, icon: Icons.money_off, onTap: () => _showDetail('expenses')),
            const SizedBox(width: 10),
            _statCard(tr('Sof foyda'), _money(n(d['profit'])), Colors.green, icon: Icons.savings, onTap: () => _showDetail('profit')),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _statCard(tr('Karta'), _money(n(pay['card'])), Colors.blue, icon: Icons.credit_card, onTap: () => _showDetail('card')),
            const SizedBox(width: 10),
            _statCard(tr('Naqd'), _money(n(pay['cash'])), Colors.green, icon: Icons.payments, onTap: () => _showDetail('cash')),
            const SizedBox(width: 10),
            _statCard(tr('Qarz'), _money(n(pay['debt'])), Colors.deepOrange, icon: Icons.account_balance_wallet, onTap: () => _showDetail('debt')),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _statCard(tr('Zakazlar'), '${(d['orders_count'] as num?)?.toInt() ?? 0}', AppTheme.accent, icon: Icons.receipt_long, onTap: () => _showDetail('orders')),
            const SizedBox(width: 10),
            _statCard(tr('O\'rtacha chek'), _money(n(d['avg_check'])), Colors.teal, icon: Icons.receipt, onTap: () => _showDetail('avg')),
            const SizedBox(width: 10),
            _statCard(tr('Chegirma'), _money(n(d['discount_total'])), Colors.purple, icon: Icons.percent, onTap: () => _showDetail('discount')),
          ],
        ),
        const SizedBox(height: 16),
        _listHeader(tr('Eng ko\'p sotilgan')),
        ...top.map((t) {
          final mp = t as Map<String, dynamic>;
          return _lineRow(
            mp['name']?.toString() ?? '',
            '${(mp['qty'] as num?)?.toInt() ?? 0} ${tr('ta')}',
            '${_money(n(mp['amount']))} ${tr('so\'m')}',
          );
        }),
        if (top.isEmpty) _emptyLine(),
        const SizedBox(height: 16),
        _listHeader(tr('Ofitsantlar reytingi')),
        ...waiters.map((w) {
          final mp = w as Map<String, dynamic>;
          return _lineRow(
            mp['full_name']?.toString() ?? '',
            '${(mp['orders'] as num?)?.toInt() ?? 0} ${tr('ta zakaz')}',
            '${_money(n(mp['sales']))} ${tr('so\'m')}',
          );
        }),
        if (waiters.isEmpty) _emptyLine(),
      ],
    );
  }

  Widget _listHeader(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(t, style: TextStyle(color: AppTheme.text, fontSize: 15, fontWeight: FontWeight.bold)),
      );

  Widget _emptyLine() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(tr('Ma\'lumot yo\'q'), style: TextStyle(color: AppTheme.textSoft, fontSize: 13)),
      );

  Widget _lineRow(String name, String mid, String amount) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(child: Text(name, style: TextStyle(color: AppTheme.text, fontSize: 13))),
          Text(mid, style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
          const SizedBox(width: 12),
          Text(amount, style: TextStyle(color: AppTheme.accent, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ── DAVOMAT (mavjud) ──
  Widget _attendanceBody() {
    final staff = (_report?['staff'] as List?) ?? [];
    final present = _report?['present_count'] ?? 0;
    final absent = _report?['absent_count'] ?? 0;
    final totalFine = double.tryParse(_report?['total_fine']?.toString() ?? '0') ?? 0;
    if (_attLoading) return Center(child: CircularProgressIndicator(color: AppTheme.accent));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              _statCard(tr('Kelganlar'), '$present', Colors.green, icon: Icons.how_to_reg),
              const SizedBox(width: 10),
              _statCard(tr('Kelmaganlar'), '$absent', Colors.red, icon: Icons.person_off),
              const SizedBox(width: 10),
              _statCard(tr('Jami jarima'), '${_money(totalFine)} ${tr('so\'m')}', Colors.orange, icon: Icons.gavel),
            ],
          ),
        ),
        Expanded(
          child: staff.isEmpty
              ? Center(child: Text(tr('Ma\'lumot yo\'q'), style: TextStyle(color: AppTheme.textSoft)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  itemCount: staff.length,
                  itemBuilder: (context, index) {
                    final s = staff[index] as Map<String, dynamic>;
                    final came = s['came'] == true;
                    final lateMin = (s['late_minutes'] as num?)?.toInt() ?? 0;
                    final fine = double.tryParse(s['fine']?.toString() ?? '0') ?? 0;
                    final isLate = lateMin > 0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: !came
                              ? Colors.red.withValues(alpha: 0.5)
                              : (isLate ? Colors.orange.withValues(alpha: 0.6) : Colors.green.withValues(alpha: 0.5)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            !came ? Icons.cancel : (isLate ? Icons.warning_amber : Icons.check_circle),
                            color: !came ? Colors.red : (isLate ? Colors.orange : Colors.green),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s['full_name']?.toString() ?? '',
                                    style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 15)),
                                Text(
                                  '${_roleLabel(s['role_name']?.toString() ?? '')}  •  ${tr('Ish')}: ${s['work_start'] ?? '-'}–${s['work_end'] ?? '-'}',
                                  style: TextStyle(color: AppTheme.textSoft, fontSize: 12),
                                ),
                                const SizedBox(height: 4),
                                if (came)
                                  Text(
                                    '${tr('Keldi')}: ${s['check_in'] ?? '-'}    ${tr('Ketdi')}: ${s['check_out'] ?? '— (${tr('hali ishda')})'}',
                                    style: TextStyle(color: AppTheme.textSoft, fontSize: 13),
                                  )
                                else
                                  Text(tr('Kelmadi'), style: TextStyle(color: Colors.red, fontSize: 13)),
                              ],
                            ),
                          ),
                          if (came && isLate)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('$lateMin ${tr('daq kech')}',
                                    style: TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.bold)),
                                if (fine > 0)
                                  Text('-${_money(fine)} ${tr('so\'m')}',
                                      style: TextStyle(color: AppTheme.accent, fontSize: 13)),
                              ],
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _statCard(String label, String value, Color color, {VoidCallback? onTap, IconData? icon}) {
    final card = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                  child: Icon(icon, size: 14, color: color),
                ),
                const SizedBox(width: 7),
              ],
              Expanded(
                child: Text(label,
                    style: TextStyle(color: AppTheme.textSoft, fontSize: 11.5),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right, size: 16, color: AppTheme.textSoft.withValues(alpha: 0.7)),
            ],
          ),
          const SizedBox(height: 9),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(color: color, fontSize: 21, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    return Expanded(
      child: onTap == null
          ? card
          : Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: card),
            ),
    );
  }

  Widget _detailSub(String t) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6, left: 2),
        child: Text(t, style: TextStyle(color: AppTheme.textSoft, fontSize: 12, fontWeight: FontWeight.bold)),
      );

  // Karta bosilganda — to'liq tafsilot oynasi
  void _showDetail(String which) {
    final d = _fin;
    if (d == null) return;
    double n(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0;
    final pay = (d['payments'] as Map?) ?? {};

    String title = '';
    String headerValue = '';
    Color headerColor = AppTheme.accent;
    final List<Widget> rows = [];

    Widget row(String left, String right, {String? sub, Color? rc}) => Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(color: AppTheme.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppTheme.border)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(left, style: TextStyle(color: AppTheme.text, fontSize: 13)),
                    if (sub != null && sub.isNotEmpty)
                      Text(sub, style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(right, style: TextStyle(color: rc ?? AppTheme.accent, fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
        );
    Widget empty() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(tr('Ma\'lumot yo\'q'), style: TextStyle(color: AppTheme.textSoft)));

    switch (which) {
      case 'sales':
        title = tr('Savdo'); headerColor = AppTheme.accent; headerValue = '${_money(n(d['sales']))} ${tr('so\'m')}';
        // Savdo (jami) = Karta + Naqd + Qarz. Qarz KASSAGA TUSHMAYDI (debitorka) —
        // shuning uchun "Kassaga tushdi" (karta+naqd) alohida ko'rsatiladi: savdo≠kassa farqi = qarz.
        rows.add(row(tr('Karta'), _money(n(pay['card'])), rc: Colors.blue));
        rows.add(row(tr('Naqd'), _money(n(pay['cash'])), rc: Colors.green));
        rows.add(row(tr('Qarz (kassaga tushmadi)'), _money(n(pay['debt'])), rc: Colors.deepOrange));
        rows.add(row(tr('Kassaga tushdi (karta+naqd)'), _money(n(pay['card']) + n(pay['cash'])), rc: AppTheme.accent));
        final top = (d['top_items'] as List?) ?? [];
        if (top.isNotEmpty) {
          rows.add(_detailSub(tr('Eng ko\'p sotilgan')));
          for (final t in top) {
            final m = t as Map;
            rows.add(row(m['name']?.toString() ?? '', _money(n(m['amount'])), sub: '${(m['qty'] as num?)?.toInt() ?? 0} ${tr('ta')}'));
          }
        }
        break;
      case 'expenses':
        title = tr('Harajat'); headerColor = Colors.red; headerValue = '${_money(n(d['expenses']))} ${tr('so\'m')}';
        final list = (d['expenses_list'] as List?) ?? [];
        for (final e in list) {
          final m = e as Map;
          final notK = m['from_kassa'] == false;
          final mtd = m['method'] == 'card' ? tr('Karta') : tr('Naqd');
          final cat = tr(m['type_name']?.toString() ?? '');
          final nm = m['name']?.toString() ?? '';
          rows.add(row(nm.isEmpty ? cat : '$cat  •  $nm', '-${_money(n(m['amount']))}',
              sub: '$mtd${notK ? ' • ${tr('Boshqa joydan')}' : ''} • ${m['dt'] ?? ''}', rc: Colors.red));
        }
        if (list.isEmpty) rows.add(empty());
        break;
      case 'profit':
        // Foyda = Savdo (qarz ham daromad) - Harajat. Kassaga tushgan pul ALOHIDA ko'rsatiladi.
        title = tr('Sof foyda'); headerColor = Colors.green; headerValue = '${_money(n(d['profit']))} ${tr('so\'m')}';
        rows.add(row(tr('Savdo (qarz bilan)'), _money(n(d['sales'])), rc: AppTheme.accent));
        rows.add(row(tr('Harajat'), '-${_money(n(d['expenses']))}', rc: Colors.red));
        rows.add(row(tr('Sof foyda'), _money(n(d['profit'])), rc: Colors.green));
        rows.add(_detailSub(tr('Kassa / debitorka')));
        rows.add(row(tr('Kassaga tushdi (karta+naqd)'), _money(n(d['received'])), rc: Colors.blue));
        rows.add(row(tr('Qarz (kassaga tushmadi)'), _money(n(pay['debt'])), rc: Colors.deepOrange));
        rows.add(_detailSub(tr('Ma\'lumot uchun')));
        rows.add(row(tr('Tannarx (COGS)'), _money(n(d['cogs'])), rc: Colors.orange));
        rows.add(row(tr('Valovaya foyda (savdo-COGS)'), _money(n(d['gross_profit'])), rc: Colors.teal));
        break;
      case 'debt':
        title = tr('Qarz'); headerColor = Colors.deepOrange; headerValue = '${_money(n(pay['debt']))} ${tr('so\'m')}';
        final list = (d['debtors'] as List?) ?? [];
        for (final e in list) {
          final m = e as Map;
          final nm = (m['debtor_name']?.toString().isNotEmpty == true) ? m['debtor_name'].toString() : tr('Noma\'lum');
          rows.add(row(nm, _money(n(m['amount'])), sub: '#${m['id']} • ${m['dt'] ?? ''}', rc: Colors.deepOrange));
        }
        if (list.isEmpty) rows.add(empty());
        break;
      case 'discount':
        title = tr('Chegirma'); headerColor = Colors.purple; headerValue = '${_money(n(d['discount_total']))} ${tr('so\'m')}';
        final list = (d['discounted_orders'] as List?) ?? [];
        for (final e in list) {
          final m = e as Map;
          final reason = (m['discount_reason']?.toString().isNotEmpty == true) ? m['discount_reason'].toString() : tr('Sababsiz');
          rows.add(row('#${m['id']}  •  $reason', '-${_money(n(m['discount']))}',
              sub: '${tr('Chegirma')} ${n(m['discount_percent']).toStringAsFixed(0)}% • ${tr('Yakuniy')}: ${_money(n(m['final_amount']))} • ${m['dt'] ?? ''}', rc: Colors.purple));
        }
        if (list.isEmpty) rows.add(empty());
        break;
      case 'orders':
        title = tr('Zakazlar'); headerColor = AppTheme.text; headerValue = '${(d['orders_count'] as num?)?.toInt() ?? 0} ${tr('ta')}';
        final list = (d['orders_list'] as List?) ?? [];
        for (final e in list) {
          final m = e as Map;
          final pm = (n(m['paid_card']) > 0 && n(m['paid_cash']) > 0)
              ? tr('aralash')
              : n(m['paid_card']) > 0 ? tr('Karta') : n(m['paid_debt']) > 0 ? tr('Qarz') : tr('Naqd');
          rows.add(row('#${m['id']}  •  ${m['waiter'] ?? ''}', _money(n(m['amount'])), sub: '$pm • ${m['dt'] ?? ''}'));
        }
        if (list.isEmpty) rows.add(empty());
        break;
      case 'card':
        title = tr('Karta'); headerColor = Colors.blue; headerValue = '${_money(n(pay['card']))} ${tr('so\'m')}';
        final list = ((d['orders_list'] as List?) ?? []).where((e) => n((e as Map)['paid_card']) > 0).toList();
        for (final e in list) {
          final m = e as Map;
          rows.add(row('#${m['id']}  •  ${m['waiter'] ?? ''}', _money(n(m['paid_card'])), sub: m['dt']?.toString(), rc: Colors.blue));
        }
        if (list.isEmpty) rows.add(empty());
        break;
      case 'cash':
        title = tr('Naqd'); headerColor = Colors.green; headerValue = '${_money(n(pay['cash']))} ${tr('so\'m')}';
        final list = ((d['orders_list'] as List?) ?? []).where((e) {
          final m = e as Map;
          return n(m['paid_cash']) > 0 || (n(m['paid_card']) == 0 && n(m['paid_cash']) == 0 && n(m['paid_debt']) == 0);
        }).toList();
        for (final e in list) {
          final m = e as Map;
          final amt = n(m['paid_cash']) > 0 ? n(m['paid_cash']) : n(m['amount']);
          rows.add(row('#${m['id']}  •  ${m['waiter'] ?? ''}', _money(amt), sub: m['dt']?.toString(), rc: Colors.green));
        }
        if (list.isEmpty) rows.add(empty());
        break;
      case 'avg':
        title = tr('O\'rtacha chek'); headerColor = AppTheme.text; headerValue = '${_money(n(d['avg_check']))} ${tr('so\'m')}';
        rows.add(row(tr('Savdo'), _money(n(d['sales'])), rc: AppTheme.accent));
        rows.add(row(tr('Zakazlar'), '${(d['orders_count'] as num?)?.toInt() ?? 0} ${tr('ta')}'));
        rows.add(row(tr('O\'rtacha chek'), _money(n(d['avg_check']))));
        break;
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: AppTheme.textSoft, fontSize: 13)),
            const SizedBox(height: 2),
            Text(headerValue, style: TextStyle(color: headerColor, fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: rows.isEmpty
              ? empty()
              : SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Yopish'), style: TextStyle(color: AppTheme.accent))),
        ],
      ),
    );
  }

  Future<void> _generatePdf() async {
    final d = _fin;
    if (d == null) return;
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();
    double n(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0;
    final pay = (d['payments'] as Map?) ?? {};
    final top = (d['top_items'] as List?) ?? [];
    final waiters = (d['waiter_sales'] as List?) ?? [];

    pw.Widget cell(String t, {pw.TextStyle? st, pw.Alignment? a}) => pw.Container(
          alignment: a ?? pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: pw.Text(t, style: st ?? pw.TextStyle(font: font, fontSize: 9)),
        );
    final hStyle = pw.TextStyle(font: fontBold, fontSize: 9);

    pw.Widget kv(String k, String v) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(k, style: pw.TextStyle(font: font, fontSize: 11)),
            pw.Text(v, style: pw.TextStyle(font: fontBold, fontSize: 11)),
          ]),
        );

    final pdf = pw.Document();
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (ctx) => [
        pw.Text('${tr('Hisobot')} — $_periodLabel', style: pw.TextStyle(font: fontBold, fontSize: 16)),
        pw.SizedBox(height: 4),
        pw.Text('${tr('Davr')}: ${d['from']} — ${d['to']}',
            style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700)),
        pw.SizedBox(height: 12),
        kv(tr('Savdo'), '${_money(n(d['sales']))} ${tr('so\'m')}'),
        kv(tr('Tannarx (COGS)'), '${_money(n(d['cogs']))} ${tr('so\'m')}'),
        kv(tr('Valovaya foyda'), '${_money(n(d['gross_profit']))} ${tr('so\'m')}'),
        kv(tr('Harajat'), '${_money(n(d['expenses']))} ${tr('so\'m')}'),
        kv(tr('Sof foyda'), '${_money(n(d['profit']))} ${tr('so\'m')}'),
        pw.Divider(color: PdfColors.grey400),
        kv(tr('Karta'), '${_money(n(pay['card']))} ${tr('so\'m')}'),
        kv(tr('Naqd'), '${_money(n(pay['cash']))} ${tr('so\'m')}'),
        kv(tr('Qarz'), '${_money(n(pay['debt']))} ${tr('so\'m')}'),
        pw.Divider(color: PdfColors.grey400),
        kv(tr('Zakazlar'), '${(d['orders_count'] as num?)?.toInt() ?? 0}'),
        kv(tr('O\'rtacha chek'), '${_money(n(d['avg_check']))} ${tr('so\'m')}'),
        kv(tr('Chegirma'), '${_money(n(d['discount_total']))} ${tr('so\'m')}'),
        pw.SizedBox(height: 14),
        pw.Text(tr('Eng ko\'p sotilgan'), style: pw.TextStyle(font: fontBold, fontSize: 12)),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: const {0: pw.FlexColumnWidth(4), 1: pw.FlexColumnWidth(1.3), 2: pw.FlexColumnWidth(2)},
          children: [
            pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [
              cell(tr('Nomi'), st: hStyle),
              cell(tr('Soni'), st: hStyle, a: pw.Alignment.centerRight),
              cell(tr('Savdo'), st: hStyle, a: pw.Alignment.centerRight),
            ]),
            ...top.map((t) {
              final mp = t as Map<String, dynamic>;
              return pw.TableRow(children: [
                cell(mp['name']?.toString() ?? ''),
                cell('${(mp['qty'] as num?)?.toInt() ?? 0}', a: pw.Alignment.centerRight),
                cell(_money(n(mp['amount'])), a: pw.Alignment.centerRight),
              ]);
            }),
          ],
        ),
        pw.SizedBox(height: 14),
        pw.Text(tr('Ofitsantlar reytingi'), style: pw.TextStyle(font: fontBold, fontSize: 12)),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: const {0: pw.FlexColumnWidth(4), 1: pw.FlexColumnWidth(1.3), 2: pw.FlexColumnWidth(2)},
          children: [
            pw.TableRow(decoration: const pw.BoxDecoration(color: PdfColors.grey200), children: [
              cell(tr('Xodim'), st: hStyle),
              cell(tr('Zakazlar'), st: hStyle, a: pw.Alignment.centerRight),
              cell(tr('Savdo'), st: hStyle, a: pw.Alignment.centerRight),
            ]),
            ...waiters.map((w) {
              final mp = w as Map<String, dynamic>;
              return pw.TableRow(children: [
                cell(mp['full_name']?.toString() ?? ''),
                cell('${(mp['orders'] as num?)?.toInt() ?? 0}', a: pw.Alignment.centerRight),
                cell(_money(n(mp['sales'])), a: pw.Alignment.centerRight),
              ]);
            }),
          ],
        ),
      ],
    ));

    final bytes = await pdf.save();
    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'hisobot_${_period}_${d['from']}.pdf';
    final filePath = '${dir.path}/$fileName';
    await File(filePath).writeAsBytes(bytes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${tr('PDF saqlandi')}: $filePath'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
      ));
    }
    await OpenFilex.open(filePath);
  }
}

// ===== INVENTARIZATSIYA BO'LIMI =====
class InventorySection extends StatefulWidget {
  const InventorySection({super.key});

  @override
  State<InventorySection> createState() => _InventorySectionState();
}

class _InventorySectionState extends State<InventorySection> {
  List<dynamic> _inventories = [];
  List<dynamic> _warehouses = [];
  int? _selectedWarehouseId;
  bool _tablewareMode = false; // true bo'lsa idishlar inventarizatsiyasi
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    setState(() => _isLoading = true);
    try {
      final whs = await ApiService.get(AppConstants.warehouses);
      final warehouses = whs is List ? whs : [];
      _warehouses = warehouses;
      _selectedWarehouseId = warehouses.isNotEmpty ? warehouses.first['id'] as int : null;
    } catch (_) {}
    await _loadInventories();
  }

  Future<void> _loadInventories() async {
    setState(() => _isLoading = true);
    try {
      final String endpoint;
      if (_tablewareMode) {
        endpoint = '${AppConstants.inventory}?type=tableware';
      } else {
        endpoint = _selectedWarehouseId != null
            ? '${AppConstants.inventory}?type=ingredient&warehouse_id=$_selectedWarehouseId'
            : '${AppConstants.inventory}?type=ingredient';
      }
      final data = await ApiService.get(endpoint);
      setState(() {
        _inventories = data is List ? data : [];
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectWarehouse(int id) async {
    if (!_tablewareMode && _selectedWarehouseId == id) return;
    setState(() {
      _tablewareMode = false;
      _selectedWarehouseId = id;
    });
    await _loadInventories();
  }

  Future<void> _selectTableware() async {
    if (_tablewareMode) return;
    setState(() => _tablewareMode = true);
    await _loadInventories();
  }

  Future<void> _createInventory() async {
    if (!_tablewareMode && _selectedWarehouseId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Avval sklad tanlang!'))),
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id') ?? 1;
    final body = <String, dynamic>{'created_by': userId};
    if (_tablewareMode) {
      body['type'] = 'tableware';
    } else {
      body['warehouse_id'] = _selectedWarehouseId;
    }
    await ApiService.post(AppConstants.inventory, body);
    _loadInventories();
  }

  // Sklad tanlash chip qatori (Sklad bo'limidagi kabi)
  Widget _buildWarehouseSelector() {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          ..._warehouses.map((w) {
            final id = w['id'] as int;
            final selected = !_tablewareMode && id == _selectedWarehouseId;
            return _buildChip(
              label: w['name']?.toString() ?? '',
              icon: Icons.warehouse,
              selected: selected,
              onTap: () => _selectWarehouse(id),
            );
          }),
          // Idishlar (idish-tovoq) inventarizatsiyasi
          _buildChip(
            label: tr('Idishlar'),
            icon: Icons.restaurant,
            selected: _tablewareMode,
            onTap: _selectTableware,
          ),
        ],
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppTheme.accent : AppTheme.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppTheme.accent : AppTheme.textSoft.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: selected ? AppTheme.text : AppTheme.textSoft),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: selected ? AppTheme.text : AppTheme.textSoft,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Column(
        children: [
          _buildWarehouseSelector(),
          // Idishlar rejimida — katalogni boshqarish tugmasi
          if (_tablewareMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TablewareCatalogScreen()),
                    );
                    _loadInventories();
                  },
                  icon: Icon(Icons.list_alt, color: AppTheme.accent),
                  label: Text(
                    tr('Idishlar ro\'yxati'),
                    style: TextStyle(color: AppTheme.accent),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppTheme.accent),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
          Expanded(
            child: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : _inventories.isEmpty
              ? Center(
                  child: Text(tr('Inventarizatsiya yo\'q'), style: TextStyle(color: AppTheme.textSoft, fontSize: 16)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _inventories.length,
                  itemBuilder: (context, index) {
                    final inv = _inventories[index];
                    final isClosed = inv['status'] == 'closed';
                    return GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => InventoryDetailScreen(
                            inventoryId: inv['id'],
                            date: inv['check_date'].toString(),
                          ),
                        ),
                      ).then((_) => _loadInventories()),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isClosed ? Colors.green : AppTheme.accent,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isClosed ? Icons.check_circle : Icons.pending,
                              color: isClosed ? Colors.green : AppTheme.accent,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${tr('Inventarizatsiya')} #${inv['id']}',
                                    style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  Text(
                                    inv['check_date'].toString().substring(0, 10),
                                    style: TextStyle(color: AppTheme.textSoft),
                                  ),
                                  if ((inv['created_by_name'] ?? '').toString().isNotEmpty)
                                    Text(
                                      inv['created_by_name'].toString(),
                                      style: TextStyle(color: AppTheme.textSoft, fontSize: 12),
                                    ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isClosed
                                    ? Colors.green.withValues(alpha: 0.2)
                                    : AppTheme.accent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isClosed ? tr('Yakunlangan') : tr('Ochiq'),
                                style: TextStyle(
                                  color: isClosed ? Colors.green : AppTheme.accent,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.accent,
        onPressed: _createInventory,
        child: Icon(Icons.add, color: AppTheme.text),
      ),
    );
  }
}

// ===== IDISHLAR KATALOGI (idish-tovoq ro'yxatini boshqarish) =====
class TablewareCatalogScreen extends StatefulWidget {
  const TablewareCatalogScreen({super.key});

  @override
  State<TablewareCatalogScreen> createState() => _TablewareCatalogScreenState();
}

class _TablewareCatalogScreenState extends State<TablewareCatalogScreen> {
  List<dynamic> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.get(AppConstants.tableware);
      setState(() {
        _items = data is List ? data : [];
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _showForm({Map<String, dynamic>? item}) async {
    final isEdit = item != null;
    final nameCtrl = TextEditingController(text: item?['name']?.toString() ?? '');
    final unitCtrl = TextEditingController(text: item?['unit']?.toString() ?? 'dona');
    final qtyCtrl = TextEditingController(
      text: item != null ? (double.tryParse(item['quantity'].toString()) ?? 0).toString() : '0',
    );
    final priceCtrl = TextEditingController(
      text: item != null ? (double.tryParse(item['price'].toString()) ?? 0).toStringAsFixed(0) : '0',
    );

    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: AppTheme.textSoft),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.textSoft)),
          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.accent)),
        );

    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(
          isEdit ? tr('Idishni tahrirlash') : tr('Yangi idish'),
          style: TextStyle(color: AppTheme.text),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, style: TextStyle(color: AppTheme.text), decoration: deco(tr('Nomi (masalan: Piola)'))),
              const SizedBox(height: 12),
              TextField(controller: unitCtrl, style: TextStyle(color: AppTheme.text), decoration: deco(tr('O\'lchov (dona/komplekt)'))),
              const SizedBox(height: 12),
              TextField(controller: qtyCtrl, style: TextStyle(color: AppTheme.text), keyboardType: TextInputType.number, decoration: deco(tr('Mavjud soni'))),
              const SizedBox(height: 12),
              TextField(controller: priceCtrl, style: TextStyle(color: AppTheme.text), keyboardType: TextInputType.number, decoration: deco(tr('Bittasining narxi (so\'m)'))),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Saqlash'), style: TextStyle(color: AppTheme.text)),
          ),
        ],
      ),
    );

    if (saved != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Idish nomini kiriting!'))),
        );
      }
      return;
    }
    final body = {
      'name': name,
      'unit': unitCtrl.text.trim().isEmpty ? 'dona' : unitCtrl.text.trim(),
      'quantity': double.tryParse(qtyCtrl.text.trim()) ?? 0,
      'price': double.tryParse(priceCtrl.text.trim()) ?? 0,
    };
    try {
      if (isEdit) {
        await ApiService.put('${AppConstants.tableware}/${item['id']}', body);
      } else {
        await ApiService.post(AppConstants.tableware, body);
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('O\'chirish'), style: TextStyle(color: AppTheme.text)),
        content: Text(
          '${item['name']} ${tr('idishini ro\'yxatdan o\'chirasizmi?')}',
          style: TextStyle(color: AppTheme.textSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('O\'chirish'), style: TextStyle(color: AppTheme.text)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ApiService.delete('${AppConstants.tableware}/${item['id']}');
      _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.card,
        title: Text(tr('Idishlar ro\'yxati'), style: TextStyle(color: AppTheme.text)),
        iconTheme: IconThemeData(color: AppTheme.text),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : _items.isEmpty
              ? Center(
                  child: Text(tr('Idishlar yo\'q. "+" bilan qo\'shing.'),
                      style: TextStyle(color: AppTheme.textSoft, fontSize: 16)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final it = _items[index] as Map<String, dynamic>;
                    final qty = double.tryParse(it['quantity'].toString()) ?? 0;
                    final price = double.tryParse(it['price'].toString()) ?? 0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.textSoft.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.restaurant, color: AppTheme.accent),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(it['name']?.toString() ?? '',
                                    style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 15)),
                                const SizedBox(height: 2),
                                Text(
                                  '${qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 2)} ${it['unit'] ?? 'dona'}'
                                  '${price > 0 ? '  •  ${price.toStringAsFixed(0)} ${tr('so\'m')}/${tr('dona')}' : ''}',
                                  style: TextStyle(color: AppTheme.textSoft, fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.edit, color: AppTheme.textSoft, size: 20),
                            onPressed: () => _showForm(item: it),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete, color: Colors.red, size: 20),
                            onPressed: () => _delete(it),
                          ),
                        ],
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.accent,
        onPressed: () => _showForm(),
        child: Icon(Icons.add, color: AppTheme.text),
      ),
    );
  }
}

class InventoryDetailScreen extends StatefulWidget {
  final int inventoryId;
  final String date;

  const InventoryDetailScreen({super.key, required this.inventoryId, required this.date});

  @override
  State<InventoryDetailScreen> createState() => _InventoryDetailScreenState();
}

class _InventoryDetailScreenState extends State<InventoryDetailScreen> {
  List<dynamic> _items = [];
  bool _isLoading = true;
  final Map<int, TextEditingController> _controllers = {};
  final Set<String> _expandedCategories = {};

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.get('/inventory/${widget.inventoryId}/items');
      final items = data is List ? data : [];
      for (final item in items) {
        final id = item['id'] as int;
        if (!_controllers.containsKey(id)) {
          final isDona = item['unit'].toString() == 'dona';
          final qty = double.tryParse(item['actual_quantity'].toString()) ?? 0;
          _controllers[id] = TextEditingController(
            text: isDona ? qty.toInt().toString() : qty.toString(),
          );
        }
      }
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateItem(int itemId, String value) async {
    final qty = double.tryParse(value) ?? 0;
    await ApiService.put('/inventory/items/$itemId', {'actual_quantity': qty});
  }

  Future<void> _closeInventory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('Yakunlash'), style: TextStyle(color: AppTheme.text)),
        content: Text(
          tr('Inventarizatsiyani yakunlashni tasdiqlaysizmi?\nSklad yangilanadi.'),
          style: TextStyle(color: AppTheme.textSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Yakunlash'), style: TextStyle(color: AppTheme.text)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ApiService.put('/inventory/${widget.inventoryId}/close', {});
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _generatePdf() async {
    // Cyrillic uchun Google Fonts dan Noto Sans
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();

    final Map<String, List<dynamic>> grouped = {};
    for (final item in _items) {
      final cat = (item['category'] ?? tr('Boshqa')).toString();
      grouped.putIfAbsent(cat, () => []).add(item);
    }

    final List<Map<String, dynamic>> pdfShortages = [];
    final List<Map<String, dynamic>> pdfSurpluses = [];
    for (final item in _items) {
      final itemId = item['id'] as int;
      final expected = double.tryParse(item['expected_quantity'].toString()) ?? 0;
      final actualText = _controllers[itemId]?.text ?? item['actual_quantity'].toString();
      final actual = double.tryParse(actualText) ?? 0;
      final diff = actual - expected;
      final price = double.tryParse(item['price_per_unit']?.toString() ?? '0') ?? 0;
      if (diff < 0) {
        pdfShortages.add({
          'name': item['ingredient_name'].toString(),
          'unit': item['unit'].toString(),
          'diff': diff.abs(),
          'price': price,
          'loss': diff.abs() * price,
        });
      } else if (diff > 0) {
        pdfSurpluses.add({
          'name': item['ingredient_name'].toString(),
          'unit': item['unit'].toString(),
          'diff': diff,
          'price': price,
          'value': diff * price,
        });
      }
    }
    final pdfTotalLoss = pdfShortages.fold<double>(0, (sum, e) => sum + (e['loss'] as double));
    final pdfTotalSurplusValue = pdfSurpluses.fold<double>(0, (sum, e) => sum + (e['value'] as double));
    final pdfNet = pdfTotalSurplusValue - pdfTotalLoss; // manfiy => zarar, musbat => ortiqcha

    final date = widget.date.length >= 10 ? widget.date.substring(0, 10) : widget.date;

    pw.Widget cell(String text, {pw.TextStyle? style, PdfColor? bg}) {
      return pw.Container(
        color: bg,
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: pw.Text(text, style: style ?? pw.TextStyle(font: font, fontSize: 9)),
      );
    }

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (ctx) {
          final List<pw.Widget> content = [];

          content.add(pw.Text(
            '${tr('Inventarizatsiya hisoboti')} - $date',
            style: pw.TextStyle(font: fontBold, fontSize: 16),
          ));
          content.add(pw.SizedBox(height: 16));

          for (final entry in grouped.entries) {
            content.add(pw.Text(
              entry.key,
              style: pw.TextStyle(font: fontBold, fontSize: 12, color: PdfColors.red700),
            ));
            content.add(pw.SizedBox(height: 6));

            final headerStyle = pw.TextStyle(font: fontBold, fontSize: 9);
            content.add(pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(3.5),
                1: pw.FlexColumnWidth(1),
                2: pw.FlexColumnWidth(1.5),
                3: pw.FlexColumnWidth(1.5),
                4: pw.FlexColumnWidth(1.5),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    cell(tr('Mahsulot nomi'), style: headerStyle),
                    cell(tr('O\'lchov'), style: headerStyle),
                    cell(tr('Kutilgan'), style: headerStyle),
                    cell(tr('Haqiqiy'), style: headerStyle),
                    cell(tr('Farq'), style: headerStyle),
                  ],
                ),
                ...entry.value.map((item) {
                  final itemId = item['id'] as int;
                  final expected = double.tryParse(item['expected_quantity'].toString()) ?? 0;
                  final actualText = _controllers[itemId]?.text ?? item['actual_quantity'].toString();
                  final actual = double.tryParse(actualText) ?? 0;
                  final diff = actual - expected;
                  final diffColor = diff < 0 ? PdfColors.red : (diff > 0 ? PdfColors.green800 : PdfColors.black);
                  final diffStr = diff > 0 ? '+${_fmt(diff)}' : _fmt(diff);
                  return pw.TableRow(
                    children: [
                      cell(item['ingredient_name'].toString()),
                      cell(item['unit'].toString()),
                      cell(_fmt(expected)),
                      cell(_fmt(actual)),
                      cell(diffStr, style: pw.TextStyle(font: font, fontSize: 9, color: diffColor)),
                    ],
                  );
                }),
              ],
            ));
            content.add(pw.SizedBox(height: 14));
          }

          // Kamomadlar bo'limi
          if (pdfShortages.isNotEmpty) {
            content.add(pw.SizedBox(height: 16));
            content.add(pw.Text(
              tr('Kamomadlar'),
              style: pw.TextStyle(font: fontBold, fontSize: 13, color: PdfColors.red),
            ));
            content.add(pw.SizedBox(height: 6));
            final hStyle = pw.TextStyle(font: fontBold, fontSize: 9);
            content.add(pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(3),
                1: pw.FlexColumnWidth(1),
                2: pw.FlexColumnWidth(1.5),
                3: pw.FlexColumnWidth(2),
                4: pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.red50),
                  children: [
                    cell(tr('Mahsulot nomi'), style: hStyle),
                    cell(tr('Birlik'), style: hStyle),
                    cell(tr('Kamomad'), style: hStyle),
                    cell(tr('Narxi'), style: hStyle),
                    cell(tr('Zarar'), style: hStyle),
                  ],
                ),
                ...pdfShortages.map((s) => pw.TableRow(
                  children: [
                    cell(s['name'] as String),
                    cell(s['unit'] as String),
                    cell(_fmt(s['diff'] as double)),
                    cell('${_fmtMoney(s['price'] as double)} ${tr('so\'m')}'),
                    cell(
                      '${_fmtMoney(s['loss'] as double)} ${tr('so\'m')}',
                      style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.red),
                    ),
                  ],
                )),
              ],
            ));
          }

          // Ortiqchalar bo'limi
          if (pdfSurpluses.isNotEmpty) {
            content.add(pw.SizedBox(height: 14));
            content.add(pw.Text(
              tr('Ortiqchalar'),
              style: pw.TextStyle(font: fontBold, fontSize: 13, color: PdfColors.green800),
            ));
            content.add(pw.SizedBox(height: 6));
            final hStyle = pw.TextStyle(font: fontBold, fontSize: 9);
            content.add(pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(3.5),
                1: pw.FlexColumnWidth(1),
                2: pw.FlexColumnWidth(1.5),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.green50),
                  children: [
                    cell(tr('Mahsulot nomi'), style: hStyle),
                    cell(tr('Birlik'), style: hStyle),
                    cell(tr('Ortiqcha'), style: hStyle),
                  ],
                ),
                ...pdfSurpluses.map((s) => pw.TableRow(
                  children: [
                    cell(s['name'] as String),
                    cell(s['unit'] as String),
                    cell(
                      '+${_fmt(s['diff'] as double)}',
                      style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.green800),
                    ),
                  ],
                )),
              ],
            ));
          }

          // Xulosa (summa) — har doim ko'rinadi
          final netIsLoss = pdfNet < 0;
          final netColor = pdfNet < 0
              ? PdfColors.red
              : (pdfNet > 0 ? PdfColors.green800 : PdfColors.black);

          pw.Widget sumRow(String label, String value, {PdfColor? color, bool bold = false}) {
            return pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(label, style: pw.TextStyle(font: bold ? fontBold : font, fontSize: 11, color: color)),
                  pw.Text(value, style: pw.TextStyle(font: bold ? fontBold : font, fontSize: 11, color: color)),
                ],
              ),
            );
          }

          content.add(pw.SizedBox(height: 18));
          content.add(pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey600, width: 1),
              color: PdfColors.grey100,
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text(tr('Xulosa'),
                    style: pw.TextStyle(font: fontBold, fontSize: 13)),
                pw.SizedBox(height: 8),
                sumRow(tr('Kamomad (zarar):'), '${_fmtMoney(pdfTotalLoss)} ${tr('so\'m')}',
                    color: PdfColors.red),
                sumRow(tr('Ortiqcha (qiymati):'), '${_fmtMoney(pdfTotalSurplusValue)} ${tr('so\'m')}',
                    color: PdfColors.green800),
                pw.Divider(color: PdfColors.grey500, height: 12),
                sumRow(
                  netIsLoss ? tr('Sof zarar:') : tr('Sof natija:'),
                  '${_fmtMoney(pdfNet.abs())} ${tr('so\'m')}',
                  color: netColor,
                  bold: true,
                ),
              ],
            ),
          ));

          return content;
        },
      ),
    );

    final bytes = await pdf.save();
    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'inventarizatsiya_${widget.inventoryId}_$date.pdf';
    final filePath = '${dir.path}/$fileName';
    final file = File(filePath);
    await file.writeAsBytes(bytes);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${tr('PDF saqlandi')}: $filePath'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    }

    await OpenFilex.open(filePath);
  }

  String _fmt(double v) {
    return v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
  }

  String _fmtMoney(double v) {
    return v.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]} ');
  }

  Widget _buildSummary() {
    final List<Map<String, dynamic>> shortages = [];
    final List<Map<String, dynamic>> surpluses = [];
    for (final item in _items) {
      final itemId = item['id'] as int;
      final expected = double.tryParse(item['expected_quantity'].toString()) ?? 0;
      final actualText = _controllers[itemId]?.text ?? item['actual_quantity'].toString();
      final actual = double.tryParse(actualText) ?? 0;
      final diff = actual - expected;
      final price = double.tryParse(item['price_per_unit']?.toString() ?? '0') ?? 0;
      if (diff < 0) {
        shortages.add({
          'name': item['ingredient_name'].toString(),
          'unit': item['unit'].toString(),
          'diff': diff.abs(),
          'price': price,
          'loss': diff.abs() * price,
        });
      } else if (diff > 0) {
        surpluses.add({
          'name': item['ingredient_name'].toString(),
          'unit': item['unit'].toString(),
          'diff': diff,
        });
      }
    }
    final totalLoss = shortages.fold<double>(0, (sum, e) => sum + (e['loss'] as double));

    if (shortages.isEmpty && surpluses.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Divider(color: AppTheme.textSoft),
        const SizedBox(height: 8),
        Text(
          tr('Umumiy hisobot'),
          style: TextStyle(color: AppTheme.text, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        if (shortages.isNotEmpty) ...[
          Text(tr('Kamomadlar'),
              style: TextStyle(color: Colors.red, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...shortages.map((s) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s['name'] as String,
                              style: TextStyle(
                                  color: AppTheme.text, fontWeight: FontWeight.bold)),
                          Text('${_fmt(s['diff'] as double)} ${s['unit']} ${tr('kamomad')}',
                              style: TextStyle(color: Colors.red, fontSize: 12)),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text("${_fmtMoney(s['price'] as double)} ${tr('so\'m')}/${s['unit']}",
                            style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
                        Text("${_fmtMoney(s['loss'] as double)} ${tr('so\'m')}",
                            style: TextStyle(
                                color: Colors.red, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              )),
          const SizedBox(height: 8),
        ],
        if (surpluses.isNotEmpty) ...[
          Text(tr('Ortiqchalar'),
              style: TextStyle(color: Colors.green, fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...surpluses.map((s) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(s['name'] as String,
                          style: TextStyle(
                              color: AppTheme.text, fontWeight: FontWeight.bold)),
                    ),
                    Text('+${_fmt(s['diff'] as double)} ${s['unit']}',
                        style: TextStyle(
                            color: Colors.green, fontWeight: FontWeight.bold)),
                  ],
                ),
              )),
          const SizedBox(height: 8),
        ],
        if (totalLoss > 0)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red),
            ),
            child: Text(
              "${tr('Jami zarar')}: ${_fmtMoney(totalLoss)} ${tr('so\'m')}",
              style: TextStyle(
                  color: Colors.red, fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    const catOrder = ['Продукция', 'Десерт', 'Холодные напитки', 'Ингредиенты', 'П/Ф'];
    final Map<String, List<dynamic>> grouped = {};
    for (final item in _items) {
      final cat = (item['category'] ?? tr('Boshqa')).toString();
      grouped.putIfAbsent(cat, () => []).add(item);
    }
    final sortedEntries = grouped.entries.toList()
      ..sort((a, b) {
        final ai = catOrder.indexOf(a.key);
        final bi = catOrder.indexOf(b.key);
        if (ai == -1 && bi == -1) return a.key.compareTo(b.key);
        if (ai == -1) return 1;
        if (bi == -1) return -1;
        return ai.compareTo(bi);
      });

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.card,
        title: Text(
          '${tr('Inventarizatsiya')} ${widget.date.length >= 10 ? widget.date.substring(0, 10) : widget.date}',
          style: TextStyle(color: AppTheme.text),
        ),
        iconTheme: IconThemeData(color: AppTheme.text),
        actions: [
          IconButton(
            icon: Icon(Icons.picture_as_pdf, color: Colors.orange),
            tooltip: tr('PDF hisobot'),
            onPressed: _generatePdf,
          ),
          TextButton(
            onPressed: _closeInventory,
            child: Text(
              tr('Yakunlash'),
              style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ...sortedEntries.map((entry) {
                  final cat = entry.key;
                  final items = entry.value;
                  final isExpanded = _expandedCategories.contains(cat);
                  return Column(
                    children: [
                      GestureDetector(
                        onTap: () => setState(() {
                          if (isExpanded) {
                            _expandedCategories.remove(cat);
                          } else {
                            _expandedCategories.add(cat);
                          }
                        }),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppTheme.card,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '$cat (${items.length})',
                                  style: TextStyle(
                                    color: AppTheme.accent,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Icon(
                                isExpanded ? Icons.expand_more : Icons.chevron_right,
                                color: AppTheme.accent,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (isExpanded)
                        ...items.map((item) {
                          final expected = double.tryParse(item['expected_quantity'].toString()) ?? 0;
                          final actual = double.tryParse(item['actual_quantity'].toString()) ?? 0;
                          final diff = actual - expected;
                          final itemId = item['id'] as int;
                          final isDona = item['unit'].toString() == 'dona';
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.accentSoft,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['ingredient_name'].toString(),
                                        style: TextStyle(
                                            color: AppTheme.text, fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        '${tr('Kutilgan')}: ${_fmt(expected)} ${item['unit']}',
                                        style: TextStyle(color: AppTheme.textSoft, fontSize: 12),
                                      ),
                                      if (diff != 0)
                                        Text(
                                          diff > 0
                                              ? '+${_fmt(diff)} ${item['unit']} ${tr('ortiqcha')}'
                                              : '${_fmt(diff)} ${item['unit']} ${tr('kamomad')}',
                                          style: TextStyle(
                                            color: diff > 0 ? Colors.green.shade700 : Colors.red,
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 110,
                                  child: TextField(
                                    controller: _controllers[itemId],
                                    keyboardType: isDona
                                        ? TextInputType.number
                                        : const TextInputType.numberWithOptions(decimal: true),
                                    style: TextStyle(color: AppTheme.text),
                                    onTap: () => _controllers[itemId]?.clear(),
                                    decoration: InputDecoration(
                                      suffix: Text(
                                        item['unit'].toString(),
                                        style: TextStyle(color: AppTheme.textSoft, fontSize: 12),
                                      ),
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8)),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(color: AppTheme.textSoft),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide:
                                            BorderSide(color: AppTheme.accent),
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 6),
                                    ),
                                    onSubmitted: (v) => _updateItem(itemId, v),
                                    onEditingComplete: () =>
                                        _updateItem(itemId, _controllers[itemId]!.text),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      const SizedBox(height: 8),
                    ],
                  );
                }),
                _buildSummary(),
              ],
            ),
    );
  }
}

// ===== STOLLAR (FLOOR-PLAN) BO'LIMI =====
// Admin xona va stollarni surib joylashtiradi. Koordinatalar NISBIY (0..1).
class FloorPlanSection extends StatefulWidget {
  const FloorPlanSection({super.key});

  @override
  State<FloorPlanSection> createState() => _FloorPlanSectionState();
}

class _FloorPlanSectionState extends State<FloorPlanSection> {
  static Color get _card => AppTheme.card;
  static Color get _accent => AppTheme.accent;
  static Color get _panel => AppTheme.accentSoft;

  List<dynamic> _rooms = [];
  List<dynamic> _tables = [];
  bool _loading = true;
  int? _openRoomId; // null = bino ko'rinishi, aks holda xona ichi

  @override
  void initState() {
    super.initState();
    _load();
  }

  double _d(dynamic v, double def) => double.tryParse(v?.toString() ?? '') ?? def;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rooms = await ApiService.get(AppConstants.rooms);
      final tables = await ApiService.get(AppConstants.roomTables);
      setState(() {
        _rooms = rooms is List ? rooms : [];
        _tables = tables is List ? tables : [];
      });
    } catch (e) {
      debugPrint('Floor-plan yuklash xatosi: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  // ─── XONA API ──────────────────────────────────────────────────────────────

  Future<void> _saveRoomPos(Map<String, dynamic> room) async {
    try {
      await ApiService.put('${AppConstants.rooms}/${room['id']}', {
        'pos_x': room['pos_x'],
        'pos_y': room['pos_y'],
      });
    } catch (e) {
      _snack('${tr('Xona saqlanmadi')}: $e', Colors.red);
    }
  }

  Future<void> _createRoom() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text(tr('Xona yaratish'), style: TextStyle(color: AppTheme.text)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: AppTheme.text),
          decoration: _dec(tr('Xona nomi / raqami'), Icons.meeting_room),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Yaratish'), style: TextStyle(color: AppTheme.onAccent)),
          ),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      try {
        await ApiService.post(AppConstants.rooms, {
          'name': ctrl.text.trim(),
          'pos_x': 0.4,
          'pos_y': 0.4,
        });
        await _load();
      } catch (e) {
        _snack('${tr('Xona yaratilmadi')}: $e', Colors.red);
      }
    }
  }

  Future<void> _deleteRoom(Map<String, dynamic> room) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text(tr("Xonani o'chirish"), style: TextStyle(color: AppTheme.text)),
        content: Text(
          "'${room['name']}' ${tr('xonasi va undagi BARCHA stollar o\'chiriladi. Davom etasizmi?')}",
          style: TextStyle(color: AppTheme.textSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr("O'chirish"), style: TextStyle(color: AppTheme.text)),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ApiService.delete('${AppConstants.rooms}/${room['id']}');
        await _load();
      } catch (e) {
        _snack("${tr('Xona o\'chmadi')}: $e", Colors.red);
      }
    }
  }

  Future<void> _renameRoom(Map<String, dynamic> room) async {
    final ctrl = TextEditingController(text: room['name']?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text(tr('Xona nomi'), style: TextStyle(color: AppTheme.text)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: TextStyle(color: AppTheme.text),
          decoration: _dec(tr('Xona nomi / raqami'), Icons.meeting_room),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Saqlash'), style: TextStyle(color: AppTheme.onAccent)),
          ),
        ],
      ),
    );
    if (ok == true && ctrl.text.trim().isNotEmpty) {
      try {
        await ApiService.put('${AppConstants.rooms}/${room['id']}', {'name': ctrl.text.trim()});
        await _load();
      } catch (e) {
        _snack('${tr('Saqlanmadi')}: $e', Colors.red);
      }
    }
  }

  // ─── STOL API ──────────────────────────────────────────────────────────────

  Future<void> _saveTablePos(Map<String, dynamic> table) async {
    try {
      await ApiService.put('${AppConstants.roomTables}/${table['id']}', {
        'pos_x': table['pos_x'],
        'pos_y': table['pos_y'],
      });
    } catch (e) {
      _snack('${tr('Stol saqlanmadi')}: $e', Colors.red);
    }
  }

  // Xona o'lchamini (width/height) + joyini saqlash (resize)
  Future<void> _saveRoomSize(Map<String, dynamic> room) async {
    try {
      await ApiService.put('${AppConstants.rooms}/${room['id']}', {
        'width': room['width'],
        'height': room['height'],
        'pos_x': room['pos_x'],
        'pos_y': room['pos_y'],
      });
    } catch (e) {
      _snack('${tr('Xona o\'lchami saqlanmadi')}: $e', Colors.red);
    }
  }

  // Stol o'lchamini o'zgartirish (0.6..2.0) — optimistik + saqlash
  Future<void> _setTableSize(Map<String, dynamic> table, double newSize) async {
    final s = newSize.clamp(0.6, 2.0);
    setState(() => table['table_size'] = s);
    try {
      await ApiService.put('${AppConstants.roomTables}/${table['id']}', {'table_size': s});
    } catch (e) {
      _snack('${tr('O\'lcham saqlanmadi')}: $e', Colors.red);
    }
  }

  Future<void> _setTableShape(Map<String, dynamic> table, String shape) async {
    setState(() => table['shape'] = shape);
    try {
      await ApiService.put('${AppConstants.roomTables}/${table['id']}', {'shape': shape});
    } catch (e) {
      _snack('${tr('Saqlanmadi')}: $e', Colors.red);
    }
  }

  Future<void> _createTable() async {
    final numberCtrl = TextEditingController();
    final seatsCtrl = TextEditingController(text: '4');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text(tr('Stol qo\'shish'), style: TextStyle(color: AppTheme.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: numberCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              style: TextStyle(color: AppTheme.text),
              decoration: _dec(tr('Stol raqami'), Icons.tag),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: seatsCtrl,
              keyboardType: TextInputType.number,
              style: TextStyle(color: AppTheme.text),
              decoration: _dec(tr('Necha kishilik'), Icons.event_seat),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Qo\'shish'), style: TextStyle(color: AppTheme.onAccent)),
          ),
        ],
      ),
    );
    if (ok == true && numberCtrl.text.trim().isNotEmpty) {
      try {
        await ApiService.post(AppConstants.roomTables, {
          'number': int.tryParse(numberCtrl.text.trim()),
          'seats': int.tryParse(seatsCtrl.text.trim()) ?? 4,
          'room_id': _openRoomId,
          'pos_x': 0.5,
          'pos_y': 0.5,
          'shape': 'rect',
        });
        await _load();
      } catch (e) {
        _snack('${tr('Stol qo\'shilmadi')}: $e', Colors.red);
      }
    }
  }

  Future<void> _editTable(Map<String, dynamic> table) async {
    final numberCtrl = TextEditingController(text: (table['number'] ?? '').toString());
    final seatsCtrl = TextEditingController(text: (table['seats'] ?? 4).toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text(tr('Stolni tahrirlash'), style: TextStyle(color: AppTheme.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: numberCtrl,
              keyboardType: TextInputType.number,
              style: TextStyle(color: AppTheme.text),
              decoration: _dec(tr('Stol raqami'), Icons.tag),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: seatsCtrl,
              keyboardType: TextInputType.number,
              style: TextStyle(color: AppTheme.text),
              decoration: _dec(tr('Necha kishilik'), Icons.event_seat),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Saqlash'), style: TextStyle(color: AppTheme.onAccent)),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await ApiService.put('${AppConstants.roomTables}/${table['id']}', {
          'number': int.tryParse(numberCtrl.text.trim()),
          'seats': int.tryParse(seatsCtrl.text.trim()) ?? 4,
        });
        await _load();
      } catch (e) {
        _snack('${tr('Saqlanmadi')}: $e', Colors.red);
      }
    }
  }

  Future<void> _deleteTable(Map<String, dynamic> table) async {
    try {
      await ApiService.delete('${AppConstants.roomTables}/${table['id']}');
      await _load();
    } catch (e) {
      _snack("${tr('Stol o\'chmadi')}: $e", Colors.red);
    }
  }

  void _tableMenu(Map<String, dynamic> table) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final size = (double.tryParse(table['table_size']?.toString() ?? '') ?? 1.0)
              .clamp(0.6, 2.0);
          Widget shapeChip(String val, String label) {
            final sel = (table['shape']?.toString() ?? 'rect') == val;
            return GestureDetector(
              onTap: () {
                _setTableShape(table, val);
                setSheet(() {});
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: sel ? _accent.withValues(alpha: 0.15) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: sel ? _accent : AppTheme.border),
                ),
                child: Text(label,
                    style: TextStyle(color: sel ? _accent : AppTheme.textSoft, fontWeight: sel ? FontWeight.bold : FontWeight.normal, fontSize: 12)),
              ),
            );
          }

          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('${tr('Stol')} ${table['number'] ?? ''}',
                      style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold)),
                ),
                // O'lcham stepper
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.aspect_ratio, color: _accent, size: 20),
                      const SizedBox(width: 12),
                      Text(tr("O'lcham"), style: TextStyle(color: AppTheme.text)),
                      const Spacer(),
                      _sizeBtn(Icons.remove, () {
                        _setTableSize(table, size - 0.2);
                        setSheet(() {});
                      }),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('${(size * 100).round()}%',
                            style: TextStyle(
                                color: AppTheme.text, fontWeight: FontWeight.bold)),
                      ),
                      _sizeBtn(Icons.add, () {
                        _setTableSize(table, size + 0.2);
                        setSheet(() {});
                      }),
                    ],
                  ),
                ),
                // Shakl
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Icon(Icons.crop_square, color: _accent, size: 20),
                      const SizedBox(width: 12),
                      Text(tr('Shakl'), style: TextStyle(color: AppTheme.text)),
                      const Spacer(),
                      shapeChip('rect', tr('To\'rtburchak')),
                      const SizedBox(width: 8),
                      shapeChip('circle', tr('Dumaloq')),
                    ],
                  ),
                ),
                Divider(color: AppTheme.border),
                ListTile(
                  leading: Icon(Icons.edit, color: _accent),
                  title: Text(tr('Tahrirlash (raqam / o\'rindiq)'),
                      style: TextStyle(color: AppTheme.text)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _editTable(table);
                  },
                ),
                ListTile(
                  leading: Icon(Icons.delete, color: Colors.red),
                  title: Text(tr("O'chirish"), style: TextStyle(color: AppTheme.text)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _deleteTable(table);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _sizeBtn(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(color: _accent, shape: BoxShape.circle),
        child: Icon(icon, color: AppTheme.onAccent, size: 20),
      ),
    );
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: AppTheme.textSoft),
        prefixIcon: Icon(icon, color: _accent),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppTheme.textSoft)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: _accent)),
      );

  // ─── BUILD ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: _accent));
    }
    return _openRoomId == null ? _buildBuilding() : _buildRoomInterior();
  }

  // KO'RINISH 1 — Bino
  Widget _buildBuilding() {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(tr('Xona: bosib kiring • ⋮ menyu (tahrir/o\'chirish) • suring'),
                style: TextStyle(color: AppTheme.textSoft, fontSize: 13)),
          ),
        ),
        Expanded(
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
                                    color: AppTheme.border,
                                    fontSize: 26,
                                    fontWeight: FontWeight.bold)),
                          ),
                          ..._rooms.map((room) => _roomFigure(room, w, h)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: Icon(Icons.add, color: AppTheme.onAccent),
              label: Text(tr('Xona yaratish'),
                  style: TextStyle(color: AppTheme.onAccent, fontWeight: FontWeight.bold)),
              onPressed: _createRoom,
            ),
          ),
        ),
      ],
    );
  }

  Widget _roomFigure(Map<String, dynamic> room, double W, double H) {
    final rw = _d(room['width'], 0.3).clamp(0.1, 1.0);
    final rh = _d(room['height'], 0.3).clamp(0.1, 1.0);
    final px = _d(room['pos_x'], 0.1).clamp(0.0, (1 - rw).clamp(0.0, 1.0));
    final py = _d(room['pos_y'], 0.1).clamp(0.0, (1 - rh).clamp(0.0, 1.0));
    final count = _tables.where((t) => t['room_id'] == room['id']).length;

    return Positioned(
      left: px * W,
      top: py * H,
      child: SizedBox(
        width: rw * W,
        height: rh * H,
        child: Stack(
          children: [
            // Asosiy xona — surish (drag) shu yerda
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _openRoomId = room['id'] as int),
                onLongPress: () => _roomMenu(room),
                onSecondaryTap: () => _roomMenu(room),
                onPanUpdate: (d) {
                  final curX = _d(room['pos_x'], 0.1);
                  final curY = _d(room['pos_y'], 0.1);
                  setState(() {
                    room['pos_x'] = ((curX * W + d.delta.dx) / W).clamp(0.0, (1 - rw).clamp(0.0, 1.0));
                    room['pos_y'] = ((curY * H + d.delta.dy) / H).clamp(0.0, (1 - rh).clamp(0.0, 1.0));
                  });
                },
                onPanEnd: (_) => _saveRoomPos(room),
                child: Container(
                  decoration: BoxDecoration(
                    color: _panel,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _accent.withValues(alpha: 0.7), width: 2),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 6, offset: const Offset(0, 3)),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.meeting_room, color: AppTheme.text, size: 22),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(room['name'].toString(),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 2),
                      Text('$count ${tr('stol')}', style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ),
            // Resize handle — pastki-o'ng burchak
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanUpdate: (d) {
                  final curW = _d(room['width'], 0.3);
                  final curH = _d(room['height'], 0.3);
                  setState(() {
                    room['width'] = ((curW * W + d.delta.dx) / W).clamp(0.1, 1.0);
                    room['height'] = ((curH * H + d.delta.dy) / H).clamp(0.1, 1.0);
                  });
                },
                onPanEnd: (_) => _saveRoomSize(room),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      bottomRight: Radius.circular(11),
                    ),
                  ),
                  child: Icon(Icons.open_in_full, color: AppTheme.onAccent, size: 15),
                ),
              ),
            ),
            // Menyu tugmasi — yuqori o'ng (nom tahrir / o'chirish)
            Positioned(
              right: 0,
              top: 0,
              child: GestureDetector(
                onTap: () => _roomMenu(room),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: _accent,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(11),
                      bottomLeft: Radius.circular(8),
                    ),
                  ),
                  child: Icon(Icons.more_vert, color: AppTheme.onAccent, size: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _roomMenu(Map<String, dynamic> room) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _card,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(room['name'].toString(),
                  style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: Icon(Icons.login, color: _accent),
              title: Text(tr('Ochish (stollar)'), style: TextStyle(color: AppTheme.text)),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _openRoomId = room['id'] as int);
              },
            ),
            ListTile(
              leading: Icon(Icons.edit, color: _accent),
              title: Text(tr('Nomini tahrirlash'), style: TextStyle(color: AppTheme.text)),
              onTap: () {
                Navigator.pop(ctx);
                _renameRoom(room);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete, color: Colors.red),
              title: Text(tr("O'chirish"), style: TextStyle(color: AppTheme.text)),
              onTap: () {
                Navigator.pop(ctx);
                _deleteRoom(room);
              },
            ),
          ],
        ),
      ),
    );
  }

  // KO'RINISH 2 — Xona ichi
  Widget _buildRoomInterior() {
    final room = _rooms.firstWhere(
      (r) => r['id'] == _openRoomId,
      orElse: () => null,
    );
    if (room == null) {
      // Xona o'chirilgan bo'lsa binoga qaytamiz
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _openRoomId = null);
      });
      return const SizedBox.shrink();
    }
    final tables = _tables.where((t) => t['room_id'] == _openRoomId).toList();
    // Xona canvas'i bino ichidagi nisbatiga mos (16:10 bino birligida)
    final roomAspect =
        ((_d(room['width'], 0.3) * 16) / (_d(room['height'], 0.3) * 10)).clamp(0.5, 4.0);

    return Column(
      children: [
        // Header: orqaga + nom
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 4),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: AppTheme.text),
                onPressed: () => setState(() => _openRoomId = null),
              ),
              Expanded(
                child: Text(room['name'].toString(),
                    style: TextStyle(color: AppTheme.text, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              Text(tr('Stolni bosing — shakl, o\'lcham, o\'chirish'),
                  style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
            ],
          ),
        ),
        Expanded(
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
                              child: Text(tr('Stol qo\'shing'),
                                  style: TextStyle(color: AppTheme.border, fontSize: 20)),
                            ),
                          ...tables.map((t) => _tableFigure(t, w, h)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: Icon(Icons.add, color: AppTheme.onAccent),
              label: Text(tr('Stol qo\'shish'),
                  style: TextStyle(color: AppTheme.onAccent, fontWeight: FontWeight.bold)),
              onPressed: _createTable,
            ),
          ),
        ),
      ],
    );
  }

  Widget _tableFigure(Map<String, dynamic> table, double W, double H) {
    final tSize = _d(table['table_size'], 1.0).clamp(0.6, 2.0);
    final isFree = (table['status'] ?? 'free') == 'free';
    final tableColor = isFree ? _accent : Colors.red; // band=qizil, bo'sh=accent
    final total = TableWithChairs.totalSize(TableWithChairs.defaultBase, tSize.toDouble());
    final seats = int.tryParse(table['seats']?.toString() ?? '') ?? 4;
    final px = _d(table['pos_x'], 0.5).clamp(0.0, 1.0);
    final py = _d(table['pos_y'], 0.5).clamp(0.0, 1.0);

    return Positioned(
      left: px * W - total / 2,
      top: py * H - total / 2,
      child: GestureDetector(
        onTap: () => _tableMenu(table),
        onLongPress: () => _tableMenu(table),
        onSecondaryTap: () => _tableMenu(table),
        onPanUpdate: (d) {
          final curX = _d(table['pos_x'], 0.5);
          final curY = _d(table['pos_y'], 0.5);
          setState(() {
            table['pos_x'] = ((curX * W + d.delta.dx) / W).clamp(0.0, 1.0);
            table['pos_y'] = ((curY * H + d.delta.dy) / H).clamp(0.0, 1.0);
          });
        },
        onPanEnd: (_) => _saveTablePos(table),
        child: TableWithChairs(
          number: '${table['number'] ?? ''}',
          seats: seats,
          tableSize: tSize.toDouble(),
          color: tableColor,
          shape: (table['shape']?.toString() == 'circle') ? 'circle' : 'rect',
        ),
      ),
    );
  }
}

// ===== ISH HAQI (PAYROLL) BO'LIMI =====
class PayrollSection extends StatefulWidget {
  const PayrollSection({super.key});
  @override
  State<PayrollSection> createState() => _PayrollSectionState();
}

class _PayrollSectionState extends State<PayrollSection> {
  bool _isLoading = true;
  late DateTime _month;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _load();
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  DateTime get _from => DateTime(_month.year, _month.month, 1);
  DateTime get _to => DateTime(_month.year, _month.month + 1, 0); // oyning oxirgi kuni

  bool get _isCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final data = await ApiService.get(
          '${AppConstants.payrollReport}?from=${_ymd(_from)}&to=${_ymd(_to)}');
      setState(() {
        _data = data is Map<String, dynamic> ? data : null;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _shiftMonth(int delta) {
    if (delta > 0 && _isCurrentMonth) return; // kelajakka o'tmaymiz
    setState(() => _month = DateTime(_month.year, _month.month + delta));
    _load();
  }

  static const List<String> _monthsUz = [
    'Yanvar', 'Fevral', 'Mart', 'Aprel', 'May', 'Iyun',
    'Iyul', 'Avgust', 'Sentabr', 'Oktabr', 'Noyabr', 'Dekabr'
  ];
  String get _monthLabel => '${tr(_monthsUz[_month.month - 1])} ${_month.year}';

  String _money(num v) {
    final neg = v < 0;
    final s = v.abs().toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return (neg ? '-' : '') + buf.toString();
  }

  String _fmtNum(num v) => v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  String _roleLabel(String role) {
    switch (role) {
      case 'admin': return tr('Admin');
      case 'waiter': return tr('Ofitsant');
      case 'chef': return tr('Oshpaz');
      case 'cashier': return tr('Kassir');
      case 'cleaner': return tr('Sanitarka');
      default: return role.isEmpty ? role : role[0].toUpperCase() + role.substring(1);
    }
  }

  String _salaryTypeLabel(String t) {
    switch (t) {
      case 'monthly': return tr('Oylik');
      case 'daily': return tr('Kunlik');
      case 'hourly': return tr('Soatlik');
      case 'percent': return tr('Savdodan foiz (%)');
      case 'percent_total': return tr('Jami tushumdan foiz (%)');
      case 'piece': return tr('Dona uchun (sdelnaya)');
      default: return t;
    }
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'waiter': return Colors.blue;
      case 'chef': return Colors.orange;
      case 'cashier': return Colors.teal;
      case 'cleaner': return Colors.purple;
      case 'admin': return AppTheme.accent;
      default: return AppTheme.textSoft;
    }
  }

  // Hisob-kitob asosi (formula) matni
  String _basis(Map<String, dynamic> s) {
    final type = s['salary_type']?.toString() ?? '';
    final val = double.tryParse(s['salary_value']?.toString() ?? '0') ?? 0;
    switch (type) {
      case 'percent':
        final sales = double.tryParse(s['total_sales']?.toString() ?? '0') ?? 0;
        final tth = double.tryParse(s['salary_tier_threshold']?.toString() ?? '0') ?? 0;
        final ttv = double.tryParse(s['salary_tier_value']?.toString() ?? '0') ?? 0;
        if (tth > 0 && ttv > 0) {
          return '${tr('Savdo')}: ${_money(sales)}  •  ${_fmtNum(val)}%  (>${_money(tth)}/kun → ${_fmtNum(ttv)}%)';
        }
        return '${tr('Savdo')}: ${_money(sales)} × ${_fmtNum(val)}%';
      case 'percent_total':
        final allSales = double.tryParse(s['total_all_sales']?.toString() ?? '0') ?? 0;
        return '${tr('Jami tushum')}: ${_money(allSales)} × ${_fmtNum(val)}%';
      case 'piece':
        final pb = double.tryParse(s['piece_base']?.toString() ?? '0') ?? 0;
        return '${tr('Dona uchun')}: ${_money(pb)}';
      case 'monthly':
        return tr('Belgilangan oylik');
      case 'daily':
        final d = (s['days_worked'] as num?)?.toInt() ?? 0;
        return '$d ${tr('kun')} × ${_money(val)}';
      case 'hourly':
        final h = double.tryParse(s['hours_worked']?.toString() ?? '0') ?? 0;
        return '${_fmtNum(h)} ${tr('soat')} × ${_money(val)}';
      default:
        return '';
    }
  }

  String get _advanceDate {
    final now = DateTime.now();
    return _isCurrentMonth ? _ymd(DateTime(now.year, now.month, now.day)) : _ymd(_to);
  }

  @override
  Widget build(BuildContext context) {
    final staff = (_data?['staff'] as List?) ?? [];
    final totalNet = double.tryParse(_data?['total_net']?.toString() ?? '0') ?? 0;
    final totalAdvance = double.tryParse(_data?['total_advance']?.toString() ?? '0') ?? 0;
    final totalRemaining = double.tryParse(_data?['total_remaining']?.toString() ?? '0') ?? 0;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.payments, color: AppTheme.accent),
                    const SizedBox(width: 8),
                    Text(tr('Ish haqi'),
                        style: TextStyle(color: AppTheme.text, fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    if (staff.isNotEmpty)
                      IconButton(
                        icon: Icon(Icons.picture_as_pdf, color: AppTheme.accent),
                        tooltip: tr('PDF hisobot'),
                        onPressed: _generatePdf,
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                // Oy tanlash (oldingi/keyingi)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.card,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: Icon(Icons.chevron_left, color: AppTheme.accent),
                        onPressed: () => _shiftMonth(-1),
                      ),
                      Text(_monthLabel,
                          style: TextStyle(color: AppTheme.text, fontSize: 15, fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: Icon(Icons.chevron_right,
                            color: _isCurrentMonth ? AppTheme.textSoft.withValues(alpha: 0.35) : AppTheme.accent),
                        onPressed: _isCurrentMonth ? null : () => _shiftMonth(1),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _statCard(tr('Hisoblangan'), _money(totalNet), AppTheme.accent),
                    const SizedBox(width: 8),
                    _statCard(tr('Avans'), totalAdvance > 0 ? '-${_money(totalAdvance)}' : '0', Colors.deepOrange),
                    const SizedBox(width: 8),
                    _statCard(tr('Qoldiq'), _money(totalRemaining), Colors.green),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: AppTheme.accent))
                : staff.isEmpty
                    ? Center(child: Text(tr('Ma\'lumot yo\'q'), style: TextStyle(color: AppTheme.textSoft)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AppTheme.accent,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          itemCount: staff.length,
                          itemBuilder: (context, index) => _staffCard(staff[index] as Map<String, dynamic>),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _staffCard(Map<String, dynamic> s) {
    final role = s['role_name']?.toString() ?? '';
    final type = s['salary_type']?.toString() ?? '';
    final fine = double.tryParse(s['total_fine']?.toString() ?? '0') ?? 0;
    final net = double.tryParse(s['net_salary']?.toString() ?? '0') ?? 0;
    final advance = double.tryParse(s['advance']?.toString() ?? '0') ?? 0;
    final remaining = double.tryParse(s['remaining']?.toString() ?? (net - advance).toString()) ?? 0;
    final rc = _roleColor(role);
    final nm = (s['full_name']?.toString() ?? '').trim();

    return GestureDetector(
      onTap: () => _showPayslip(s),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: rc.withValues(alpha: 0.15),
              child: Text(nm.isNotEmpty ? nm[0].toUpperCase() : '?',
                  style: TextStyle(color: rc, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(nm,
                      style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text('${_roleLabel(role)}  •  ${_salaryTypeLabel(type)}',
                      style: TextStyle(color: rc, fontSize: 12)),
                  const SizedBox(height: 3),
                  Text(_basis(s), style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
                  if (fine > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('${tr('Jarima')}: -${_money(fine)} ${tr('so\'m')}',
                          style: const TextStyle(color: Colors.orange, fontSize: 12)),
                    ),
                  if (advance > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('${tr('Avans')}: -${_money(advance)} ${tr('so\'m')}',
                          style: const TextStyle(color: Colors.deepOrange, fontSize: 12)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (advance > 0)
                  Text(_money(net),
                      style: TextStyle(
                          color: AppTheme.textSoft,
                          fontSize: 11,
                          decoration: TextDecoration.lineThrough)),
                Text(_money(remaining),
                    style: const TextStyle(color: Colors.green, fontSize: 16, fontWeight: FontWeight.bold)),
                Text(tr('so\'m'), style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showPayslip(Map<String, dynamic> s) {
    showDialog(
      context: context,
      builder: (_) => _PayslipDialog(
        staff: s,
        fromYmd: _ymd(_from),
        toYmd: _ymd(_to),
        advanceDate: _advanceDate,
        monthLabel: _monthLabel,
        roleLabel: _roleLabel,
        salaryTypeLabel: _salaryTypeLabel,
        money: _money,
        fmtNum: _fmtNum,
        onChanged: _load,
      ),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Column(
          children: [
            FittedBox(
              child: Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: AppTheme.textSoft, fontSize: 11), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Future<void> _generatePdf() async {
    final staff = (_data?['staff'] as List?) ?? [];
    if (staff.isEmpty) return;
    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();
    double n(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0;
    final totalBase = n(_data?['total_base']);
    final totalFine = n(_data?['total_fine']);
    final totalManualFine = n(_data?['total_manual_fine']);
    final totalBonus = n(_data?['total_bonus']);
    final totalAdvance = n(_data?['total_advance']);
    final totalPaid = n(_data?['total_paid']);
    final totalSalaryPaid = totalPaid - totalAdvance;
    final totalRemaining = n(_data?['total_remaining']);

    pw.Widget cell(String t, {pw.TextStyle? st, pw.Alignment? a}) => pw.Container(
          alignment: a ?? pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: pw.Text(t, style: st ?? pw.TextStyle(font: font, fontSize: 8)),
        );
    final hStyle = pw.TextStyle(font: fontBold, fontSize: 8);
    String dash(num v) => v > 0 ? '-${_money(v)}' : '—';
    String salMethod(Map<String, dynamic> s) {
      final c = n(s['salary_card']);
      final h = n(s['salary_cash']);
      if (c > 0 && h > 0) return tr('aralash');
      if (c > 0) return tr('Karta');
      if (h > 0) return tr('Naqd');
      return '';
    }

    final pdf = pw.Document();
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      orientation: pw.PageOrientation.landscape,
      margin: const pw.EdgeInsets.all(22),
      build: (ctx) => [
        pw.Text('${tr('Ish haqi varaqasi')} — $_monthLabel',
            style: pw.TextStyle(font: fontBold, fontSize: 16)),
        pw.SizedBox(height: 4),
        pw.Text('${tr('Davr')}: ${_data?['from']} — ${_data?['to']}',
            style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey700)),
        pw.SizedBox(height: 12),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(0.5),
            1: pw.FlexColumnWidth(2.8),
            2: pw.FlexColumnWidth(2.4),
            3: pw.FlexColumnWidth(1.5),
            4: pw.FlexColumnWidth(1.4),
            5: pw.FlexColumnWidth(1.3),
            6: pw.FlexColumnWidth(1.3),
            7: pw.FlexColumnWidth(1.8),
            8: pw.FlexColumnWidth(1.6),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.grey200),
              children: [
                cell('#', st: hStyle),
                cell(tr('Xodim'), st: hStyle),
                cell(tr('Hisob-kitob'), st: hStyle),
                cell(tr('Hisoblangan'), st: hStyle, a: pw.Alignment.centerRight),
                cell(tr('Jarima'), st: hStyle, a: pw.Alignment.centerRight),
                cell(tr('Bonus'), st: hStyle, a: pw.Alignment.centerRight),
                cell(tr('Avans'), st: hStyle, a: pw.Alignment.centerRight),
                cell(tr('Oylik'), st: hStyle, a: pw.Alignment.centerRight),
                cell(tr('Qoldiq'), st: hStyle, a: pw.Alignment.centerRight),
              ],
            ),
            ...staff.asMap().entries.map((e) {
              final i = e.key;
              final s = e.value as Map<String, dynamic>;
              final base = n(s['base_salary']);
              final allFine = n(s['total_fine']) + n(s['manual_fine']); // auto (kechikish) + qo'l
              final bonus = n(s['bonus']);
              final adv = n(s['advance']);
              final sal = n(s['salary_paid']);
              final rem = n(s['remaining']);
              final pd = (s['salary_period_days'] as num?)?.toInt() ?? 30;
              final m = salMethod(s);
              return pw.TableRow(children: [
                cell('${i + 1}'),
                cell('${s['full_name'] ?? ''}\n${_roleLabel(s['role_name']?.toString() ?? '')}  •  ${tr('Har')} $pd ${tr('kun')}'),
                cell(_basis(s)),
                cell(_money(base), a: pw.Alignment.centerRight),
                cell(dash(allFine), a: pw.Alignment.centerRight),
                cell(bonus > 0 ? '+${_money(bonus)}' : '—', a: pw.Alignment.centerRight),
                cell(dash(adv), a: pw.Alignment.centerRight),
                cell(sal > 0 ? '-${_money(sal)}${m.isNotEmpty ? '\n($m)' : ''}' : '—', a: pw.Alignment.centerRight),
                cell(_money(rem), st: pw.TextStyle(font: fontBold, fontSize: 8), a: pw.Alignment.centerRight),
              ]);
            }),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Container(
          alignment: pw.Alignment.centerRight,
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('${tr('Jami hisoblangan')}: ${_money(totalBase)} ${tr('so\'m')}',
                style: pw.TextStyle(font: font, fontSize: 10)),
            pw.Text('${tr('Jami jarima')}: -${_money(totalFine + totalManualFine)} ${tr('so\'m')}',
                style: pw.TextStyle(font: font, fontSize: 10)),
            if (totalBonus > 0)
              pw.Text('${tr('Bonus')}: +${_money(totalBonus)} ${tr('so\'m')}',
                  style: pw.TextStyle(font: font, fontSize: 10)),
            pw.Text('${tr('Avans')}: -${_money(totalAdvance)} ${tr('so\'m')}',
                style: pw.TextStyle(font: font, fontSize: 10)),
            pw.Text('${tr('Oylik')}: -${_money(totalSalaryPaid)} ${tr('so\'m')}',
                style: pw.TextStyle(font: font, fontSize: 10)),
            pw.SizedBox(height: 2),
            pw.Text('${tr('Jami to\'lanadigan')}: ${_money(totalRemaining)} ${tr('so\'m')}',
                style: pw.TextStyle(font: fontBold, fontSize: 13)),
          ]),
        ),
      ],
    ));

    final bytes = await pdf.save();
    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'ish_haqi_${_month.year}_${_month.month.toString().padLeft(2, '0')}.pdf';
    final filePath = '${dir.path}/$fileName';
    await File(filePath).writeAsBytes(bytes);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${tr('PDF saqlandi')}: $filePath'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 4),
      ));
    }
    await OpenFilex.open(filePath);
  }
}

// Payslip + avans boshqaruvi dialogi
class _PayslipDialog extends StatefulWidget {
  final Map<String, dynamic> staff;
  final String fromYmd;
  final String toYmd;
  final String advanceDate;
  final String monthLabel;
  final String Function(String) roleLabel;
  final String Function(String) salaryTypeLabel;
  final String Function(num) money;
  final String Function(num) fmtNum;
  final VoidCallback onChanged;

  const _PayslipDialog({
    required this.staff,
    required this.fromYmd,
    required this.toYmd,
    required this.advanceDate,
    required this.monthLabel,
    required this.roleLabel,
    required this.salaryTypeLabel,
    required this.money,
    required this.fmtNum,
    required this.onChanged,
  });

  @override
  State<_PayslipDialog> createState() => _PayslipDialogState();
}

class _PayslipDialogState extends State<_PayslipDialog> {
  List<dynamic> _payments = [];
  List<dynamic> _fines = [];
  List<dynamic> _bonuses = [];
  Map<String, dynamic>? _staffOverride; // jarima tahrirlangach yangilangan ma'lumot
  bool _loading = true;
  bool _paying = false; // to'lov yuborilmoqda — ikki marta bosishdan himoya

  int get _userId => (widget.staff['user_id'] as num).toInt();

  // Kechikish jarimasi tahrirlangach shu xodim ma'lumotini qayta yuklash
  Future<void> _refreshStaff() async {
    try {
      final data = await ApiService.get('${AppConstants.payrollReport}?from=${widget.fromYmd}&to=${widget.toYmd}');
      final list = (data is Map ? data['staff'] : null) as List?;
      if (list != null) {
        final found = list
            .cast<Map<String, dynamic>>()
            .firstWhere((x) => (x['user_id'] as num).toInt() == _userId, orElse: () => <String, dynamic>{});
        if (found.isNotEmpty && mounted) setState(() => _staffOverride = found);
      }
    } catch (_) {}
  }

  // Kechikish jarimasini tahrirlash / kechirish (oy bo'yicha)
  Future<void> _editLateFine(double autoFine) async {
    final s = _staffOverride ?? widget.staff;
    final ym = widget.fromYmd.length >= 7 ? widget.fromYmd.substring(0, 7) : '';
    if (ym.isEmpty) return;
    final overridden = s['fine_overridden'] == true;
    final cur = double.tryParse(s['total_fine']?.toString() ?? '0') ?? 0;
    final ctrl = TextEditingController(text: widget.fmtNum(cur));
    final reasonCtrl = TextEditingController(text: overridden ? (s['fine_override_reason']?.toString() ?? '') : '');
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('Kechikish jarimasi'), style: TextStyle(color: AppTheme.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${tr('Avtomatik')}: ${widget.money(autoFine)} ${tr('so\'m')}',
                style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: TextStyle(color: AppTheme.text),
              decoration: InputDecoration(
                  labelText: tr('Yangi jarima'), suffixText: tr('so\'m'), labelStyle: TextStyle(color: AppTheme.textSoft)),
            ),
            TextField(
              controller: reasonCtrl,
              style: TextStyle(color: AppTheme.text),
              decoration: InputDecoration(labelText: tr('Sabab'), labelStyle: TextStyle(color: AppTheme.textSoft)),
            ),
            const SizedBox(height: 6),
            Text(tr('0 = to\'liq kechirish'), style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
          if (overridden)
            TextButton(onPressed: () => Navigator.pop(ctx, 'reset'), child: Text(tr('Avtomatik'), style: const TextStyle(color: Colors.teal))),
          TextButton(onPressed: () => Navigator.pop(ctx, 'save'), child: Text(tr('Saqlash'), style: TextStyle(color: AppTheme.accent))),
        ],
      ),
    );
    if (res == null) return;
    try {
      if (res == 'reset') {
        await ApiService.delete('${AppConstants.lateFineOverride}?user_id=$_userId&period_ym=$ym');
      } else {
        final amt = double.tryParse(ctrl.text.trim().replaceAll(' ', '')) ?? 0;
        await ApiService.post(AppConstants.lateFineOverride, {
          'user_id': _userId,
          'period_ym': ym,
          'amount': amt,
          'reason': reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
        });
      }
      await _refreshStaff();
      widget.onChanged();
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _loadPayments();
    _loadFines();
    _loadBonuses();
  }

  Future<void> _loadBonuses() async {
    try {
      final data = await ApiService.get(
          '${AppConstants.salaryBonuses}?user_id=$_userId&from=${widget.fromYmd}&to=${widget.toYmd}');
      if (mounted) setState(() => _bonuses = data is List ? data : []);
    } catch (_) {}
  }

  double get _bonusTotal =>
      _bonuses.fold(0.0, (sum, a) => sum + (double.tryParse(a['amount']?.toString() ?? '0') ?? 0));

  Future<void> _addBonus() async {
    final valCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    bool isPercent = false;
    final net = double.tryParse(widget.staff['net_salary']?.toString() ?? '0') ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text(tr('Bonus'), style: TextStyle(color: AppTheme.text)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                _methodToggle(ctx, tr('Summa'), !isPercent, () => setSt(() => isPercent = false)),
                const SizedBox(width: 8),
                _methodToggle(ctx, tr('Foiz'), isPercent, () => setSt(() => isPercent = true)),
              ]),
              const SizedBox(height: 8),
              TextField(
                controller: valCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: TextStyle(color: AppTheme.text),
                decoration: InputDecoration(
                    labelText: isPercent ? tr('Foiz') : tr('Summa'),
                    suffixText: isPercent ? '%' : tr('so\'m'),
                    labelStyle: TextStyle(color: AppTheme.textSoft)),
              ),
              TextField(
                controller: reasonCtrl,
                style: TextStyle(color: AppTheme.text),
                decoration: InputDecoration(labelText: tr('Sabab'), labelStyle: TextStyle(color: AppTheme.textSoft)),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Saqlash'), style: TextStyle(color: AppTheme.accent))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final v = double.tryParse(valCtrl.text.trim().replaceAll(' ', '')) ?? 0;
    if (v <= 0) return;
    final amount = isPercent ? (net * v / 100).roundToDouble() : v;
    if (amount <= 0) return;
    try {
      await ApiService.post(AppConstants.salaryBonuses, {
        'user_id': _userId,
        'amount': amount,
        'percent': isPercent ? v : null,
        'reason': reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
        'date': widget.advanceDate,
      });
      await _loadBonuses();
      widget.onChanged();
    } catch (_) {}
  }

  Future<void> _deleteBonus(int id) async {
    try {
      await ApiService.delete('${AppConstants.salaryBonuses}/$id');
      await _loadBonuses();
      widget.onChanged();
    } catch (_) {}
  }

  Future<void> _loadPayments() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.get(
          '${AppConstants.salaryPayments}?user_id=$_userId&from=${widget.fromYmd}&to=${widget.toYmd}');
      if (mounted) {
        setState(() {
          _payments = data is List ? data : [];
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadFines() async {
    try {
      final data = await ApiService.get(
          '${AppConstants.salaryFines}?user_id=$_userId&from=${widget.fromYmd}&to=${widget.toYmd}');
      if (mounted) setState(() => _fines = data is List ? data : []);
    } catch (_) {}
  }

  double get _paidTotal =>
      _payments.fold(0.0, (sum, a) => sum + (double.tryParse(a['amount']?.toString() ?? '0') ?? 0));

  double get _finesTotal =>
      _fines.fold(0.0, (sum, a) => sum + (double.tryParse(a['amount']?.toString() ?? '0') ?? 0));

  Future<void> _addFine() async {
    final amtCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('Jarima'), style: TextStyle(color: AppTheme.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amtCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: TextStyle(color: AppTheme.text),
              decoration: InputDecoration(
                  labelText: tr('Summa'), suffixText: tr('so\'m'), labelStyle: TextStyle(color: AppTheme.textSoft)),
            ),
            TextField(
              controller: reasonCtrl,
              style: TextStyle(color: AppTheme.text),
              decoration: InputDecoration(labelText: tr('Sabab'), labelStyle: TextStyle(color: AppTheme.textSoft)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('Saqlash'), style: TextStyle(color: AppTheme.accent))),
        ],
      ),
    );
    if (ok != true) return;
    final amt = double.tryParse(amtCtrl.text.trim().replaceAll(' ', '')) ?? 0;
    if (amt <= 0) return;
    try {
      await ApiService.post(AppConstants.salaryFines, {
        'user_id': _userId,
        'amount': amt,
        'reason': reasonCtrl.text.trim().isEmpty ? null : reasonCtrl.text.trim(),
        'date': widget.advanceDate,
      });
      await _loadFines();
      widget.onChanged();
    } catch (_) {}
  }

  Future<void> _deleteFine(int id) async {
    try {
      await ApiService.delete('${AppConstants.salaryFines}/$id');
      await _loadFines();
      widget.onChanged();
    } catch (_) {}
  }

  // kind: 'advance' yoki 'salary'
  Future<void> _addPayment(String kind) async {
    final amtCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final sourceCtrl = TextEditingController();
    String method = 'cash';
    bool fromKassa = true; // pul Kassadan chiqadimi
    final isSalary = kind == 'salary';
    if (isSalary) {
      // qoldiqni avtomatik to'ldiramiz
      final net = double.tryParse(widget.staff['net_salary']?.toString() ?? '0') ?? 0;
      final rem = net - _paidTotal;
      if (rem > 0) amtCtrl.text = rem.toStringAsFixed(0);
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text(isSalary ? tr('Oylik to\'lash') : tr('Avans qo\'shish'), style: TextStyle(color: AppTheme.text)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amtCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: TextStyle(color: AppTheme.text),
                decoration: InputDecoration(
                  labelText: tr('Summa'),
                  suffixText: tr('so\'m'),
                  labelStyle: TextStyle(color: AppTheme.textSoft),
                  suffixStyle: TextStyle(color: AppTheme.textSoft),
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [
                _methodToggle(ctx, tr('Naqd'), method == 'cash', () => setSt(() => method = 'cash')),
                const SizedBox(width: 8),
                _methodToggle(ctx, tr('Karta'), method == 'card', () => setSt(() => method = 'card')),
              ]),
              const SizedBox(height: 10),
              // Pul manbasi: Kassadan yoki boshqa joydan
              Align(
                alignment: Alignment.centerLeft,
                child: Text(tr('Pul manbasi'), style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
              ),
              const SizedBox(height: 4),
              Row(children: [
                _methodToggle(ctx, tr('Kassadan'), fromKassa, () => setSt(() => fromKassa = true)),
                const SizedBox(width: 8),
                _methodToggle(ctx, tr('Boshqa joydan'), !fromKassa, () => setSt(() => fromKassa = false)),
              ]),
              if (!fromKassa)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: TextField(
                    controller: sourceCtrl,
                    style: TextStyle(color: AppTheme.text),
                    decoration: InputDecoration(
                      labelText: tr('Qayerdan'),
                      hintText: tr('masalan: Direktor cho\'ntagidan'),
                      hintStyle: TextStyle(color: AppTheme.textSoft, fontSize: 12),
                      labelStyle: TextStyle(color: AppTheme.textSoft),
                    ),
                  ),
                ),
              if (!fromKassa)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(tr('Kassadan pul yechilmaydi'), style: const TextStyle(color: Colors.teal, fontSize: 11)),
                  ),
                ),
              TextField(
                controller: noteCtrl,
                style: TextStyle(color: AppTheme.text),
                decoration: InputDecoration(labelText: tr('Izoh'), labelStyle: TextStyle(color: AppTheme.textSoft)),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Saqlash'), style: TextStyle(color: AppTheme.accent))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final amt = double.tryParse(amtCtrl.text.trim().replaceAll(' ', '')) ?? 0;
    if (amt <= 0) return;
    if (_paying) return; // so'rov ketayotganda takror bosish ishlamaydi
    setState(() => _paying = true);
    try {
      // Idempotency-Key — oylik/avans to'lovi retry'da ikki marta yozilmasligi uchun
      final res = await ApiService.post(AppConstants.salaryPayments, {
        'user_id': _userId,
        'amount': amt,
        'method': method,
        'kind': kind,
        'note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
        'from_kassa': fromKassa,
        'source': fromKassa ? null : (sourceCtrl.text.trim().isEmpty ? null : sourceCtrl.text.trim()),
        'date': widget.advanceDate,
      }, idempotencyKey: ApiService.newIdempotencyKey());
      // Backend xato (masalan sikl) — message qaytaradi, id bo'lmaydi
      if (res is Map && res['id'] == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message']?.toString() ?? tr('Xato')), backgroundColor: Colors.red),
          );
        }
        return;
      }
      await _loadPayments();
      widget.onChanged();
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  Widget _methodToggle(BuildContext ctx, String label, bool sel, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: sel ? AppTheme.accent.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: sel ? AppTheme.accent : AppTheme.border),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(color: sel ? AppTheme.accent : AppTheme.textSoft, fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
        ),
      ),
    );
  }

  Future<void> _deletePayment(int id) async {
    try {
      await ApiService.delete('${AppConstants.salaryPayments}/$id');
      await _loadPayments();
      widget.onChanged();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = _staffOverride ?? widget.staff;
    final type = s['salary_type']?.toString() ?? '';
    final val = double.tryParse(s['salary_value']?.toString() ?? '0') ?? 0;
    final base = double.tryParse(s['base_salary']?.toString() ?? '0') ?? 0;
    final fine = double.tryParse(s['total_fine']?.toString() ?? '0') ?? 0;
    final autoFine = double.tryParse(s['auto_fine']?.toString() ?? '0') ?? 0;
    final fineOverridden = s['fine_overridden'] == true;
    final fineOverrideReason = s['fine_override_reason']?.toString() ?? '';
    final net = double.tryParse(s['net_salary']?.toString() ?? '0') ?? 0;
    final sales = double.tryParse(s['total_sales']?.toString() ?? '0') ?? 0;
    final allSales = double.tryParse(s['total_all_sales']?.toString() ?? '0') ?? 0;
    final orders = (s['orders_count'] as num?)?.toInt() ?? 0;
    final days = (s['days_worked'] as num?)?.toInt() ?? 0;
    final hours = double.tryParse(s['hours_worked']?.toString() ?? '0') ?? 0;
    final remaining = net + _bonusTotal - _finesTotal - _paidTotal;
    final salarySettled = s['salary_settled'] == true;
    final canPaySalary = s['can_pay_salary'] == true;
    final lastSalaryDate = s['last_salary_date']?.toString() ?? '';
    final periodDays = (s['salary_period_days'] as num?)?.toInt() ?? 30;
    final daysSince = (s['days_since_salary'] as num?)?.toInt();

    Widget kv(String k, String v, {Color? c, bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text(k, style: TextStyle(color: AppTheme.textSoft, fontSize: 13))),
              const SizedBox(width: 12),
              Text(v,
                  style: TextStyle(
                      color: c ?? AppTheme.text,
                      fontSize: bold ? 17 : 13,
                      fontWeight: bold ? FontWeight.bold : FontWeight.w600)),
            ],
          ),
        );

    return AlertDialog(
      backgroundColor: AppTheme.card,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s['full_name']?.toString() ?? '', style: TextStyle(color: AppTheme.text, fontSize: 17)),
          Text('${widget.roleLabel(s['role_name']?.toString() ?? '')}  •  ${widget.monthLabel}',
              style: TextStyle(color: AppTheme.textSoft, fontSize: 12, fontWeight: FontWeight.normal)),
        ],
      ),
      content: SizedBox(
        width: 330,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              kv(tr('Maosh turi'), widget.salaryTypeLabel(type)),
              kv(tr('Oylik davri'), '${tr('Har')} $periodDays ${tr('kun')}${daysSince != null ? '  •  ${tr('oxirgisidan')} $daysSince ${tr('kun')}' : ''}'),
              if (type == 'percent') ...[
                kv(tr('Savdo'), '${widget.money(sales)} ${tr('so\'m')}'),
                kv(tr('Zakazlar'), '$orders ${tr('ta')}'),
                kv(tr('Foiz'), '${widget.fmtNum(val)}%'),
              ],
              if (type == 'percent_total') ...[
                kv(tr('Jami tushum'), '${widget.money(allSales)} ${tr('so\'m')}'),
                kv(tr('Foiz'), '${widget.fmtNum(val)}%'),
              ],
              kv(tr('Ishlagan kun'), '$days'),
              kv(tr('Ishlagan soat'), widget.fmtNum(hours)),
              Divider(color: AppTheme.border, height: 16),
              kv(tr('Hisoblangan'), '${widget.money(base)} ${tr('so\'m')}'),
              if (autoFine > 0 || fineOverridden)
                InkWell(
                  onTap: () => _editLateFine(autoFine),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(tr('Kechikish jarimasi'), style: TextStyle(color: AppTheme.textSoft, fontSize: 13)),
                              const SizedBox(width: 4),
                              Icon(Icons.edit, size: 13, color: AppTheme.accent),
                              if (fineOverridden)
                                Flexible(
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 5),
                                    child: Text(
                                      fineOverrideReason.isNotEmpty ? fineOverrideReason : tr('tahrirlangan'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.teal, fontSize: 10),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(fine > 0 ? '-${widget.money(fine)} ${tr('so\'m')}' : '0',
                            style: const TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              kv(tr('Sof maosh'), '${widget.money(net)} ${tr('so\'m')}'),
              if (salarySettled)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 16),
                      const SizedBox(width: 6),
                      Text('${tr('Oylik berildi')}${lastSalaryDate.isNotEmpty ? ': $lastSalaryDate' : ''}',
                          style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              Divider(color: AppTheme.border, height: 16),
              Text(tr('To\'lovlar'),
                  style: TextStyle(color: AppTheme.text, fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _addPayment('advance'),
                    icon: Icon(Icons.add, size: 16, color: AppTheme.accent),
                    label: Text(tr('Avans'), style: TextStyle(color: AppTheme.accent, fontSize: 12)),
                    style: OutlinedButton.styleFrom(side: BorderSide(color: AppTheme.border), padding: const EdgeInsets.symmetric(vertical: 4)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (canPaySalary && remaining > 0) ? () => _addPayment('salary') : null,
                    icon: Icon(Icons.payments, size: 16, color: (canPaySalary && remaining > 0) ? Colors.green : AppTheme.textSoft),
                    label: Text(tr('Oylik to\'lash'),
                        style: TextStyle(color: (canPaySalary && remaining > 0) ? Colors.green : AppTheme.textSoft, fontSize: 12)),
                    style: OutlinedButton.styleFrom(side: BorderSide(color: AppTheme.border), padding: const EdgeInsets.symmetric(vertical: 4)),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              if (_loading)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent))),
                )
              else if (_payments.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(tr('To\'lov yo\'q'), style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
                )
              else
                ..._payments.map((a) {
                  final id = (a['id'] as num).toInt();
                  final amt = double.tryParse(a['amount']?.toString() ?? '0') ?? 0;
                  final note = a['note']?.toString() ?? '';
                  final date = a['date']?.toString() ?? '';
                  final pkind = a['kind']?.toString() ?? 'advance';
                  final pmethod = a['method']?.toString() ?? 'cash';
                  final src = a['source']?.toString() ?? '';
                  final otherSrc = src.isNotEmpty && src != 'kassa';
                  final isSal = pkind == 'salary';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(
                      children: [
                        Icon(pmethod == 'card' ? Icons.credit_card : Icons.payments, size: 13, color: AppTheme.textSoft),
                        const SizedBox(width: 4),
                        Text(isSal ? tr('Oylik') : tr('Avans'),
                            style: TextStyle(color: isSal ? Colors.green : Colors.deepOrange, fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                              '$date${otherSrc ? '  •  $src' : ''}${note.isNotEmpty ? '  •  $note' : ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: otherSrc ? Colors.teal : AppTheme.textSoft, fontSize: 11)),
                        ),
                        Text('-${widget.money(amt)}',
                            style: TextStyle(color: isSal ? Colors.green : Colors.deepOrange, fontSize: 13, fontWeight: FontWeight.w600)),
                        IconButton(
                          icon: Icon(Icons.close, size: 16, color: AppTheme.textSoft),
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.only(left: 8),
                          onPressed: () => _deletePayment(id),
                        ),
                      ],
                    ),
                  );
                }),
              // ── Qo'lda jarimalar ──
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(tr('Jarimalar'),
                      style: TextStyle(color: AppTheme.text, fontSize: 14, fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: _addFine,
                    icon: Icon(Icons.add, size: 16, color: Colors.orange),
                    label: Text(tr('Jarima'), style: const TextStyle(color: Colors.orange, fontSize: 12)),
                  ),
                ],
              ),
              if (_fines.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(tr('Jarima yo\'q'), style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
                )
              else
                ..._fines.map((f) {
                  final id = (f['id'] as num).toInt();
                  final amt = double.tryParse(f['amount']?.toString() ?? '0') ?? 0;
                  final reason = f['reason']?.toString() ?? '';
                  final date = f['date']?.toString() ?? '';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(
                      children: [
                        Icon(Icons.gavel, size: 13, color: Colors.orange),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('$date${reason.isNotEmpty ? '  •  $reason' : ''}',
                              style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
                        ),
                        Text('-${widget.money(amt)}',
                            style: const TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.w600)),
                        IconButton(
                          icon: Icon(Icons.close, size: 16, color: AppTheme.textSoft),
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.only(left: 8),
                          onPressed: () => _deleteFine(id),
                        ),
                      ],
                    ),
                  );
                }),
              // ── Bonuslar ──
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(tr('Bonuslar'),
                      style: TextStyle(color: AppTheme.text, fontSize: 14, fontWeight: FontWeight.bold)),
                  TextButton.icon(
                    onPressed: _addBonus,
                    icon: Icon(Icons.add, size: 16, color: Colors.teal),
                    label: Text(tr('Bonus'), style: const TextStyle(color: Colors.teal, fontSize: 12)),
                  ),
                ],
              ),
              if (_bonuses.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(tr('Bonus yo\'q'), style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
                )
              else
                ..._bonuses.map((b) {
                  final id = (b['id'] as num).toInt();
                  final amt = double.tryParse(b['amount']?.toString() ?? '0') ?? 0;
                  final pct = b['percent'];
                  final reason = b['reason']?.toString() ?? '';
                  final date = b['date']?.toString() ?? '';
                  final pctStr = pct != null ? ' (${widget.fmtNum(double.tryParse(pct.toString()) ?? 0)}%)' : '';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Row(
                      children: [
                        Icon(Icons.star, size: 13, color: Colors.teal),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text('$date$pctStr${reason.isNotEmpty ? '  •  $reason' : ''}',
                              style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
                        ),
                        Text('+${widget.money(amt)}',
                            style: const TextStyle(color: Colors.teal, fontSize: 13, fontWeight: FontWeight.w600)),
                        IconButton(
                          icon: Icon(Icons.close, size: 16, color: AppTheme.textSoft),
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints(),
                          padding: const EdgeInsets.only(left: 8),
                          onPressed: () => _deleteBonus(id),
                        ),
                      ],
                    ),
                  );
                }),
              Divider(color: AppTheme.border, height: 16),
              kv(tr('Qoldiq'), '${widget.money(remaining)} ${tr('so\'m')}', c: Colors.green, bold: true),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Yopish'), style: TextStyle(color: AppTheme.accent)),
        ),
      ],
    );
  }
}
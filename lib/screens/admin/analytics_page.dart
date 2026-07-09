import 'package:flutter/material.dart';
import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../../core/lang.dart';

/// Kengaytirilgan analitika — davr (Bugun/Hafta/Oy/o'z davri) bo'yicha
/// KPI + oldingi davr bilan taqqoslash, kunlik grafik, top taomlar,
/// kategoriya/to'lov/soat kesimlari, ofitsantlar.
class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});
  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  String _period = 'd7'; // today|yesterday|d7|d30|month|prevmonth|year|custom
  String _dishSort = 'profit'; // profit | revenue | qty | margin
  DateTime _from = DateTime.now().subtract(const Duration(days: 6));
  DateTime _to = DateTime.now();
  Map<String, dynamic>? _d;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      // Har doim from/to yuboramiz (backend resolveRange 02:30 chegara qo'yadi)
      final res = await ApiService.get('/reports/analytics?from=${_ymd(_from)}&to=${_ymd(_to)}');
      if (!mounted) return;
      setState(() { _d = res is Map ? Map<String, dynamic>.from(res) : null; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  // Tayyor davrlar (foydalanuvchi o'zi tanlaydi)
  void _setPreset(String key) {
    final now = DateTime.now();
    DateTime f = now, t = now;
    switch (key) {
      case 'today': f = now; t = now; break;
      case 'yesterday': f = now.subtract(const Duration(days: 1)); t = f; break;
      case 'd7': f = now.subtract(const Duration(days: 6)); t = now; break;
      case 'd30': f = now.subtract(const Duration(days: 29)); t = now; break;
      case 'month': f = DateTime(now.year, now.month, 1); t = now; break;
      case 'prevmonth': f = DateTime(now.year, now.month - 1, 1); t = DateTime(now.year, now.month, 0); break;
      case 'year': f = DateTime(now.year, 1, 1); t = now; break;
    }
    setState(() { _period = key; _from = f; _to = t; });
    _load();
  }

  Future<void> _pickCustom() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (r != null) {
      setState(() { _period = 'custom'; _from = r.start; _to = r.end; });
      _load();
    }
  }

  num _n(dynamic v) => v is num ? v : (num.tryParse(v?.toString() ?? '0') ?? 0);

  String _money(num v) {
    final neg = v < 0;
    final s = v.abs().round().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return (neg ? '-' : '') + buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([AppTheme.instance, Lang.instance]),
      builder: (_, __) => Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(
          backgroundColor: AppTheme.card,
          iconTheme: IconThemeData(color: AppTheme.text),
          title: Text(tr('Analitika'), style: TextStyle(color: AppTheme.text)),
          actions: [
            IconButton(
              icon: Icon(Icons.refresh, color: AppTheme.text),
              onPressed: _load,
            ),
          ],
        ),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: AppTheme.accent))
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('${tr('Xato')}: $_error', style: TextStyle(color: Colors.red))))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
                      children: [
                        _filterBar(),
                        const SizedBox(height: 14),
                        ..._body(),
                      ],
                    ),
                  ),
      ),
    );
  }

  // ==== filtr: davrni O'ZI tanlaydi (tayyor davrlar + o'z diapazoni) ====
  Widget _filterBar() {
    Widget chip(String key, String label, {VoidCallback? onTap, bool custom = false}) {
      final sel = _period == key;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          onTap: onTap ?? () => _setPreset(key),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? AppTheme.accent : AppTheme.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: sel ? AppTheme.accent : AppTheme.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (custom) Padding(padding: const EdgeInsets.only(right: 5), child: Icon(Icons.date_range, size: 15, color: sel ? Colors.white : AppTheme.textSoft)),
              Text(label, style: TextStyle(color: sel ? Colors.white : AppTheme.text, fontWeight: FontWeight.w600, fontSize: 13)),
            ]),
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          chip('today', tr('Bugun')),
          chip('yesterday', tr('Kecha')),
          chip('d7', tr('7 kun')),
          chip('d30', tr('30 kun')),
          chip('month', tr('Shu oy')),
          chip('prevmonth', tr('O\'tgan oy')),
          chip('year', tr('Yil')),
          chip('custom', tr('Davr'), onTap: _pickCustom, custom: true),
        ]),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Icon(Icons.calendar_today, size: 13, color: AppTheme.textSoft),
        const SizedBox(width: 6),
        Text('${_ymd(_from)}  —  ${_ymd(_to)}', style: TextStyle(color: AppTheme.textSoft, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    ]);
  }

  List<Widget> _body() {
    final d = _d;
    if (d == null) return [Center(child: Text(tr('Ma\'lumot yo\'q'), style: TextStyle(color: AppTheme.textSoft)))];
    final s = Map<String, dynamic>.from(d['summary'] ?? {});
    final p = Map<String, dynamic>.from(d['prev'] ?? {});
    final pay = Map<String, dynamic>.from(d['payment'] ?? {});
    final byDay = (d['sales_by_day'] as List?)?.cast<dynamic>() ?? [];
    final top = (d['top_items'] as List?)?.cast<dynamic>() ?? [];
    final cats = (d['by_category'] as List?)?.cast<dynamic>() ?? [];
    final hours = (d['by_hour'] as List?)?.cast<dynamic>() ?? [];
    final waiters = (d['waiters'] as List?)?.cast<dynamic>() ?? [];
    final byDish = (d['by_dish'] as List?)?.cast<dynamic>() ?? [];
    final expBreak = (d['expenses_breakdown'] as List?)?.cast<dynamic>() ?? [];
    final debt = Map<String, dynamic>.from(d['debt'] ?? {});
    final lossDishes = byDish.where((e) => _n(e['profit']) < 0).toList();
    final received = _n(s['received']);
    final expenses = _n(s['expenses']);

    return [
      // KPI kartalar
      Wrap(spacing: 10, runSpacing: 10, children: [
        _kpi(tr('Savdo'), _money(_n(s['sales'])), _n(s['sales']), _n(p['sales']), Colors.blue, Icons.trending_up),
        _kpi(tr('Sof foyda'), _money(_n(s['profit'])), _n(s['profit']), _n(p['profit']), Colors.green, Icons.savings),
        _kpi(tr('Kassaga tushdi'), _money(_n(s['received'])), _n(s['received']), null, Colors.teal, Icons.account_balance_wallet),
        _kpi(tr('Valovaya foyda'), _money(_n(s['gross_profit'])), _n(s['gross_profit']), _n(p['gross_profit']), Colors.lightGreen, Icons.show_chart),
        _kpi(tr('Tannarx'), _money(_n(s['cogs'])), _n(s['cogs']), _n(p['cogs']), Colors.orange, Icons.inventory_2, invert: true),
        _kpi(tr('O\'rtacha chek'), _money(_n(s['avg_check'])), _n(s['avg_check']), _n(p['avg_check']), Colors.indigo, Icons.receipt_long),
        _kpi(tr('Zakazlar'), _n(s['orders']).toString(), _n(s['orders']), _n(p['orders']), Colors.purple, Icons.list_alt),
        _kpi(tr('Chegirma'), _money(_n(s['discount'])), _n(s['discount']), null, Colors.redAccent, Icons.percent, invert: true),
      ]),
      const SizedBox(height: 18),

      // Pul oqimi: kirim / chiqim / sof + ochiq qarz
      _card(tr('Pul oqimi'), Column(children: [
        _flowRow(tr('Kirim (kassaga)'), received, Colors.green),
        _flowRow(tr('Chiqim'), expenses, Colors.red),
        Divider(color: AppTheme.border, height: 18),
        _flowRow(tr('Sof oqim'), received - expenses, (received - expenses) >= 0 ? Colors.green : Colors.red, bold: true),
        if (_n(debt['total']) > 0)
          _flowRow('${tr('Ochiq qarz')} (${_n(debt['count'])})', _n(debt['total']), Colors.orange),
      ])),

      // Kunlik savdo grafigi
      _card(tr('Kunlik savdo'), _barChart(byDay,
          (e) => (e['d']?.toString() ?? '').replaceAll(RegExp(r'^\d{4}-'), ''),
          (e) => _n(e['sales']))),

      // To'lov usullari
      _card(tr('To\'lov usullari'), Column(children: [
        _hbar(tr('Karta'), _n(pay['card']), _maxPay(pay), Colors.blue),
        _hbar(tr('Naqd'), _n(pay['cash']), _maxPay(pay), Colors.green),
        _hbar(tr('Qarz'), _n(pay['debt']), _maxPay(pay), Colors.orange),
      ])),

      // Chiqimlar turi bo'yicha (qayerga ketdi)
      if (expBreak.isNotEmpty)
        _card(tr('Chiqimlar (turi bo\'yicha)'), Column(children: [
          for (final e in expBreak)
            _hbar(e['name']?.toString() ?? '', _n(e['amount']),
                _n(expBreak.first['amount']), Colors.redAccent),
        ])),

      // Top taomlar
      _card(tr('Eng ko\'p sotilgan (top)'), Column(children: [
        for (final e in top)
          _hbar('${e['name']}  (${_n(e['qty'])})', _n(e['amount']),
              top.isNotEmpty ? _n(top.first['amount']) : 0, AppTheme.accent),
        if (top.isEmpty) _empty(),
      ])),

      // Kategoriya
      _card(tr('Kategoriya bo\'yicha'), Column(children: [
        for (final e in cats)
          _hbar(e['name']?.toString() ?? '', _n(e['sales']),
              cats.isNotEmpty ? _n(cats.first['sales']) : 0, Colors.deepPurple),
        if (cats.isEmpty) _empty(),
      ])),

      // Zararli blyudolar (foyda < 0) — audit uchun alohida ajratib
      if (lossDishes.isNotEmpty)
        _card('⚠️ ${tr('Zararli blyudolar')}', Column(children: [
          for (final e in lossDishes)
            Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
              Expanded(child: Text('${e['name']}  ×${_n(e['qty'])}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppTheme.text))),
              Text('${_money(_n(e['profit']))} (${_n(e['margin'])}%)', style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600)),
            ])),
        ])),

      // Blyudolar bo'yicha (sotildi/tushum/tannarx/foyda/marja)
      _dishSection(byDish),

      // Soatlar
      _card(tr('Soat bo\'yicha savdo'), _barChart(hours,
          (e) => '${_n(e['h'])}', (e) => _n(e['sales']))),

      // Ofitsantlar
      _card(tr('Ofitsantlar'), Column(children: [
        for (final e in waiters)
          _hbar('${e['full_name']}  (${_n(e['orders'])})', _n(e['sales']),
              waiters.isNotEmpty ? _n(waiters.first['sales']) : 0, Colors.blueGrey),
        if (waiters.isEmpty) _empty(),
      ])),
    ];
  }

  num _maxPay(Map pay) {
    final a = [_n(pay['card']), _n(pay['cash']), _n(pay['debt'])];
    return a.fold<num>(0, (m, v) => v > m ? v : m);
  }

  // ==== KPI karta (qiymat + o'tgan davrga nisbatan o'sish %) ====
  Widget _kpi(String label, String value, num cur, num? prev, Color color, IconData icon, {bool invert = false}) {
    Widget delta = const SizedBox.shrink();
    if (prev != null && prev != 0) {
      final dp = (cur - prev) / prev.abs() * 100;
      final up = dp >= 0;
      // invert: tannarx/chegirma uchun o'sish = yomon (qizil)
      final good = invert ? !up : up;
      delta = Text('${up ? '▲' : '▼'} ${dp.abs().toStringAsFixed(0)}%',
          style: TextStyle(color: good ? Colors.green : Colors.red, fontSize: 10, fontWeight: FontWeight.bold));
    }
    return Container(
      width: 158,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(child: Text(label, style: TextStyle(color: AppTheme.textSoft, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 8),
        Text(value, style: TextStyle(color: AppTheme.text, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        delta,
      ]),
    );
  }

  Widget _card(String title, Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 12),
          child,
        ]),
      );

  Widget _empty() => Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(tr('Ma\'lumot yo\'q'), style: TextStyle(color: AppTheme.textSoft, fontSize: 12)));

  // pul oqimi qatori (nom + rangli summa)
  Widget _flowRow(String label, num value, Color color, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(color: AppTheme.text, fontSize: bold ? 14 : 13, fontWeight: bold ? FontWeight.bold : FontWeight.normal))),
          Text(_money(value), style: TextStyle(color: color, fontSize: bold ? 16 : 14, fontWeight: FontWeight.bold)),
        ]),
      );

  // vertikal ustunli grafik (widget asosida — CustomPaint kerak emas)
  Widget _barChart(List data, String Function(dynamic) label, num Function(dynamic) value) {
    if (data.isEmpty) return _empty();
    num maxV = 0;
    for (final e in data) { final v = value(e); if (v > maxV) maxV = v; }
    return SizedBox(
      height: 150,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final e in data)
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text(_money(value(e)), style: TextStyle(fontSize: 8, color: AppTheme.textSoft), maxLines: 1, overflow: TextOverflow.clip),
              const SizedBox(height: 2),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                height: (maxV > 0 ? (value(e) / maxV * 110) : 2).clamp(2, 110).toDouble(),
                decoration: BoxDecoration(color: AppTheme.accent, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
              ),
              const SizedBox(height: 4),
              Text(label(e), style: TextStyle(fontSize: 8, color: AppTheme.textSoft), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
      ]),
    );
  }

  // gorizontal proporsional bar (nom + bar + qiymat)
  Widget _hbar(String name, num value, num maxV, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        SizedBox(width: 120, child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppTheme.text))),
        Expanded(
          child: Stack(children: [
            Container(height: 16, decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(4))),
            FractionallySizedBox(
              widthFactor: (maxV > 0 ? (value / maxV) : 0).clamp(0.0, 1.0).toDouble(),
              child: Container(height: 16, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 74, child: Text(_money(value), textAlign: TextAlign.right, style: TextStyle(fontSize: 11, color: AppTheme.text, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  // ==== BLYUDOLAR jadvali: sotildi/tushum/tannarx/foyda/marja (saralanadigan) ====
  Widget _dishSection(List dishes) {
    if (dishes.isEmpty) return _card(tr('Blyudolar bo\'yicha'), _empty());
    final sorted = [...dishes];
    sorted.sort((a, b) {
      switch (_dishSort) {
        case 'revenue': return _n(b['revenue']).compareTo(_n(a['revenue']));
        case 'qty': return _n(b['qty']).compareTo(_n(a['qty']));
        case 'margin': return _n(b['margin']).compareTo(_n(a['margin']));
        default: return _n(b['profit']).compareTo(_n(a['profit']));
      }
    });

    Widget sortChip(String key, String label) {
      final sel = _dishSort == key;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InkWell(
          onTap: () => setState(() => _dishSort = key),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            decoration: BoxDecoration(
              color: sel ? AppTheme.accent : AppTheme.bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: sel ? AppTheme.accent : AppTheme.border),
            ),
            child: Text(label, style: TextStyle(color: sel ? Colors.white : AppTheme.textSoft, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ),
      );
    }

    Widget cell(String t, double w, {Color? color, FontWeight? fw, TextAlign a = TextAlign.right}) => SizedBox(
        width: w,
        child: Text(t, textAlign: a, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: color ?? AppTheme.text, fontWeight: fw)));

    Color marginColor(num m) => m < 0 ? Colors.red : (m < 15 ? Colors.orange : Colors.green);

    return _card(tr('Blyudolar bo\'yicha'), Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        Padding(padding: const EdgeInsets.only(right: 8, top: 2), child: Text('${tr('Saralash')}:', style: TextStyle(color: AppTheme.textSoft, fontSize: 11))),
        sortChip('profit', tr('Foyda')),
        sortChip('revenue', tr('Tushum')),
        sortChip('qty', tr('Soni')),
        sortChip('margin', tr('Marja')),
      ])),
      Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 2),
        child: Text('👆 ${tr('Blyudoni bosing — batafsil (kunlik dinamika)')}',
            style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
      ),
      const SizedBox(height: 6),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: 492,
          child: Column(children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border, width: 1.5))),
              child: Row(children: [
                cell(tr('Blyudo'), 150, a: TextAlign.left, fw: FontWeight.bold, color: AppTheme.textSoft),
                cell(tr('Soni'), 42, fw: FontWeight.bold, color: AppTheme.textSoft),
                cell(tr('Tushum'), 78, fw: FontWeight.bold, color: AppTheme.textSoft),
                cell(tr('Tannarx'), 72, fw: FontWeight.bold, color: AppTheme.textSoft),
                cell(tr('Foyda'), 78, fw: FontWeight.bold, color: AppTheme.textSoft),
                cell(tr('Marja'), 50, fw: FontWeight.bold, color: AppTheme.textSoft),
              ]),
            ),
            for (final e in sorted)
              InkWell(
                onTap: e['menu_item_id'] == null
                    ? null
                    : () => Navigator.push(context, MaterialPageRoute(
                        builder: (_) => DishDetailPage(
                          id: (e['menu_item_id'] as num).toInt(),
                          name: e['name']?.toString() ?? '',
                          from: _from, to: _to))),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border.withValues(alpha: 0.4)))),
                  child: Row(children: [
                    cell(e['name']?.toString() ?? '', 150, a: TextAlign.left),
                    cell(_n(e['qty']).toString(), 42),
                    cell(_money(_n(e['revenue'])), 78),
                    cell(_money(_n(e['cost'])), 72, color: AppTheme.textSoft),
                    cell(_money(_n(e['profit'])), 78, color: _n(e['profit']) < 0 ? Colors.red : Colors.green, fw: FontWeight.w600),
                    cell('${_n(e['margin'])}%', 50, color: marginColor(_n(e['margin'])), fw: FontWeight.w600),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    ]));
  }
}

// ==== BITTA BLYUDO detali: davr bo'yicha KPI + kunlik/soatlik dinamika ====
class DishDetailPage extends StatefulWidget {
  final int id;
  final String name;
  final DateTime from;
  final DateTime to;
  const DishDetailPage({super.key, required this.id, required this.name, required this.from, required this.to});
  @override
  State<DishDetailPage> createState() => _DishDetailPageState();
}

class _DishDetailPageState extends State<DishDetailPage> {
  Map<String, dynamic>? _d;
  bool _loading = true;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  String _ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final res = await ApiService.get('/reports/dish/${widget.id}?from=${_ymd(widget.from)}&to=${_ymd(widget.to)}');
      if (!mounted) return;
      setState(() { _d = res is Map ? Map<String, dynamic>.from(res) : null; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  num _n(dynamic v) => v is num ? v : (num.tryParse(v?.toString() ?? '0') ?? 0);

  String _money(num v) {
    final neg = v < 0;
    final s = v.abs().round().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return (neg ? '-' : '') + buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([AppTheme.instance, Lang.instance]),
      builder: (_, __) => Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(
          backgroundColor: AppTheme.card,
          iconTheme: IconThemeData(color: AppTheme.text),
          title: Text(widget.name, style: TextStyle(color: AppTheme.text)),
          actions: [IconButton(icon: Icon(Icons.refresh, color: AppTheme.text), onPressed: _load)],
        ),
        body: _loading
            ? Center(child: CircularProgressIndicator(color: AppTheme.accent))
            : _error != null
                ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('${tr('Xato')}: $_error', style: const TextStyle(color: Colors.red))))
                : _body(),
      ),
    );
  }

  Widget _body() {
    final d = _d;
    if (d == null) return Center(child: Text(tr('Ma\'lumot yo\'q'), style: TextStyle(color: AppTheme.textSoft)));
    final byDay = (d['by_day'] as List?)?.cast<dynamic>() ?? [];
    final byHour = (d['by_hour'] as List?)?.cast<dynamic>() ?? [];
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
      children: [
        Text('${_ymd(widget.from)}  —  ${_ymd(widget.to)}', style: TextStyle(color: AppTheme.textSoft, fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _kpi(tr('Sotildi (dona)'), _n(d['qty']).toString(), Colors.blue, Icons.tag),
          _kpi(tr('Tushum'), _money(_n(d['revenue'])), Colors.green, Icons.payments),
          _kpi(tr('Tannarx'), _money(_n(d['cost'])), Colors.orange, Icons.inventory_2),
          _kpi(tr('Foyda'), _money(_n(d['profit'])), _n(d['profit']) < 0 ? Colors.red : Colors.teal, Icons.savings),
          _kpi(tr('Marja'), '${_n(d['margin'])}%', Colors.indigo, Icons.percent),
          _kpi(tr('Zakazlar'), _n(d['orders']).toString(), Colors.purple, Icons.receipt_long),
        ]),
        const SizedBox(height: 18),
        _card(tr('Kunlik sotuv (dona)'), _bar(byDay, (e) => (e['d']?.toString() ?? '').replaceAll(RegExp(r'^\d{4}-'), ''), (e) => _n(e['qty']))),
        _card(tr('Kunlik tushum'), _bar(byDay, (e) => (e['d']?.toString() ?? '').replaceAll(RegExp(r'^\d{4}-'), ''), (e) => _n(e['revenue']))),
        _card(tr('Soat bo\'yicha (dona)'), _bar(byHour, (e) => '${_n(e['h'])}', (e) => _n(e['qty']))),
      ],
    );
  }

  Widget _kpi(String label, String value, Color color, IconData icon) => Container(
        width: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(child: Text(label, style: TextStyle(color: AppTheme.textSoft, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: AppTheme.text, fontSize: 18, fontWeight: FontWeight.bold)),
        ]),
      );

  Widget _card(String title, Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppTheme.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 12),
          child,
        ]),
      );

  Widget _bar(List data, String Function(dynamic) label, num Function(dynamic) value) {
    if (data.isEmpty) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(tr('Ma\'lumot yo\'q'), style: TextStyle(color: AppTheme.textSoft, fontSize: 12)));
    }
    num maxV = 0;
    for (final e in data) { final v = value(e); if (v > maxV) maxV = v; }
    return SizedBox(
      height: 150,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final e in data)
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
              Text(_money(value(e)), style: TextStyle(fontSize: 8, color: AppTheme.textSoft), maxLines: 1, overflow: TextOverflow.clip),
              const SizedBox(height: 2),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                height: (maxV > 0 ? (value(e) / maxV * 110) : 2).clamp(2, 110).toDouble(),
                decoration: BoxDecoration(color: AppTheme.accent, borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
              ),
              const SizedBox(height: 4),
              Text(label(e), style: TextStyle(fontSize: 8, color: AppTheme.textSoft), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
      ]),
    );
  }
}

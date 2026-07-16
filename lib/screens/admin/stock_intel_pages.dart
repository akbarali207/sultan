import 'package:flutter/material.dart';
import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../../core/lang.dart';

/// Sklad intellekti sahifalari:
///  - [IngredientTimelinePage] — bitta mahsulot bo'yicha barcha harakatlar tarixi
///  - [IngredientAnalyticsPage] — narx/sarf dinamikasi, prognoz, KPI
///  - [AbcXyzPage] — ABC/XYZ tahlil (sarf qiymati + barqarorlik)
///  - [AuditLogPage] — o'zgarmas audit jurnali
///  - [ConsistencyPage] — ma'lumotlar muvofiqligi tekshiruvi + tuzatish
///  - [showCostingSettingsDialog] — tannarx usuli va sklad sozlamalari

// ═══════════════ UMUMIY YORDAMCHILAR ═══════════════

num _n(dynamic v) => v is num ? v : (num.tryParse(v?.toString() ?? '') ?? 0);

String _two(int n) => n.toString().padLeft(2, '0');

DateTime? _parseTs(dynamic s) {
  if (s == null) return null;
  return DateTime.tryParse(s.toString())?.toLocal();
}

/// Pul: 1234567 -> '1 234 567'
String _money(dynamic v) {
  if (v == null) return '—';
  final n = _n(v);
  final neg = n < 0;
  final s = n.abs().round().toString();
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return (neg ? '-' : '') + b.toString();
}

/// ISO -> 'YYYY-MM-DD'
String _d(dynamic s) {
  final t = _parseTs(s);
  if (t == null) {
    final raw = s?.toString() ?? '';
    if (raw.isEmpty) return '—';
    return raw.length >= 10 ? raw.substring(0, 10) : raw;
  }
  return '${t.year}-${_two(t.month)}-${_two(t.day)}';
}

/// ISO -> 'YYYY-MM-DD HH:MM'
String _dt(dynamic s) {
  final t = _parseTs(s);
  if (t == null) return _d(s);
  return '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';
}

/// ISO -> 'HH:MM'
String _hm(dynamic s) {
  final t = _parseTs(s);
  if (t == null) return '';
  return '${_two(t.hour)}:${_two(t.minute)}';
}

/// Miqdor: 12.50 -> '12.5', 12.00 -> '12'
String _qtyStr(dynamic v) {
  if (v == null) return '—';
  var s = _n(v).toDouble().toStringAsFixed(2);
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  return s;
}

/// Sarlavhali karta (uy uslubi)
Widget _card(String title, Widget child) => Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 12),
        child,
      ]),
    );

Widget _emptyNote() => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(tr('Ma\'lumot yo\'q'), style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
    );

/// Tanlanadigan chip (davr/filtr)
Widget _selChip(String label, bool sel, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: sel ? AppTheme.accent : AppTheme.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: sel ? AppTheme.accent : AppTheme.border),
          ),
          child: Text(label,
              style: TextStyle(
                  color: sel ? AppTheme.onAccent : AppTheme.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ),
      ),
    );

/// Vertikal ustunli grafik (uy uslubi — paketlarsiz)
Widget _vBars(List<dynamic> data, String Function(dynamic) label, num Function(dynamic) value,
    {String Function(num)? fmt}) {
  if (data.isEmpty) return _emptyNote();
  num maxV = 0;
  for (final e in data) {
    final v = value(e);
    if (v > maxV) maxV = v;
  }
  final f = fmt ?? _money;
  return SizedBox(
    height: 150,
    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
      for (final e in data)
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text(f(value(e)),
                style: TextStyle(fontSize: 8, color: AppTheme.textSoft),
                maxLines: 1,
                overflow: TextOverflow.clip),
            const SizedBox(height: 2),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              height: (maxV > 0 ? (value(e) / maxV * 110) : 2).clamp(2, 110).toDouble(),
              decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
            ),
            const SizedBox(height: 4),
            Text(label(e),
                style: TextStyle(fontSize: 8, color: AppTheme.textSoft),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ]),
        ),
    ]),
  );
}

/// 'YYYY-MM' -> 'MM'
String _mm(dynamic m) {
  final s = m?.toString() ?? '';
  return s.contains('-') ? s.split('-').last : s;
}

// ═══════════════ 1. MAHSULOT TARIXI (timeline) ═══════════════

class IngredientTimelinePage extends StatefulWidget {
  final int ingredientId;
  final String ingredientName;
  const IngredientTimelinePage(
      {super.key, required this.ingredientId, required this.ingredientName});

  @override
  State<IngredientTimelinePage> createState() => _IngredientTimelinePageState();
}

class _IngredientTimelinePageState extends State<IngredientTimelinePage> {
  final List<Map<String, dynamic>> _events = [];
  bool _isLoading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await ApiService.get('/stock/${widget.ingredientId}/timeline?limit=150');
      if (!mounted) return;
      if (res is List) {
        setState(() {
          _events
            ..clear()
            ..addAll(res.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
          _hasMore = res.length >= 150;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = (res is Map && res['message'] != null)
              ? res['message'].toString()
              : tr('Ma\'lumot yo\'q');
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _events.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      // Kompound kursor: oxirgi qatorning cts (mikrosekund-aniq) + src + eid — bir xil
      // vaqtdagi hodisalar chegarada tushib qolmasligi uchun. 'cts' ni ishlatamiz ('ts'
      // JSON'da millisekundgacha kesiladi — mikrosekundli hodisalar chiqib ketardi).
      final last = _events.last;
      final before = Uri.encodeComponent(last['cts']?.toString() ?? last['ts']?.toString() ?? '');
      final beforeSrc = last['src']?.toString() ?? '';
      final beforeEid = last['eid']?.toString() ?? '';
      final res = await ApiService.get(
          '/stock/${widget.ingredientId}/timeline?limit=150&before=$before'
          '&before_src=$beforeSrc&before_eid=$beforeEid');
      if (!mounted) return;
      if (res is List) {
        setState(() {
          _events.addAll(res.whereType<Map>().map((e) => Map<String, dynamic>.from(e)));
          _hasMore = res.length >= 150;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Color _kindColor(String k) {
    switch (k) {
      case 'purchase':
      case 'purchase_legacy':
        return Colors.green;
      case 'sale':
        return Colors.blue;
      case 'writeoff':
      case 'return':
        return Colors.red;
      case 'pf':
        return Colors.purple;
      case 'restore':
        return Colors.teal;
      case 'inventory':
        return Colors.orange;
      default:
        return Colors.grey; // edit / audit / adjust
    }
  }

  String _kindLabel(String k) {
    switch (k) {
      case 'purchase':
        return tr('Kirim');
      case 'purchase_legacy':
        return tr('Kirim (eski)');
      case 'sale':
        return tr('Savdo');
      case 'pf':
        return tr('P/F');
      case 'writeoff':
        return tr('Spisaniya');
      case 'return':
        return tr('Qaytarish');
      case 'inventory':
        return tr('Inventarizatsiya');
      case 'restore':
        return tr('Tiklash');
      case 'adjust':
        return tr('Korrektirovka');
      case 'edit':
        return tr('Tahrir');
      case 'audit':
        return tr('Audit');
      default:
        return k;
    }
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
          title: Text('${widget.ingredientName} — ${tr('Tarix')}',
              style: TextStyle(color: AppTheme.text)),
          actions: [IconButton(icon: Icon(Icons.refresh, color: AppTheme.text), onPressed: _load)],
        ),
        body: _isLoading
            ? Center(child: CircularProgressIndicator(color: AppTheme.accent))
            : _error != null
                ? Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('${tr('Xato')}: $_error',
                            style: const TextStyle(color: Colors.red))))
                : _events.isEmpty
                    ? Center(child: _emptyNote())
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
                          itemCount: _events.length + 1,
                          itemBuilder: (_, i) {
                            if (i == _events.length) return _footer();
                            return _eventRow(_events[i], i == _events.length - 1 && !_hasMore);
                          },
                        ),
                      ),
      ),
    );
  }

  Widget _footer() {
    if (!_hasMore) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: _loadingMore ? null : _loadMore,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.accent,
            side: BorderSide(color: AppTheme.accent),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
          icon: _loadingMore
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent))
              : const Icon(Icons.expand_more, size: 18),
          label: Text(tr('Yana yuklash'), style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _eventRow(Map<String, dynamic> e, bool isLast) {
    final kind = e['kind']?.toString() ?? '';
    final c = _kindColor(kind);
    final hasQty = e['qty'] != null;
    final q = _n(e['qty']).toDouble();
    final user = (e['user_name'] ?? '').toString();
    final detail = (e['detail'] ?? '').toString();
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Chap: sana + soat
        SizedBox(
          width: 80,
          child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_d(e['ts']),
                style: TextStyle(color: AppTheme.text, fontSize: 11.5, fontWeight: FontWeight.bold)),
            Text(_hm(e['ts']), style: TextStyle(color: AppTheme.textSoft, fontSize: 10.5)),
          ]),
        ),
        const SizedBox(width: 10),
        // Nuqta + chiziq
        Column(children: [
          const SizedBox(height: 3),
          Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          Expanded(child: Container(width: 2, color: isLast ? Colors.transparent : AppTheme.border)),
        ]),
        const SizedBox(width: 10),
        // O'ng: mazmun
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                    child: Text((e['title'] ?? '').toString(),
                        style: TextStyle(
                            color: AppTheme.text, fontSize: 13.5, fontWeight: FontWeight.w600))),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: c.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(999)),
                  child: Text(_kindLabel(kind),
                      style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
              ]),
              if (hasQty || e['unit_cost'] != null || e['amount'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (hasQty)
                          Text(q >= 0 ? '+${_qtyStr(q)}' : _qtyStr(q),
                              style: TextStyle(
                                  color: q < 0 ? Colors.red : Colors.green,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800)),
                        if (e['unit_cost'] != null)
                          Text('× ${_money(e['unit_cost'])}',
                              style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
                        if (e['amount'] != null)
                          Text('= ${_money(e['amount'])}',
                              style: TextStyle(
                                  color: AppTheme.text,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600)),
                      ]),
                ),
              if (user.isNotEmpty || detail.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text([user, detail].where((s) => s.isNotEmpty).join(' · '),
                      style: TextStyle(color: AppTheme.textSoft, fontSize: 11),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
            ]),
          ),
        ),
      ]),
    );
  }
}

// ═══════════════ 2. MAHSULOT ANALITIKASI ═══════════════

class IngredientAnalyticsPage extends StatefulWidget {
  final int ingredientId;
  final String ingredientName;
  const IngredientAnalyticsPage(
      {super.key, required this.ingredientId, required this.ingredientName});

  @override
  State<IngredientAnalyticsPage> createState() => _IngredientAnalyticsPageState();
}

class _IngredientAnalyticsPageState extends State<IngredientAnalyticsPage> {
  int _days = 90;
  Map<String, dynamic>? _data;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res =
          await ApiService.get('/stock/${widget.ingredientId}/analytics?days=$_days');
      if (!mounted) return;
      if (res is Map && res['ingredient'] != null) {
        setState(() {
          _data = Map<String, dynamic>.from(res);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = (res is Map && res['message'] != null)
              ? res['message'].toString()
              : tr('Ma\'lumot yo\'q');
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _isLoading = false;
      });
    }
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
          title: Text(widget.ingredientName, style: TextStyle(color: AppTheme.text)),
          actions: [IconButton(icon: Icon(Icons.refresh, color: AppTheme.text), onPressed: _load)],
        ),
        body: _isLoading
            ? Center(child: CircularProgressIndicator(color: AppTheme.accent))
            : _error != null
                ? Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('${tr('Xato')}: $_error',
                            style: const TextStyle(color: Colors.red))))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
                      children: [_periodBar(), const SizedBox(height: 14), ..._body()],
                    ),
                  ),
      ),
    );
  }

  Widget _periodBar() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final d in const [30, 90, 180, 365])
            _selChip('$d ${tr('kun')}', _days == d, () {
              setState(() => _days = d);
              _load();
            }),
        ]),
      );

  List<Widget> _body() {
    final d = _data;
    if (d == null) return [Center(child: _emptyNote())];
    final ing = Map<String, dynamic>.from(d['ingredient'] ?? {});
    final price = Map<String, dynamic>.from(d['price'] ?? {});
    final usage = Map<String, dynamic>.from(d['usage'] ?? {});
    final fc = Map<String, dynamic>.from(d['forecast'] ?? {});
    final prof =
        d['profitability'] is Map ? Map<String, dynamic>.from(d['profitability']) : null;
    final unit = ing['unit']?.toString() ?? '';

    // Narx o'zgarishi (davr boshidan oxirigacha)
    final cp = price['change_pct'];
    String cpText = '—';
    Color cpColor = AppTheme.textSoft;
    if (cp != null) {
      final v = _n(cp).toDouble();
      cpText = '${v > 0 ? '▲ ' : (v < 0 ? '▼ ' : '')}${v.abs().toStringAsFixed(1)}%';
      cpColor = v > 0 ? Colors.red : (v < 0 ? Colors.green : AppTheme.textSoft);
    }
    final turnover = d['turnover'];
    final losses = _n(d['losses_value']);
    final priceMonthly = (price['monthly'] as List?) ?? const [];
    final usageMonthly = (usage['monthly'] as List?) ?? const [];

    return [
      Wrap(spacing: 10, runSpacing: 10, children: [
        _kpi(tr('Qoldiq'), '${_qtyStr(ing['stock_quantity'])} $unit', Colors.blue,
            Icons.inventory_2, sub: _money(d['stock_value'])),
        _kpi(tr('O\'rtacha narx'), _money(price['avg_price']), Colors.teal, Icons.payments),
        _kpi(tr('Min narx'), _money(price['min_price']), Colors.green, Icons.south),
        _kpi(tr('Maks narx'), _money(price['max_price']), Colors.orange, Icons.north),
        _kpi(tr('Narx o\'zgarishi'), cpText, cpColor, Icons.percent, valueColor: cpColor),
        _kpi(tr('Zakupkalar soni'), '${_n(price['purchase_count']).round()}', Colors.indigo,
            Icons.shopping_cart),
        _kpi(tr('Kunlik sarf'), '${_qtyStr(usage['daily_avg'])} $unit', Colors.purple,
            Icons.speed),
        _kpi(tr('Oborachivayemost'),
            turnover == null ? '—' : '${_n(turnover).toStringAsFixed(1)}×', Colors.blueGrey,
            Icons.sync),
        _kpi(tr('Food Cost ulushi'), '${_n(d['food_cost_share_pct']).toStringAsFixed(1)}%',
            AppTheme.accent, Icons.pie_chart),
        _kpi(tr('Yo\'qotishlar'), _money(losses), Colors.red, Icons.warning_amber,
            valueColor: losses > 0 ? Colors.red : null),
      ]),
      const SizedBox(height: 18),
      _forecastCard(fc, prof, unit),
      _card(tr('Narx dinamikasi (12 oy)'),
          _vBars(priceMonthly, (e) => _mm(e['month']), (e) => _n(e['avg_price']))),
      _card(
          tr('Sarf dinamikasi (12 oy)'),
          _vBars(usageMonthly, (e) => _mm(e['month']), (e) => _n(e['used']),
              fmt: (v) => _qtyStr(v))),
    ];
  }

  Widget _kpi(String label, String value, Color color, IconData icon,
      {String? sub, Color? valueColor}) {
    return Container(
      width: 158,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
              child: Text(label,
                  style: TextStyle(color: AppTheme.textSoft, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis)),
        ]),
        const SizedBox(height: 8),
        Text(value,
            style: TextStyle(
                color: valueColor ?? AppTheme.text, fontSize: 17, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        if (sub != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(sub,
                style: TextStyle(color: AppTheme.textSoft, fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
      ]),
    );
  }

  Widget _forecastCard(Map<String, dynamic> fc, Map<String, dynamic>? prof, String unit) {
    final dl = fc['days_left'];
    Widget head;
    if (dl == null) {
      head = Text(tr('Sarf yo\'q'),
          style: TextStyle(color: AppTheme.textSoft, fontSize: 16, fontWeight: FontWeight.bold));
    } else {
      final n = _n(dl).round();
      final c = n < 7 ? Colors.red : (n < 14 ? Colors.orange : Colors.green);
      head = Text('$n ${tr('kunga yetadi')}',
          style: TextStyle(color: c, fontSize: 18, fontWeight: FontWeight.bold));
    }
    Widget row(String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(
                child: Text(label, style: TextStyle(color: AppTheme.textSoft, fontSize: 12.5))),
            Text(value,
                style: TextStyle(
                    color: color ?? AppTheme.text, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        );
    return _card(
        tr('Prognoz'),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          head,
          const SizedBox(height: 10),
          row(tr('Tugash sanasi'), fc['stockout_date'] == null ? '—' : _d(fc['stockout_date'])),
          row(tr('Keyingi zakupka'),
              fc['next_purchase_date'] == null ? '—' : _d(fc['next_purchase_date'])),
          row(tr('Tavsiya min qoldiq'), '${_qtyStr(fc['recommended_min'])} $unit'),
          row(tr('Tavsiya zakupka hajmi'), '${_qtyStr(fc['recommended_order'])} $unit'),
          if (prof != null) ...[
            Divider(color: AppTheme.border, height: 18),
            row(tr('Rentabellik'),
                '${_money(prof['margin'])} (${_n(prof['margin_pct']).toStringAsFixed(1)}%)',
                color: _n(prof['margin']) < 0 ? Colors.red : Colors.green),
          ],
        ]));
  }
}

// ═══════════════ 3. ABC/XYZ TAHLIL ═══════════════

class AbcXyzPage extends StatefulWidget {
  const AbcXyzPage({super.key});

  @override
  State<AbcXyzPage> createState() => _AbcXyzPageState();
}

class _AbcXyzPageState extends State<AbcXyzPage> {
  int _days = 90;
  String _filter = 'all'; // all | A | B | C | problem
  Map<String, dynamic>? _data;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await ApiService.get('/stock/analytics/abc-xyz?days=$_days');
      if (!mounted) return;
      if (res is Map && res['items'] != null) {
        setState(() {
          _data = Map<String, dynamic>.from(res);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = (res is Map && res['message'] != null)
              ? res['message'].toString()
              : tr('Ma\'lumot yo\'q');
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _isLoading = false;
      });
    }
  }

  Color _abcColor(String a) =>
      a == 'A' ? Colors.green : (a == 'B' ? Colors.orange : Colors.grey);
  Color _xyzColor(String x) => x == 'X' ? Colors.green : (x == 'Y' ? Colors.orange : Colors.red);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([AppTheme.instance, Lang.instance]),
      builder: (_, __) => Scaffold(
        backgroundColor: AppTheme.bg,
        appBar: AppBar(
          backgroundColor: AppTheme.card,
          iconTheme: IconThemeData(color: AppTheme.text),
          title: Text(tr('ABC/XYZ tahlil'), style: TextStyle(color: AppTheme.text)),
          actions: [IconButton(icon: Icon(Icons.refresh, color: AppTheme.text), onPressed: _load)],
        ),
        body: _isLoading
            ? Center(child: CircularProgressIndicator(color: AppTheme.accent))
            : _error != null
                ? Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('${tr('Xato')}: $_error',
                            style: const TextStyle(color: Colors.red))))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
                      children: _body(),
                    ),
                  ),
      ),
    );
  }

  List<Widget> _body() {
    final d = _data;
    if (d == null) return [Center(child: _emptyNote())];
    final sum = Map<String, dynamic>.from(d['summary'] ?? {});
    final items = ((d['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final filtered = items.where((it) {
      switch (_filter) {
        case 'A':
        case 'B':
        case 'C':
          return it['abc']?.toString() == _filter;
        case 'problem':
          return ((it['problems'] as List?) ?? const []).isNotEmpty;
        default:
          return true;
      }
    }).toList();

    return [
      // Davr
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (final dd in const [30, 90, 180])
            _selChip('$dd ${tr('kun')}', _days == dd, () {
              setState(() => _days = dd);
              _load();
            }),
        ]),
      ),
      const SizedBox(height: 12),
      // Xulosa chiplar
      Wrap(spacing: 6, runSpacing: 6, children: [
        _sumChip('A', sum['A'], Colors.green),
        _sumChip('B', sum['B'], Colors.orange),
        _sumChip('C', sum['C'], Colors.grey),
        _sumChip('X', sum['X'], Colors.green),
        _sumChip('Y', sum['Y'], Colors.orange),
        _sumChip('Z', sum['Z'], Colors.red),
        _sumChip(tr('Harakatsiz'), sum['dead'], Colors.grey),
        _sumChip(tr('Minus'), sum['minus'], Colors.red),
        _sumChip(tr('Kam qoldi'), sum['low'], Colors.orange),
      ]),
      const SizedBox(height: 10),
      // Tushuntirish — bosib ochiladi (foydalanuvchi ABC/XYZ ma'nosini tushunishi uchun)
      Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          leading: Icon(Icons.help_outline, color: AppTheme.accent, size: 20),
          title: Text(tr('ABC/XYZ nima degani? (bosing)'),
              style: TextStyle(color: AppTheme.text, fontSize: 14, fontWeight: FontWeight.w600)),
          iconColor: AppTheme.accent,
          collapsedIconColor: AppTheme.accent,
          backgroundColor: AppTheme.card,
          collapsedBackgroundColor: AppTheme.card,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10), side: BorderSide(color: AppTheme.border)),
          collapsedShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10), side: BorderSide(color: AppTheme.border)),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          children: [
            Align(
                alignment: Alignment.centerLeft,
                child: Text(tr('ABC — muhimlik (qancha pul beradi)'),
                    style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 13))),
            const SizedBox(height: 6),
            _helpRow('A', Colors.green, tr('~20% mahsulot — sarfning ~80%. Eng muhim (go\'sht, asosiy). Doim nazorat.')),
            _helpRow('B', Colors.orange, tr('Keyingi ~15%. O\'rtacha ahamiyat.')),
            _helpRow('C', Colors.grey, tr('Qolgan ~5% — ko\'p mayda, kam pul. Kam e\'tibor.')),
            const SizedBox(height: 10),
            Align(
                alignment: Alignment.centerLeft,
                child: Text(tr('XYZ — barqarorlik (qanchalik tekis sarflanadi)'),
                    style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 13))),
            const SizedBox(height: 6),
            _helpRow('X', Colors.green, tr('Barqaror, oldindan bilsa bo\'ladi. Rejalash oson.')),
            _helpRow('Y', Colors.orange, tr('O\'rtacha tebranish.')),
            _helpRow('Z', Colors.red, tr('Notekis, kutilmagan sarf. Rejalash qiyin.')),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: AppTheme.bg, borderRadius: BorderRadius.circular(8)),
              child: Text(
                  tr('Birgalikda: A-X — qimmat + barqaror → doim zaxira ushlab tur. A-Z — qimmat + tebranadi → ehtiyotkorlik bilan, talabga qarab. C-Z — arzon + kam → deyarli e\'tibor bermasa ham bo\'ladi.'),
                  style: TextStyle(color: AppTheme.textSoft, fontSize: 12, height: 1.4)),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      // Filtr
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          _selChip(tr('Barchasi'), _filter == 'all', () => setState(() => _filter = 'all')),
          _selChip('A', _filter == 'A', () => setState(() => _filter = 'A')),
          _selChip('B', _filter == 'B', () => setState(() => _filter = 'B')),
          _selChip('C', _filter == 'C', () => setState(() => _filter = 'C')),
          _selChip(tr('Muammoli'), _filter == 'problem',
              () => setState(() => _filter = 'problem')),
        ]),
      ),
      const SizedBox(height: 12),
      if (filtered.isEmpty) Center(child: _emptyNote()),
      for (final it in filtered) _itemRow(it),
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(tr('A — sarfning 80%, B — 15%, C — 5%. X — barqaror, Z — notekis sarf'),
            style: TextStyle(color: AppTheme.textSoft, fontSize: 11),
            textAlign: TextAlign.center),
      ),
    ];
  }

  Widget _sumChip(String label, dynamic count, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.withValues(alpha: 0.4)),
        ),
        child: Text('$label: ${_n(count).round()}',
            style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
      );

  Widget _letter(String ch, Color c) => Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.withValues(alpha: 0.15), shape: BoxShape.circle),
        child: Text(ch, style: TextStyle(color: c, fontWeight: FontWeight.bold, fontSize: 13)),
      );

  // Tushuntirish qatori: rangli harf (A/B/C/X/Y/Z) + izoh
  Widget _helpRow(String ch, Color c, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _letter(ch, c),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: TextStyle(color: AppTheme.textSoft, fontSize: 12, height: 1.3))),
        ]),
      );

  Widget _tag(String label, Color c) => Container(
        margin: const EdgeInsets.only(left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
            color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(6)),
        child: Text(label, style: TextStyle(color: c, fontSize: 9.5, fontWeight: FontWeight.w700)),
      );

  Widget _itemRow(Map<String, dynamic> it) {
    final abc = it['abc']?.toString() ?? '';
    final xyz = it['xyz']?.toString() ?? '';
    final unit = it['unit']?.toString() ?? '';
    final category = it['category']?.toString() ?? '';
    final problems = ((it['problems'] as List?) ?? const []).map((e) => e.toString()).toList();
    return InkWell(
      onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => IngredientAnalyticsPage(
                  ingredientId: _n(it['id']).toInt(),
                  ingredientName: it['name']?.toString() ?? ''))),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border)),
        child: Row(children: [
          _letter(abc, _abcColor(abc)),
          const SizedBox(width: 4),
          _letter(xyz, _xyzColor(xyz)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                    child: Text(it['name']?.toString() ?? '',
                        style: TextStyle(
                            color: AppTheme.text, fontSize: 13.5, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis)),
                if (problems.contains('minus')) _tag(tr('Minus'), Colors.red),
                if (problems.contains('dead')) _tag(tr('Harakatsiz'), Colors.grey),
                if (problems.contains('low')) _tag(tr('Kam qoldi'), Colors.orange),
              ]),
              const SizedBox(height: 2),
              Text(
                  [
                    if (category.isNotEmpty) category,
                    '${_qtyStr(it['consumption_qty'])} $unit',
                  ].join(' · '),
                  style: TextStyle(color: AppTheme.textSoft, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_money(it['consumption_value']),
                style:
                    TextStyle(color: AppTheme.text, fontSize: 13, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text('${tr('Qoldiq')}: ${_qtyStr(it['stock_quantity'])}',
                style: TextStyle(color: AppTheme.textSoft, fontSize: 10)),
          ]),
        ]),
      ),
    );
  }
}

// ═══════════════ 4. AUDIT JURNALI ═══════════════

class AuditLogPage extends StatefulWidget {
  const AuditLogPage({super.key});

  @override
  State<AuditLogPage> createState() => _AuditLogPageState();
}

class _AuditLogPageState extends State<AuditLogPage> {
  final TextEditingController _actionCtrl = TextEditingController();
  String _entity = '';
  String? _from;
  String? _to;
  List<Map<String, dynamic>> _rows = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _actionCtrl.dispose();
    super.dispose();
  }

  // Amal kodini (stock.incoming ...) tushunarli nomga aylantiramiz
  String _actionLabel(String a) {
    switch (a) {
      case 'stock.incoming': return tr('Sklad kirim');
      case 'ingredient.edit': return tr('Mahsulot tahrirlandi');
      case 'ingredient.create': case 'stock.create': return tr('Mahsulot qo\'shildi');
      case 'ingredient.delete': return tr('Mahsulot o\'chirildi');
      case 'inventory.close': return tr('Inventarizatsiya yopildi');
      case 'lot.writeoff': return tr('Partiya spisan');
      case 'lot.return': return tr('Partiya qaytarildi');
      case 'lot.block': return tr('Partiya bloklandi');
      case 'lot.pay': return tr('Partiya to\'lovi');
      case 'supplier.create': return tr('Postavshik qo\'shildi');
      case 'supplier.update': return tr('Postavshik tahrirlandi');
      case 'supplier.delete': return tr('Postavshik o\'chirildi');
      case 'supplier.pay': return tr('Postavshikka to\'lov');
      case 'settings.update': return tr('Sozlama o\'zgardi');
      case 'consistency.fix': return tr('Muvofiqlik tuzatildi');
      default: return a.replaceAll('.', ' • ');
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      var q = '/reports/audit?limit=100';
      final a = _actionCtrl.text.trim();
      if (a.isNotEmpty) q += '&action=${Uri.encodeComponent(a)}';
      if (_entity.isNotEmpty) q += '&entity_type=${Uri.encodeComponent(_entity)}';
      if (_from != null) q += '&from=$_from';
      if (_to != null) q += '&to=$_to';
      final res = await ApiService.get(q);
      if (!mounted) return;
      if (res is List) {
        setState(() {
          _rows = res.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = (res is Map && res['message'] != null)
              ? res['message'].toString()
              : tr('Ma\'lumot yo\'q');
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _isLoading = false;
      });
    }
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
          title: Text(tr('Audit jurnali'), style: TextStyle(color: AppTheme.text)),
          actions: [IconButton(icon: Icon(Icons.refresh, color: AppTheme.text), onPressed: _load)],
        ),
        body: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 0), child: _filters()),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator(color: AppTheme.accent))
                : _error != null
                    ? Center(
                        child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text('${tr('Xato')}: $_error',
                                style: const TextStyle(color: Colors.red))))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
                          children: [
                            if (_rows.isEmpty) Center(child: _emptyNote()),
                            for (final r in _rows) _logRow(r),
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                  tr('Jurnal o\'zgarmas — yozuvlarni o\'chirib bo\'lmaydi'),
                                  style: TextStyle(color: AppTheme.textSoft, fontSize: 11),
                                  textAlign: TextAlign.center),
                            ),
                          ],
                        ),
                      ),
          ),
        ]),
      ),
    );
  }

  Widget _filters() => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border)),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: TextField(
                controller: _actionCtrl,
                onSubmitted: (_) => _load(),
                style: TextStyle(color: AppTheme.text, fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: tr('Amal (action)'),
                  labelStyle: TextStyle(color: AppTheme.textSoft, fontSize: 12),
                  prefixIcon: Icon(Icons.search, size: 18, color: AppTheme.textSoft),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppTheme.border)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppTheme.accent)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.border)),
              child: DropdownButton<String>(
                value: _entity,
                underline: const SizedBox.shrink(),
                dropdownColor: AppTheme.card,
                style: TextStyle(color: AppTheme.text, fontSize: 13),
                items: [
                  DropdownMenuItem(value: '', child: Text(tr('Barchasi'))),
                  for (final t in const [
                    'ingredient',
                    'stock_lot',
                    'supplier',
                    'inventory',
                    'setting',
                    'consistency'
                  ])
                    DropdownMenuItem(value: t, child: Text(t)),
                ],
                onChanged: (v) {
                  setState(() => _entity = v ?? '');
                  _load();
                },
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _dateBtn(true),
            const SizedBox(width: 8),
            _dateBtn(false),
            if (_from != null || _to != null)
              IconButton(
                icon: Icon(Icons.clear, size: 18, color: AppTheme.textSoft),
                onPressed: () {
                  setState(() {
                    _from = null;
                    _to = null;
                  });
                  _load();
                },
              ),
          ]),
        ]),
      );

  Widget _dateBtn(bool isFrom) {
    final v = isFrom ? _from : _to;
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final init = v != null ? (DateTime.tryParse(v) ?? now) : now;
        final r = await showDatePicker(
            context: context,
            initialDate: init,
            firstDate: DateTime(2023),
            lastDate: now.add(const Duration(days: 1)));
        if (r == null) return;
        final s = '${r.year}-${_two(r.month)}-${_two(r.day)}';
        setState(() {
          if (isFrom) {
            _from = s;
          } else {
            _to = s;
          }
        });
        _load();
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.border),
            color: AppTheme.bg),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.date_range, size: 15, color: AppTheme.textSoft),
          const SizedBox(width: 5),
          Text(v ?? (isFrom ? tr('Dan') : tr('Gacha')),
              style: TextStyle(
                  color: v == null ? AppTheme.textSoft : AppTheme.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  Widget _logRow(Map<String, dynamic> r) {
    final reason = (r['reason'] ?? '').toString();
    return InkWell(
      onTap: () => _showDetail(r),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                  color: AppTheme.accentSoft, borderRadius: BorderRadius.circular(6)),
              child: Text(_actionLabel((r['action'] ?? '').toString()),
                  style: TextStyle(
                      color: AppTheme.accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'monospace')),
            ),
            const Spacer(),
            Text(_dt(r['created_at']), style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Icon(Icons.person, size: 13, color: AppTheme.textSoft),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                  [
                    (r['user_name'] ?? '').toString(),
                    (r['user_role'] ?? '').toString(),
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: TextStyle(color: AppTheme.text, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            if (r['entity_type'] != null)
              Text('${r['entity_type']}#${r['entity_id'] ?? ''}',
                  style: TextStyle(
                      color: AppTheme.textSoft, fontSize: 11, fontFamily: 'monospace')),
          ]),
          if (reason.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(reason,
                  style: TextStyle(
                      color: AppTheme.textSoft, fontSize: 11.5, fontStyle: FontStyle.italic),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ),
        ]),
      ),
    );
  }

  void _showDetail(Map<String, dynamic> r) {
    final oldV = r['old_value'] is Map
        ? Map<String, dynamic>.from(r['old_value'] as Map)
        : <String, dynamic>{};
    final newV = r['new_value'] is Map
        ? Map<String, dynamic>.from(r['new_value'] as Map)
        : <String, dynamic>{};
    final keys = <String>{...oldV.keys, ...newV.keys}.toList()..sort();
    String vs(dynamic v) => v == null ? '—' : v.toString();
    final reason = (r['reason'] ?? '').toString();

    final diffLines = <Widget>[];
    for (final k in keys) {
      final ov = vs(oldV[k]);
      final nv = vs(newV[k]);
      final changed = ov != nv;
      diffLines.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Text.rich(TextSpan(children: [
          TextSpan(
              text: '$k: ',
              style: TextStyle(
                  color: changed ? AppTheme.text : AppTheme.textSoft,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          TextSpan(
              text: ov,
              style: TextStyle(
                  color: changed ? Colors.red : AppTheme.textSoft,
                  fontSize: 12,
                  decoration: changed ? TextDecoration.lineThrough : null)),
          TextSpan(text: '  →  ', style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
          TextSpan(
              text: nv,
              style: TextStyle(
                  color: changed ? Colors.green : AppTheme.textSoft,
                  fontSize: 12,
                  fontWeight: changed ? FontWeight.w700 : FontWeight.normal)),
        ])),
      ));
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(_actionLabel((r['action'] ?? '').toString()),
            style: TextStyle(color: AppTheme.text, fontSize: 16, fontFamily: 'monospace')),
        content: SizedBox(
          width: (MediaQuery.of(context).size.width * 0.9).clamp(0.0, 440.0),
          child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_dt(r['created_at']),
                      style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(
                      [
                        (r['user_name'] ?? '').toString(),
                        (r['user_role'] ?? '').toString(),
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: TextStyle(color: AppTheme.text, fontSize: 12.5)),
                  if (r['entity_type'] != null)
                    Text('${r['entity_type']}#${r['entity_id'] ?? ''}',
                        style: TextStyle(
                            color: AppTheme.textSoft, fontSize: 12, fontFamily: 'monospace')),
                  if ((r['branch'] ?? '').toString().isNotEmpty)
                    Text(r['branch'].toString(),
                        style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
                  if ((r['ip'] ?? '').toString().isNotEmpty ||
                      (r['device'] ?? '').toString().isNotEmpty)
                    Text('${r['ip'] ?? ''}  ${r['device'] ?? ''}',
                        style: TextStyle(color: AppTheme.textSoft, fontSize: 10.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  if (reason.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(reason,
                          style: TextStyle(
                              color: AppTheme.textSoft,
                              fontSize: 12,
                              fontStyle: FontStyle.italic)),
                    ),
                  Divider(color: AppTheme.border, height: 18),
                  if (diffLines.isEmpty)
                    Text(tr('O\'zgarishlar yo\'q'),
                        style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
                  ...diffLines,
                ]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('Yopish'), style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════ 5. MUVOFIQLIK TEKSHIRUVI ═══════════════

class ConsistencyPage extends StatefulWidget {
  const ConsistencyPage({super.key});

  @override
  State<ConsistencyPage> createState() => _ConsistencyPageState();
}

class _ConsistencyPageState extends State<ConsistencyPage> {
  Map<String, dynamic>? _data;
  bool _isLoading = true;
  String? _error;
  final Set<String> _open = {};
  String? _fixingKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final res = await ApiService.get('/system/consistency');
      if (!mounted) return;
      if (res is Map && res['results'] != null) {
        setState(() {
          _data = Map<String, dynamic>.from(res);
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = (res is Map && res['message'] != null)
              ? res['message'].toString()
              : tr('Ma\'lumot yo\'q');
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _isLoading = false;
      });
    }
  }

  Color _sevColor(String s) {
    switch (s) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.amber;
      case 'info':
        return Colors.blue;
      default:
        return Colors.red; // error
    }
  }

  Future<void> _fix(Map<String, dynamic> r) async {
    final key = r['key']?.toString() ?? '';
    final fixNote = (r['fix_note'] ?? '').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('Tasdiqlash'), style: TextStyle(color: AppTheme.text)),
        content: Text('$fixNote ${tr('Davom etasizmi?')}'.trim(),
            style: TextStyle(color: AppTheme.text, fontSize: 13.5)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent, foregroundColor: AppTheme.onAccent),
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(tr('Ha')),
          ),
        ],
      ),
    );
    if (ok != true || _fixingKey != null || !mounted) return;
    setState(() => _fixingKey = key);
    try {
      final res = await ApiService.post('/system/consistency/fix', {'key': key},
          idempotencyKey: ApiService.newIdempotencyKey());
      if (!mounted) return;
      if (res is Map && res['ok'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('${_n(res['fixed']).round()} ${tr('ta tuzatildi')}'),
            backgroundColor: Colors.green));
        await _load();
      } else {
        final msg = (res is Map && res['message'] != null) ? res['message'].toString() : tr('Xato');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _fixingKey = null);
    }
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
          title: Text(tr('Muvofiqlik tekshiruvi'), style: TextStyle(color: AppTheme.text)),
          actions: [IconButton(icon: Icon(Icons.refresh, color: AppTheme.text), onPressed: _load)],
        ),
        body: _isLoading
            ? Center(child: CircularProgressIndicator(color: AppTheme.accent))
            : _error != null
                ? Center(
                    child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text('${tr('Xato')}: $_error',
                            style: const TextStyle(color: Colors.red))))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
                      children: _body(),
                    ),
                  ),
      ),
    );
  }

  List<Widget> _body() {
    final d = _data;
    if (d == null) return [Center(child: _emptyNote())];
    final results = ((d['results'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final ok = d['ok'] == true;
    final problems = results.where((r) {
      final c = _n(r['count']).toInt();
      return c > 0 || c == -1;
    }).length;

    return [
      // Katta status karta
      Container(
        padding: const EdgeInsets.all(16),
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: ok ? AppTheme.successSoft : AppTheme.dangerSoft,
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: (ok ? AppTheme.success : AppTheme.danger).withValues(alpha: 0.5)),
        ),
        child: Row(children: [
          Icon(ok ? Icons.check_circle : Icons.error,
              color: ok ? AppTheme.success : AppTheme.danger, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(ok ? tr('Hammasi mos') : '$problems ${tr('ta muammo')}',
                  style: TextStyle(
                      color: ok ? AppTheme.success : AppTheme.danger,
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text('${tr('Tekshirildi')}: ${_dt(d['checked_at'])}',
                  style: TextStyle(color: AppTheme.textSoft, fontSize: 11.5)),
              if ((d['source_note'] ?? '').toString().isNotEmpty)
                Text(d['source_note'].toString(),
                    style: TextStyle(color: AppTheme.textSoft, fontSize: 10.5)),
            ]),
          ),
        ]),
      ),
      for (final r in results) _resultCard(r),
    ];
  }

  Widget _resultCard(Map<String, dynamic> r) {
    final key = r['key']?.toString() ?? '';
    final sev = _sevColor(r['severity']?.toString() ?? '');
    final cnt = _n(r['count']).toInt();
    final rows = ((r['rows'] as List?) ?? const []).whereType<Map>().toList();
    final fixable = r['fixable'] == true;
    final fixNote = (r['fix_note'] ?? '').toString();
    final expanded = _open.contains(key);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 4, color: sev), // severity chizig'i
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  InkWell(
                    onTap: rows.isEmpty
                        ? null
                        : () => setState(() {
                              if (expanded) {
                                _open.remove(key);
                              } else {
                                _open.add(key);
                              }
                            }),
                    child: Row(children: [
                      Expanded(
                          child: Text((r['title'] ?? '').toString(),
                              style: TextStyle(
                                  color: AppTheme.text,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: sev.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999)),
                        child: Text(cnt == -1 ? tr('Xato') : '$cnt',
                            style:
                                TextStyle(color: sev, fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                      if (rows.isNotEmpty)
                        Icon(expanded ? Icons.expand_less : Icons.expand_more,
                            size: 20, color: AppTheme.textSoft),
                    ]),
                  ),
                  if (fixNote.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(fixNote,
                          style: TextStyle(color: AppTheme.textSoft, fontSize: 11.5)),
                    ),
                  if (expanded && rows.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        for (final row in rows)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                                row.entries
                                    .map((e) => '${e.key}: ${e.value ?? '—'}')
                                    .join(', '),
                                style: TextStyle(
                                    color: AppTheme.textSoft,
                                    fontSize: 11,
                                    fontFamily: 'monospace'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          ),
                      ]),
                    ),
                  if (fixable && cnt > 0)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _fixingKey != null ? null : () => _fix(r),
                        icon: _fixingKey == key
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppTheme.accent))
                            : Icon(Icons.build, size: 16, color: AppTheme.accent),
                        label: Text(tr('Tuzatish'),
                            style: TextStyle(
                                color: AppTheme.accent, fontWeight: FontWeight.w700)),
                      ),
                    ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════ 6. SKLAD SOZLAMALARI (tannarx usuli) ═══════════════

/// Sklad sozlamalari dialogi: tannarx usuli (FIFO/LIFO/o'rtacha) +
/// srok ogohlantirish kunlari + yetkazuvchi qarz kechikish chegarasi.
Future<void> showCostingSettingsDialog(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  dynamic res;
  try {
    res = await ApiService.get('/system/settings');
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
    return;
  }
  if (res is! Map || res['settings'] is! List) {
    final msg = (res is Map && res['message'] != null) ? res['message'].toString() : tr('Xato');
    messenger.showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    return;
  }

  final settings = (res['settings'] as List)
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList();
  Map<String, dynamic> find(String k) =>
      settings.firstWhere((s) => s['key'] == k, orElse: () => <String, dynamic>{});

  final methods = ((res['costing_methods'] as List?) ?? const ['fifo', 'lifo', 'average'])
      .map((e) => e.toString())
      .toList();
  final costingSetting = find('costing_method');
  String method = (costingSetting['value'] ?? 'fifo').toString();
  final origMethod = method;
  final expiryCtrl =
      TextEditingController(text: (find('expiry_warn_days')['value'] ?? '').toString());
  final overdueCtrl =
      TextEditingController(text: (find('supplier_overdue_days')['value'] ?? '').toString());
  final origExpiry = expiryCtrl.text;
  final origOverdue = overdueCtrl.text;
  // Chiqishsiz (check-out yo'q) kunni oylikка qo'shamizmi? '1'=ha (default), '0'=yo'q.
  bool payMissingCheckout = (find('pay_missing_checkout')['value'] ?? '1').toString() != '0';
  final origPayMissing = payMissingCheckout;

  String methodLabel(String m) {
    switch (m) {
      case 'fifo':
        return tr('FIFO — avval kelgani avval ketadi');
      case 'lifo':
        return tr('LIFO — oxirgi kelgani avval ketadi');
      case 'average':
        return tr('O\'rtacha-vaznli tannarx');
      default:
        return m;
    }
  }

  if (!context.mounted) return;
  await showDialog(
    context: context,
    builder: (_) {
      bool saving = false;
      return StatefulBuilder(
        builder: (ctx, setSt) {
          Widget radio(String value) => InkWell(
                onTap: saving ? null : () => setSt(() => method = value),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Icon(
                        method == value
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 20,
                        color: method == value ? AppTheme.accent : AppTheme.textSoft),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(methodLabel(value),
                            style: TextStyle(color: AppTheme.text, fontSize: 13.5))),
                  ]),
                ),
              );

          InputDecoration deco(String label) => InputDecoration(
                isDense: true,
                labelText: label,
                labelStyle: TextStyle(color: AppTheme.textSoft, fontSize: 12),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppTheme.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppTheme.accent)),
              );

          Future<void> save() async {
            if (saving) return;
            setSt(() => saving = true);
            try {
              final changes = <Map<String, dynamic>>[];
              if (method != origMethod) {
                changes.add({'key': 'costing_method', 'value': method});
              }
              final ex = expiryCtrl.text.trim();
              if (ex != origExpiry.trim()) {
                changes.add({'key': 'expiry_warn_days', 'value': int.tryParse(ex) ?? ex});
              }
              final ov = overdueCtrl.text.trim();
              if (ov != origOverdue.trim()) {
                changes.add({'key': 'supplier_overdue_days', 'value': int.tryParse(ov) ?? ov});
              }
              if (payMissingCheckout != origPayMissing) {
                changes.add({'key': 'pay_missing_checkout', 'value': payMissingCheckout ? '1' : '0'});
              }
              for (final ch in changes) {
                final r = await ApiService.put('/system/settings', ch);
                if (r is Map && r['ok'] != true) {
                  throw ApiException(400, (r['message'] ?? tr('Xato')).toString());
                }
              }
              messenger.showSnackBar(
                  SnackBar(content: Text(tr('Saqlandi')), backgroundColor: Colors.green));
              if (ctx.mounted) Navigator.pop(ctx);
            } catch (e) {
              messenger
                  .showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red));
              if (ctx.mounted) setSt(() => saving = false);
            }
          }

          return AlertDialog(
            backgroundColor: AppTheme.card,
            title: Text(tr('Sklad sozlamalari'), style: TextStyle(color: AppTheme.text)),
            content: SizedBox(
              width: (MediaQuery.of(context).size.width * 0.9).clamp(0.0, 420.0),
              child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Tannarx usuli'),
                          style: TextStyle(
                              color: AppTheme.textSoft,
                              fontSize: 12,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      for (final m in methods) radio(m),
                      if ((costingSetting['updated_by_name'] ?? '').toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                              '${tr('Oxirgi o\'zgartirgan')}: ${costingSetting['updated_by_name']} · ${_dt(costingSetting['updated_at'])}',
                              style: TextStyle(color: AppTheme.textSoft, fontSize: 10.5)),
                        ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: expiryCtrl,
                        enabled: !saving,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: AppTheme.text, fontSize: 13.5),
                        decoration: deco(tr('Srok ogohlantirish (kun)')),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: overdueCtrl,
                        enabled: !saving,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: AppTheme.text, fontSize: 13.5),
                        decoration: deco(tr('Qarz kechikish chegarasi (kun)')),
                      ),
                      const SizedBox(height: 16),
                      Divider(color: AppTheme.border, height: 1),
                      const SizedBox(height: 8),
                      Text(tr('Ish haqi / Davomat'),
                          style: TextStyle(color: AppTheme.textSoft, fontSize: 12, fontWeight: FontWeight.w700)),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        activeColor: AppTheme.accent,
                        value: payMissingCheckout,
                        onChanged: saving ? null : (v) => setSt(() => payMissingCheckout = v),
                        title: Text(tr('Chiqishsiz kunni oylikка qo\'shish'),
                            style: TextStyle(color: AppTheme.text, fontSize: 13.5)),
                        subtitle: Text(tr('O\'chirilsa: xodim ketishни belgilamagan kun (0 soat) to\'lanmaydi'),
                            style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
                      ),
                    ]),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent, foregroundColor: AppTheme.onAccent),
                onPressed: saving ? null : save,
                child: saving
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child:
                            CircularProgressIndicator(strokeWidth: 2, color: AppTheme.onAccent))
                    : Text(tr('Saqlash')),
              ),
            ],
          );
        },
      );
    },
  );
}

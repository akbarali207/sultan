import 'package:flutter/material.dart';
import '../core/api_service.dart';
import '../core/constants.dart';
import '../core/app_theme.dart';
import '../core/lang.dart';

/// RETSEPTLAR bo'limi: Tip -> Taom (rasmsiz) -> Excel ko'rinishidagi kalkulyatsiya.
/// Masaliq: brutto (xom vazn), chiqish%, narx kiritiladi; netto va tannarx avtomatik.
class RecipeSection extends StatefulWidget {
  const RecipeSection({super.key});
  @override
  State<RecipeSection> createState() => _RecipeSectionState();
}

class _RecipeSectionState extends State<RecipeSection> {
  List<dynamic> _categories = [];
  List<dynamic> _items = [];
  final Set<int> _expanded = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final cats = await ApiService.get(AppConstants.menuCategories);
      // include_pf=1 — polufabrikatlar ham ko'rinadi (menyuda emas, faqat shu yerda)
      final items = await ApiService.get('${AppConstants.menuItems}?include_pf=1');
      if (!mounted) return;
      setState(() {
        _categories = cats is List ? cats : [];
        _items = items is List ? items : [];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // POLUFABRIKAT yaratish — nom + birlik + sklad, keyin retsept muharriri ochiladi
  Future<void> _addPf(Map category) async {
    List<dynamic> whs = [];
    try {
      final w = await ApiService.get(AppConstants.warehouses);
      whs = w is List ? w : [];
    } catch (_) {}
    if (!mounted) return;
    final nameC = TextEditingController();
    String unit = 'кг';
    int? whId = whs.isNotEmpty ? whs.first['id'] as int : null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text('${category['name']} — ${tr('Polufabrikat qo\'shish')}',
              style: TextStyle(color: AppTheme.text, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameC,
                autofocus: true,
                style: TextStyle(color: AppTheme.text),
                decoration: InputDecoration(
                  labelText: tr('Nomi'),
                  labelStyle: TextStyle(color: AppTheme.textSoft),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.accent)),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: unit,
                dropdownColor: AppTheme.card,
                style: TextStyle(color: AppTheme.text),
                decoration: InputDecoration(
                  labelText: tr('Birlik'),
                  labelStyle: TextStyle(color: AppTheme.textSoft),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                ),
                items: const ['кг', 'л', 'шт', 'г', 'мл', 'dona']
                    .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                    .toList(),
                onChanged: (v) => setSt(() => unit = v ?? 'кг'),
              ),
              const SizedBox(height: 10),
              if (whs.isNotEmpty)
                DropdownButtonFormField<int>(
                  value: whId,
                  isExpanded: true,
                  dropdownColor: AppTheme.card,
                  style: TextStyle(color: AppTheme.text),
                  decoration: InputDecoration(
                    labelText: tr('Sklad (qaysi sex)'),
                    labelStyle: TextStyle(color: AppTheme.textSoft),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                  ),
                  items: whs
                      .map((w) => DropdownMenuItem<int>(
                            value: w['id'] as int,
                            child: Text(w['name']?.toString() ?? '', style: TextStyle(color: AppTheme.text)),
                          ))
                      .toList(),
                  onChanged: (v) => setSt(() => whId = v),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Saqlash'), style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (ok != true || nameC.text.trim().isEmpty) return;
    try {
      final res = await ApiService.post('/menu/pf', {
        'name': nameC.text.trim(),
        'unit': unit,
        'warehouse_id': whId,
        'category_id': category['id'],
      });
      if (res is Map && res['id'] != null) {
        await _load();
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => RecipeEditorPage(menuItem: Map<String, dynamic>.from(res))),
        );
        _load();
      } else if (res is Map && res['message'] != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'].toString()), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([AppTheme.instance, Lang.instance]),
      builder: (_, __) => _content(),
    );
  }

  Widget _content() {
    if (_loading) return Center(child: CircularProgressIndicator(color: AppTheme.accent));
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
            child: Row(children: [
              Text(tr('Retseptlar'),
                  style: TextStyle(color: AppTheme.text, fontSize: 22, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(icon: Icon(Icons.refresh, color: AppTheme.textSoft), onPressed: _load),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
                tr('Tipni oching -> taomni bosing -> masaliqlar (brutto, chiqish%, narx). Netto va tannarx avtomatik hisoblanadi.'),
                style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
          ),
          Expanded(
            child: _categories.isEmpty
                ? Center(child: Text(tr('Tip yo\'q'), style: TextStyle(color: AppTheme.textSoft)))
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: _categories.map((c) {
                      final cid = c['id'] as int;
                      final catItems = _items.where((m) => m['category_id'] == cid).toList();
                      final exp = _expanded.contains(cid);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(12)),
                        child: Column(
                          children: [
                            InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => setState(() {
                                if (exp) {
                                  _expanded.remove(cid);
                                } else {
                                  _expanded.add(cid);
                                }
                              }),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                child: Row(children: [
                                  Icon(Icons.category, color: AppTheme.accent),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text('${c['name']} (${catItems.length})',
                                        style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 15)),
                                  ),
                                  Icon(exp ? Icons.expand_more : Icons.chevron_right, color: AppTheme.accent),
                                ]),
                              ),
                            ),
                            if (exp) ...[
                              // + POLUFABRIKAT — shu kategoriya uchun P/F yaratish
                              Container(
                                decoration: BoxDecoration(
                                    border: Border(top: BorderSide(color: AppTheme.border))),
                                child: ListTile(
                                  dense: true,
                                  leading: const Icon(Icons.blender, color: Colors.purple, size: 20),
                                  title: Text(tr('Polufabrikat qo\'shish'),
                                      style: const TextStyle(color: Colors.purple, fontWeight: FontWeight.w600)),
                                  trailing: const Icon(Icons.add, color: Colors.purple, size: 18),
                                  onTap: () => _addPf(c),
                                ),
                              ),
                              ...catItems.map((m) {
                                final isPf = m['type']?.toString() == 'pf';
                                return Container(
                                  decoration: BoxDecoration(
                                      border: Border(top: BorderSide(color: AppTheme.border))),
                                  child: ListTile(
                                    dense: true,
                                    leading: Icon(isPf ? Icons.blender : Icons.receipt_long,
                                        color: isPf ? Colors.purple : AppTheme.textSoft, size: 20),
                                    title: Row(children: [
                                      Flexible(
                                        child: Text(m['name']?.toString() ?? '',
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(color: AppTheme.text)),
                                      ),
                                      if (isPf) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.purple.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text('П/Ф',
                                              style: TextStyle(color: Colors.purple, fontSize: 10, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ]),
                                    trailing: Icon(Icons.chevron_right, color: AppTheme.textSoft),
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => RecipeEditorPage(menuItem: m)),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Bitta taom retsepti — Excel ko'rinishidagi jadval (kalkulyatsiya).
class RecipeEditorPage extends StatefulWidget {
  final Map<String, dynamic> menuItem;
  const RecipeEditorPage({super.key, required this.menuItem});
  @override
  State<RecipeEditorPage> createState() => _RecipeEditorPageState();
}

class _RecipeEditorPageState extends State<RecipeEditorPage> {
  List<dynamic> _lines = [];
  List<dynamic> _warehouses = [];
  List<dynamic> _allIngredients = []; // avto-qidiruv uchun mavjud masaliqlar
  bool _loading = true;
  double? _yieldOverride; // partiya chiqishi qo'lda tahrirlangach — darhol ko'rsatish uchun
  int get _itemId => widget.menuItem['id'] as int;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await ApiService.get('/menu/recipe/$_itemId');
      final whs = await ApiService.get(AppConstants.warehouses);
      // Mavjud masaliqlar (avto-qidiruv uchun) — xato bo'lsa ham retsept ochilaveradi
      List<dynamic> ings = [];
      try {
        final r = await ApiService.get(AppConstants.ingredients);
        ings = r is List ? r : [];
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _lines = data is List ? data : [];
        _warehouses = whs is List ? whs : [];
        _allIngredients = ings;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Yangi masaliq qaysi skladга tushsin (default): oxirgi satr skladi, bo'lmasa 1-sklad
  int? get _defaultWh {
    if (_lines.isNotEmpty) {
      final w = _lines.last['warehouse_id'];
      if (w is int) return w;
      final n = int.tryParse(w?.toString() ?? '');
      if (n != null) return n;
    }
    return _warehouses.isNotEmpty ? _warehouses.first['id'] as int : null;
  }

  double _d(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0;
  double _netto(dynamic r) => _d(r['quantity']) * _d(r['yield_percent']) / 100;
  double _cost(dynamic r) => _d(r['quantity']) * _d(r['price_per_unit']);
  String _w(double v) => v.toStringAsFixed(3);

  // PARTIYA CHIQISHI (ВЫХОД, kg) — ТТК da QO'LDA beriladi (masalan Соус Цезарь П/Ф = 0.840 кг),
  // ingredientlar yig'indisidan hisoblanmaydi (dona/litr kg bilan aralashadi — 8 yumurtcha ≠ 8 kg).
  // Manba: (1) backend maydoni menu_items.yield_kg; (2) bo'lmasa — quyidagi ТТК jadvali (nom bo'yicha).
  static const Map<String, double> _ttkYield = {
    'соус цезарь п/ф': 0.840,
    'соус пицца п/ф': 6.7,
    'катлет фарш п/ф': 5.65,
    'котлет фарш п/ф': 5.65,
    'фарш хинкали п/ф': 2.3,
    'зажарка для чучбара ттк': 4.0,
    'зажарка ттк': 4.0,
  };
  String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  // Retseptning partiya chiqishi (kg) yoki null (porsiyalik taom).
  double? _batchYieldKg() {
    // Qo'lda tahrirlangan qiymat (saqlangach) — birinchi navbatda
    if (_yieldOverride != null && _yieldOverride! > 0) return _yieldOverride;
    final y = widget.menuItem['yield_kg'];
    final yd = y == null ? null : double.tryParse(y.toString());
    if (yd != null && yd > 0) return yd;
    return _ttkYield[_norm(widget.menuItem['name']?.toString() ?? '')];
  }

  // Partiya chiqishini (ВЫХОД, kg) qo'lda o'rnatish — PUT /menu/items/:id/yield
  Future<void> _editYield() async {
    final current = _batchYieldKg();
    final ctrl = TextEditingController(
        text: current != null ? current.toStringAsFixed(3) : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('Chiqish (partiya)'), style: TextStyle(color: AppTheme.text, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: TextStyle(color: AppTheme.text),
          decoration: InputDecoration(
            labelText: '${tr('Chiqish (partiya)')} (кг)',
            labelStyle: TextStyle(color: AppTheme.textSoft),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.accent)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Saqlash'), style: TextStyle(color: AppTheme.onAccent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final parsed = double.tryParse(ctrl.text.replaceAll(',', '.').trim());
    if (parsed == null || parsed <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr('Noto\'g\'ri qiymat')), backgroundColor: Colors.red));
      }
      return;
    }
    try {
      await ApiService.put('/menu/items/$_itemId/yield', {'yield_kg': parsed});
      if (!mounted) return;
      setState(() => _yieldOverride = parsed); // darhol ko'rinsin
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _addOrEdit({Map? line}) async {
    final res = await showDialog<bool>(
        context: context,
        builder: (_) => _RecipeLineDialog(
              menuItemId: _itemId,
              line: line,
              warehouses: _warehouses,
              allIngredients: _allIngredients,
              defaultWarehouseId: _defaultWh,
              // P/F o'z retseptiga o'zini qo'sha olmasin
              excludeIngredientId: widget.menuItem['type']?.toString() == 'pf'
                  ? (widget.menuItem['ingredient_id'] is int
                      ? widget.menuItem['ingredient_id'] as int
                      : int.tryParse(widget.menuItem['ingredient_id']?.toString() ?? ''))
                  : null,
            ));
    if (res == true) _load();
  }

  Future<void> _delete(Map r) async {
    await ApiService.delete('/menu/recipe/${r['id']}');
    _load();
  }

  Widget _cell(String text, double w, {Color? color, FontWeight? fw, TextAlign align = TextAlign.center}) =>
      SizedBox(
        width: w,
        child: Text(text,
            textAlign: align,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: color ?? AppTheme.text, fontSize: 12, fontWeight: fw)),
      );

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([AppTheme.instance, Lang.instance]),
      builder: (_, __) => _content(),
    );
  }

  Widget _content() {
    double totB = 0, totN = 0, totC = 0;
    for (final r in _lines) {
      totB += _d(r['quantity']);
      totN += _netto(r);
      totC += _cost(r);
    }
    final batchKg = _batchYieldKg(); // ТТК partiya chiqishi (kg) yoki null
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.card,
        iconTheme: IconThemeData(color: AppTheme.text),
        title: Text('${widget.menuItem['name']} — ${tr('retsept')}',
            style: TextStyle(color: AppTheme.text, fontSize: 16)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.accent,
        onPressed: () => _addOrEdit(),
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text(tr('Masaliq qo\'shish'), style: const TextStyle(color: Colors.white)),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 640,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 90),
                  children: [
                    // Sarlavha qatori
                    Container(
                      color: AppTheme.card,
                      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
                      child: Row(children: [
                        _cell('№', 28, fw: FontWeight.bold, color: AppTheme.textSoft),
                        _cell(tr('Masaliq'), 158, fw: FontWeight.bold, align: TextAlign.left),
                        _cell(tr('Birlik'), 42, fw: FontWeight.bold, color: AppTheme.textSoft),
                        _cell(tr('Brutto'), 64, fw: FontWeight.bold),
                        _cell(tr('Chiqish'), 56, fw: FontWeight.bold),
                        _cell(tr('Netto'), 64, fw: FontWeight.bold),
                        _cell(tr('Narx'), 60, fw: FontWeight.bold),
                        _cell(tr('Tannarx'), 74, fw: FontWeight.bold, color: AppTheme.accent),
                        const SizedBox(width: 34),
                      ]),
                    ),
                    if (_lines.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(30),
                        child: Text(tr('Masaliqlar kiritilmagan. "+" bilan qo\'shing.'),
                            style: TextStyle(color: AppTheme.textSoft)),
                      ),
                    ..._lines.asMap().entries.map((e) {
                      final i = e.key;
                      final r = e.value as Map;
                      return InkWell(
                        onTap: () => _addOrEdit(line: r),
                        child: Container(
                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border))),
                          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
                          child: Row(children: [
                            _cell('${i + 1}', 28, color: AppTheme.textSoft),
                            SizedBox(
                              width: 158,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                      (r['ingredient_category']?.toString() == 'П/Ф' ? '[П/Ф] ' : '') +
                                          (r['ingredient_name']?.toString() ?? ''),
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: r['ingredient_category']?.toString() == 'П/Ф'
                                              ? Colors.purple
                                              : AppTheme.text,
                                          fontSize: 12)),
                                  if ((r['warehouse_name']?.toString() ?? '').isNotEmpty)
                                    Text(r['warehouse_name'].toString(),
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(color: AppTheme.accent, fontSize: 9)),
                                ],
                              ),
                            ),
                            _cell(r['unit']?.toString() ?? '', 42, color: AppTheme.textSoft),
                            _cell(_w(_d(r['quantity'])), 64),
                            _cell('${_d(r['yield_percent']).toStringAsFixed(0)}%', 56),
                            _cell(_w(_netto(r)), 64, color: AppTheme.textSoft),
                            _cell(_d(r['price_per_unit']).toStringAsFixed(0), 60),
                            _cell(_cost(r).toStringAsFixed(2), 74, color: AppTheme.accent, fw: FontWeight.bold),
                            SizedBox(
                              width: 34,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                icon: Icon(Icons.delete, color: Colors.red, size: 18),
                                onPressed: () => _delete(r),
                              ),
                            ),
                          ]),
                        ),
                      );
                    }),
                    // JAMI (ustunlar yig'indisi — brutto/netto aralash birlik, faqat ma'lumot uchun)
                    Container(
                      color: AppTheme.accentSoft,
                      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
                      child: Row(children: [
                        _cell('', 28),
                        _cell(tr('JAMI'), 158, fw: FontWeight.bold, align: TextAlign.left),
                        _cell('', 42),
                        _cell(_w(totB), 64, fw: FontWeight.bold),
                        _cell('', 56),
                        _cell(_w(totN), 64, fw: FontWeight.bold),
                        _cell('', 60),
                        _cell(totC.toStringAsFixed(2), 74, fw: FontWeight.bold, color: AppTheme.accent),
                        const SizedBox(width: 34),
                      ]),
                    ),
                    // KONVENSIYA (per-unit): retsept 1 kg chiqishga kiritiladi -> tannarx/кг = jami tannarx
                    // TO'G'RIDAN-TO'G'RI (yield_kg ga bo'linmaydi; syncPfCost bilan mos). "Chiqish" — faqat ma'lumot.
                    if (batchKg != null && batchKg > 0)
                      InkWell(
                        onTap: _editYield,
                        child: Container(
                          color: AppTheme.card,
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                          child: Row(children: [
                            Icon(Icons.scale, size: 17, color: AppTheme.accent),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text('${tr('Chiqish (partiya)')}: ${batchKg.toStringAsFixed(3)} кг',
                                  style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 13)),
                            ),
                            Icon(Icons.edit, size: 15, color: AppTheme.textSoft),
                            const SizedBox(width: 8),
                            Text('${totC.toStringAsFixed(0)} ${tr('so\'m')}/кг',
                                style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold, fontSize: 13)),
                          ]),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// Masaliq qo'shish/tahrirlash dialogi (oddiy masaliq YOKI polufabrikat)
class _RecipeLineDialog extends StatefulWidget {
  final int menuItemId;
  final Map? line;
  final List<dynamic> warehouses;
  final List<dynamic> allIngredients; // avto-qidiruv manbasi
  final int? defaultWarehouseId;
  final int? excludeIngredientId; // P/F o'zini tanlamasin
  const _RecipeLineDialog({
    required this.menuItemId,
    this.line,
    required this.warehouses,
    this.allIngredients = const [],
    this.defaultWarehouseId,
    this.excludeIngredientId,
  });
  @override
  State<_RecipeLineDialog> createState() => _RecipeLineDialogState();
}

class _RecipeLineDialogState extends State<_RecipeLineDialog> {
  late TextEditingController _name, _brutto, _yield, _price;
  String _unit = 'кг';
  int? _whId;
  bool get _isEdit => widget.line != null;
  static const _units = ['кг', 'л', 'шт', 'г', 'мл'];

  // --- Avto-qidiruv (mavjud masaliq tanlash) ---
  final FocusNode _nameFocus = FocusNode();
  int? _selectedIngredientId; // to'ldirilgan bo'lsa: mavjud masaliq, yangi YARATILMAYDI

  // --- P/F rejimi ---
  bool _pfMode = false;          // yangi satr: masaliq (false) yoki P/F (true)
  List<dynamic> _pfList = [];    // skladdagi П/Ф masaliqlar
  int? _pfId;                    // tanlangan P/F ingredient_id
  bool get _isPfLine => // tahrirlanayotgan satr P/F mi?
      (widget.line?['ingredient_category']?.toString() ?? '') == 'П/Ф';

  double get _pfPrice {
    for (final p in _pfList) {
      if (p['id'] == _pfId) return double.tryParse(p['price_per_unit']?.toString() ?? '0') ?? 0;
    }
    return 0;
  }

  Future<void> _loadPfList() async {
    try {
      final r = await ApiService.get('/stock?category=${Uri.encodeQueryComponent('П/Ф')}');
      if (!mounted) return;
      setState(() {
        _pfList = (r is List ? r : [])
            .where((p) => p['id'] != widget.excludeIngredientId)
            .toList();
        if (_pfId == null && _pfList.isNotEmpty) _pfId = _pfList.first['id'] as int;
      });
    } catch (_) {}
  }

  String _whName(int? id) {
    for (final w in widget.warehouses) {
      if (w['id'] == id) return w['name']?.toString() ?? '-';
    }
    return '-';
  }

  @override
  void initState() {
    super.initState();
    final l = widget.line;
    _whId = l != null
        ? (l['warehouse_id'] is int ? l['warehouse_id'] : int.tryParse(l['warehouse_id']?.toString() ?? ''))
        : widget.defaultWarehouseId;
    _name = TextEditingController(text: l?['ingredient_name']?.toString() ?? '');
    _brutto = TextEditingController(text: l != null ? (l['quantity']?.toString() ?? '') : '');
    _yield = TextEditingController(
        text: l != null ? ((double.tryParse(l['yield_percent']?.toString() ?? '100') ?? 100).toStringAsFixed(0)) : '100');
    _price = TextEditingController(
        text: l != null ? ((double.tryParse(l['price_per_unit']?.toString() ?? '0') ?? 0).toStringAsFixed(0)) : '');
    _unit = l?['unit']?.toString() ?? 'кг';
    if (!_units.contains(_unit)) _unit = 'кг';
  }

  @override
  void dispose() {
    _name.dispose();
    _brutto.dispose();
    _yield.dispose();
    _price.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  // Kiritilgan matnga mos MAVJUD masaliqlar (P/F va o'zini tanlab bo'lmaydiganlar tashqari).
  // startsWith avval, keyin contains — alifbo tartibida.
  Iterable<Map> _suggest(String query) {
    final nq = _norm(query);
    if (nq.isEmpty) return const <Map>[];
    final list = <Map>[];
    for (final e in widget.allIngredients) {
      if (e is! Map) continue;
      if ((e['category']?.toString() ?? '') == 'П/Ф') continue; // P/F alohida rejimда
      final id = e['id'] is int ? e['id'] as int : int.tryParse(e['id']?.toString() ?? '');
      if (id != null && id == widget.excludeIngredientId) continue;
      if (_norm(e['name']?.toString() ?? '').contains(nq)) list.add(e);
    }
    list.sort((a, b) {
      final an = _norm(a['name']?.toString() ?? '');
      final bn = _norm(b['name']?.toString() ?? '');
      final aw = an.startsWith(nq) ? 0 : 1;
      final bw = bn.startsWith(nq) ? 0 : 1;
      if (aw != bw) return aw - bw;
      return an.compareTo(bn);
    });
    return list.take(30);
  }

  // Mavjud masaliq tanlandi — id/birlik/narx/sklad kartadan olinadi (dublikat ochilmaydi)
  void _onPick(Map m) {
    setState(() {
      _selectedIngredientId = m['id'] is int ? m['id'] as int : int.tryParse(m['id']?.toString() ?? '');
      _name.text = m['name']?.toString() ?? '';
      _unit = m['unit']?.toString() ?? _unit;
      _price.text = (double.tryParse(m['price_per_unit']?.toString() ?? '0') ?? 0).toStringAsFixed(0);
      final w = m['warehouse_id'];
      _whId = w is int ? w : int.tryParse(w?.toString() ?? '');
    });
    _nameFocus.unfocus();
  }

  Widget _previewBox(double netto, double cost) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppTheme.bg, borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('${tr('Netto')}: ${netto.toStringAsFixed(3)}',
              style: TextStyle(color: AppTheme.textSoft, fontSize: 13)),
          Text('${tr('Tannarx')}: ${cost.toStringAsFixed(2)}',
              style: TextStyle(color: AppTheme.accent, fontSize: 14, fontWeight: FontWeight.bold)),
        ]),
      );

  double get _b => double.tryParse(_brutto.text.replaceAll(',', '.')) ?? 0;
  double get _y => double.tryParse(_yield.text.replaceAll(',', '.')) ?? 100;
  double get _p => double.tryParse(_price.text.replaceAll(',', '.')) ?? 0;
  double _d0(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0;

  Future<void> _save() async {
    if (_b <= 0) return;
    if (!_isEdit && !_pfMode && _name.text.trim().isEmpty) return;
    if (!_isEdit && _pfMode && _pfId == null) return;
    try {
      dynamic res;
      if (_isEdit) {
        // P/F satri: narx/birlik yuborilmaydi (P/F narxi o'z retseptidan sync bo'ladi)
        res = await ApiService.put('/menu/recipe/${widget.line!['id']}',
            _isPfLine
                ? {'quantity': _b, 'yield_percent': _y}
                : {'quantity': _b, 'yield_percent': _y, 'price_per_unit': _p, 'unit': _unit});
      } else if (_pfMode) {
        // POLUFABRIKAT — mavjud П/Ф masaliq to'g'ridan-to'g'ri ulanadi
        res = await ApiService.post('/menu/recipe', {
          'menu_item_id': widget.menuItemId,
          'ingredient_id': _pfId,
          'quantity': _b,
          'yield_percent': 100,
        });
      } else if (_selectedIngredientId != null) {
        // MAVJUD masaliq — id bo'yicha ulanadi, yangi masaliq YARATILMAYDI (dublikat yo'q)
        res = await ApiService.post('/menu/recipe', {
          'menu_item_id': widget.menuItemId,
          'ingredient_id': _selectedIngredientId,
          'quantity': _b,
          'yield_percent': _y,
        });
      } else {
        res = await ApiService.post('/menu/recipe', {
          'menu_item_id': widget.menuItemId,
          'ingredient_name': _name.text.trim(),
          'unit': _unit,
          'quantity': _b,
          'yield_percent': _y,
          'price_per_unit': _p,
          if (_whId != null) 'warehouse_id': _whId,
        });
      }
      if (res is Map && res['message'] != null && res['id'] == null && res['ok'] != true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(res['message'].toString()), backgroundColor: Colors.red));
        }
        return;
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
      }
    }
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        labelStyle: TextStyle(color: AppTheme.textSoft, fontSize: 13),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.accent)),
      );

  Widget _modeBtn(String label, bool sel, VoidCallback onTap, {Color color = Colors.blue}) =>
      Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: sel ? color.withValues(alpha: 0.15) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: sel ? color : AppTheme.border),
            ),
            child: Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: sel ? color : AppTheme.textSoft,
                    fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final netto = _b * _y / 100;
    final cost = _b * (_pfMode ? _pfPrice : (_isPfLine ? _d0(widget.line?['price_per_unit']) : _p));
    return AlertDialog(
      backgroundColor: AppTheme.card,
      title: Text(
          _isEdit
              ? (_isPfLine ? tr('Polufabrikat') : tr('Masaliqni tahrirlash'))
              : (_pfMode ? tr('Polufabrikat') : tr('Masaliq qo\'shish')),
          style: TextStyle(color: AppTheme.text)),
      content: SizedBox(
        width: 320,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Yangi satr: Masaliq | Polufabrikat tanlovi
            if (!_isEdit) ...[
              Row(children: [
                _modeBtn(tr('Masaliq'), !_pfMode, () => setState(() => _pfMode = false)),
                const SizedBox(width: 8),
                _modeBtn(tr('Polufabrikat'), _pfMode, () {
                  setState(() => _pfMode = true);
                  if (_pfList.isEmpty) _loadPfList();
                }, color: Colors.purple),
              ]),
              const SizedBox(height: 12),
            ],
            // ---- P/F rejimi: tayyor П/Ф ro'yxatidan tanlash ----
            if (!_isEdit && _pfMode) ...[
              if (_pfList.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(tr('P/F yo\'q — avval kategoriyada "Polufabrikat qo\'shish" bilan yarating'),
                      style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
                )
              else
                DropdownButtonFormField<int>(
                  value: _pfId,
                  isExpanded: true,
                  dropdownColor: AppTheme.card,
                  style: TextStyle(color: AppTheme.text),
                  decoration: _dec(tr('P/F tanlang')),
                  items: _pfList
                      .map((p) => DropdownMenuItem<int>(
                            value: p['id'] as int,
                            child: Text(
                                '${p['name']} (${(double.tryParse(p['price_per_unit']?.toString() ?? '0') ?? 0).toStringAsFixed(0)}/${p['unit']})',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: AppTheme.text, fontSize: 13)),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _pfId = v),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: _brutto,
                keyboardType: TextInputType.number,
                style: TextStyle(color: AppTheme.text),
                onChanged: (_) => setState(() {}),
                decoration: _dec(tr('Brutto (xom)')),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppTheme.bg, borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('${tr('Narx')}: ${_pfPrice.toStringAsFixed(0)}',
                      style: TextStyle(color: AppTheme.textSoft, fontSize: 13)),
                  Text('${tr('Tannarx')}: ${cost.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.purple, fontSize: 14, fontWeight: FontWeight.bold)),
                ]),
              ),
            ],
            // ---- TAHRIR: mavjud satr (masaliq nomi o'zgarmaydi) ----
            if (_isEdit) ...[
              if (widget.warehouses.isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('${tr('Sklad')}: ${_whName(_whId)}',
                      style: TextStyle(color: AppTheme.accent, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: _name,
                enabled: false,
                style: TextStyle(color: AppTheme.text),
                decoration: _dec(tr('Masaliq nomi')),
              ),
              const SizedBox(height: 10),
              Row(children: [
                SizedBox(
                  width: 90,
                  child: DropdownButtonFormField<String>(
                    value: _unit,
                    dropdownColor: AppTheme.card,
                    style: TextStyle(color: AppTheme.text),
                    decoration: _dec(tr('Birlik')),
                    items: _units
                        .map((u) => DropdownMenuItem(value: u, child: Text(u, style: TextStyle(color: AppTheme.text))))
                        .toList(),
                    onChanged: (v) => setState(() => _unit = v ?? 'кг'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _brutto,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: AppTheme.text),
                    onChanged: (_) => setState(() {}),
                    decoration: _dec(tr('Brutto (xom)')),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _yield,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: AppTheme.text),
                    onChanged: (_) => setState(() {}),
                    decoration: _dec(tr('Chiqish %')),
                  ),
                ),
                const SizedBox(width: 8),
                if (!_isPfLine)
                  Expanded(
                    child: TextField(
                      controller: _price,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: AppTheme.text),
                      onChanged: (_) => setState(() {}),
                      decoration: _dec(tr('Narx (1 birlik)')),
                    ),
                  )
                else
                  const Expanded(child: SizedBox()),
              ]),
              const SizedBox(height: 12),
              _previewBox(netto, cost),
            ],
            // ---- YANGI oddiy masaliq: AVTO-QIDIRUV (yozing -> tanlang, dublikat ochilmaydi) ----
            if (!_isEdit && !_pfMode) ...[
              RawAutocomplete<Map>(
                textEditingController: _name,
                focusNode: _nameFocus,
                optionsBuilder: (t) => _suggest(t.text),
                displayStringForOption: (m) => m['name']?.toString() ?? '',
                onSelected: _onPick,
                fieldViewBuilder: (ctx, ctrl, fnode, _) => TextField(
                  controller: ctrl,
                  focusNode: fnode,
                  style: TextStyle(color: AppTheme.text),
                  onChanged: (_) {
                    // Tanlangan masaliqdan chetga chiqilsa — tanlovni bekor qilamiz (yangi sifatida)
                    if (_selectedIngredientId != null) setState(() => _selectedIngredientId = null);
                  },
                  decoration: _dec(tr('Masaliq nomi (yozing: pom...)')).copyWith(
                    prefixIcon: Icon(
                      _selectedIngredientId != null ? Icons.check_circle : Icons.search,
                      color: _selectedIngredientId != null ? Colors.green : AppTheme.textSoft,
                      size: 18,
                    ),
                  ),
                ),
                optionsViewBuilder: (ctx, onSel, options) => Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    color: AppTheme.card,
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(color: AppTheme.border),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 240, maxWidth: 300),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (c, i) {
                          final m = options.elementAt(i);
                          final pr = (double.tryParse(m['price_per_unit']?.toString() ?? '0') ?? 0).toStringAsFixed(0);
                          return InkWell(
                            onTap: () => onSel(m),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              child: Row(children: [
                                Expanded(
                                  child: Text(m['name']?.toString() ?? '',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: AppTheme.text, fontSize: 13)),
                                ),
                                Text('$pr/${m['unit'] ?? ''}',
                                    style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
                              ]),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (_selectedIngredientId != null) ...[
                // Mavjud masaliq ulanadi — sklad/narx/birlik kartadan olinadi
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.link, color: Colors.green, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${tr('Mavjud masaliq')} · $_unit · ${_price.text}/$_unit · ${_whName(_whId)}',
                        style: TextStyle(color: AppTheme.textSoft, fontSize: 11),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _brutto,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: AppTheme.text),
                      onChanged: (_) => setState(() {}),
                      decoration: _dec(tr('Brutto (xom)')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _yield,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: AppTheme.text),
                      onChanged: (_) => setState(() {}),
                      decoration: _dec(tr('Chiqish %')),
                    ),
                  ),
                ]),
              ] else ...[
                // Yangi masaliq — sklad, birlik, narx kiritiladi
                if (widget.warehouses.isNotEmpty) ...[
                  DropdownButtonFormField<int>(
                    value: _whId,
                    dropdownColor: AppTheme.card,
                    isExpanded: true,
                    style: TextStyle(color: AppTheme.text),
                    decoration: _dec(tr('Sklad (qaysi sex)')),
                    items: widget.warehouses
                        .map((w) => DropdownMenuItem<int>(
                              value: w['id'] as int,
                              child: Text(w['name']?.toString() ?? '', style: TextStyle(color: AppTheme.text)),
                            ))
                        .toList(),
                    onChanged: (v) => setState(() => _whId = v),
                  ),
                  const SizedBox(height: 10),
                ],
                Row(children: [
                  SizedBox(
                    width: 90,
                    child: DropdownButtonFormField<String>(
                      value: _unit,
                      dropdownColor: AppTheme.card,
                      style: TextStyle(color: AppTheme.text),
                      decoration: _dec(tr('Birlik')),
                      items: _units
                          .map((u) => DropdownMenuItem(value: u, child: Text(u, style: TextStyle(color: AppTheme.text))))
                          .toList(),
                      onChanged: (v) => setState(() => _unit = v ?? 'кг'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _brutto,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: AppTheme.text),
                      onChanged: (_) => setState(() {}),
                      decoration: _dec(tr('Brutto (xom)')),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _yield,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: AppTheme.text),
                      onChanged: (_) => setState(() {}),
                      decoration: _dec(tr('Chiqish %')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _price,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: AppTheme.text),
                      onChanged: (_) => setState(() {}),
                      decoration: _dec(tr('Narx (1 birlik)')),
                    ),
                  ),
                ]),
              ],
              const SizedBox(height: 12),
              _previewBox(netto, cost),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
          onPressed: _save,
          child: Text(tr('Saqlash'), style: TextStyle(color: AppTheme.onAccent)),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../../core/lang.dart';
import '../../core/num_input.dart';

/// ── Umumiy yordamchilar ──

num _num(dynamic v) => v is num ? v : (num.tryParse(v?.toString() ?? '') ?? 0);

/// Pul: 12345.67 -> "12346 so'm"
String _money(dynamic v) => '${_num(v).toDouble().toStringAsFixed(0)} ${tr('so\'m')}';

/// ISO sana -> YYYY-MM-DD
String _d(dynamic s) {
  if (s == null) return '-';
  final t = s.toString();
  return t.length >= 10 ? t.substring(0, 10) : t;
}

/// Miqdor: butun bo'lsa kasrsiz ko'rsatadi.
String _qty(dynamic v) {
  final d = _num(v).toDouble();
  return d == d.roundToDouble() ? d.toStringAsFixed(0) : d.toString();
}

// ═══════════════════════════════════════════════════════════════════════════
// POSTAVSHIKLAR RO'YXATI
// ═══════════════════════════════════════════════════════════════════════════

class SuppliersPage extends StatefulWidget {
  const SuppliersPage({super.key});

  @override
  State<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends State<SuppliersPage> {
  List<dynamic> _suppliers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final r = await ApiService.get('/stock/suppliers');
      if (!mounted) return;
      setState(() {
        _suppliers = r is List ? r : [];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
    }
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppTheme.bg,
        labelStyle: TextStyle(color: AppTheme.textSoft),
        prefixIcon: Icon(icon, color: AppTheme.accent),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppTheme.textSoft)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppTheme.accent)),
      );

  // ── Qo'shish / tahrirlash dialogi ──
  void _showSupplierDialog({Map<String, dynamic>? supplier}) {
    final isEdit = supplier != null;
    final nameCtrl = TextEditingController(text: supplier?['name']?.toString() ?? '');
    final phoneCtrl = TextEditingController(text: supplier?['phone']?.toString() ?? '');
    final contactCtrl =
        TextEditingController(text: supplier?['contact_person']?.toString() ?? '');
    final addressCtrl = TextEditingController(text: supplier?['address']?.toString() ?? '');
    final noteCtrl = TextEditingController(text: supplier?['note']?.toString() ?? '');
    bool isActive = supplier?['is_active'] != false;
    bool saving = false;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text(isEdit ? tr('Postavshikni tahrirlash') : tr('Yangi postavshik'),
              style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 17)),
          content: SizedBox(
            width: (MediaQuery.of(context).size.width * 0.9).clamp(0.0, 420.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                      controller: nameCtrl,
                      style: TextStyle(color: AppTheme.text),
                      decoration: _dec(tr('Nomi'), Icons.business)),
                  const SizedBox(height: 10),
                  TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      style: TextStyle(color: AppTheme.text),
                      decoration: _dec(tr('Telefon'), Icons.phone)),
                  const SizedBox(height: 10),
                  TextField(
                      controller: contactCtrl,
                      style: TextStyle(color: AppTheme.text),
                      decoration: _dec(tr('Mas\'ul shaxs'), Icons.person)),
                  const SizedBox(height: 10),
                  TextField(
                      controller: addressCtrl,
                      style: TextStyle(color: AppTheme.text),
                      decoration: _dec(tr('Manzil'), Icons.location_on)),
                  const SizedBox(height: 10),
                  TextField(
                      controller: noteCtrl,
                      style: TextStyle(color: AppTheme.text),
                      decoration: _dec(tr('Izoh'), Icons.notes)),
                  if (isEdit) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(
                          child: Text(tr('Faol'),
                              style: TextStyle(color: AppTheme.text, fontSize: 14))),
                      Switch(
                          value: isActive, onChanged: (v) => setD(() => isActive = v)),
                    ]),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success, foregroundColor: Colors.white),
              onPressed: saving
                  ? null
                  : () async {
                      final name = nameCtrl.text.trim();
                      if (name.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                            content: Text(tr('Nomini kiriting')),
                            backgroundColor: Colors.red));
                        return;
                      }
                      setD(() => saving = true);
                      try {
                        final body = <String, dynamic>{
                          'name': name,
                          'phone': phoneCtrl.text.trim(),
                          'contact_person': contactCtrl.text.trim(),
                          'address': addressCtrl.text.trim(),
                          'note': noteCtrl.text.trim(),
                          if (isEdit) 'is_active': isActive,
                        };
                        final r = isEdit
                            ? await ApiService.put(
                                '/stock/suppliers/${supplier['id']}', body)
                            : await ApiService.post('/stock/suppliers', body);
                        if (!mounted) return;
                        if (r is Map && r['message'] != null) {
                          if (ctx.mounted) setD(() => saving = false);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(r['message'].toString()),
                              backgroundColor: Colors.red));
                        } else {
                          if (ctx.mounted) Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(tr('Saqlandi')),
                              backgroundColor: Colors.green));
                          _load();
                        }
                      } catch (e) {
                        if (ctx.mounted) setD(() => saving = false);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('${tr('Xato')}: $e'),
                            backgroundColor: Colors.red));
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(tr('Saqlash')),
            ),
          ],
        ),
      ),
    );
  }

  // ── O'chirish (tarixi bo'lsa server arxivlaydi) ──
  Future<void> _deleteSupplier(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('O\'chirish'),
            style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 17)),
        content: Text('${s['name'] ?? ''} — ${tr('Rostdan o\'chirilsinmi?')}',
            style: TextStyle(color: AppTheme.textSoft)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Yo\'q'), style: TextStyle(color: AppTheme.textSoft))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.danger, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Ha'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await ApiService.delete('/stock/suppliers/${s['id']}');
      if (!mounted) return;
      if (r is Map && r['message'] != null) {
        // DELETE muvaffaqiyatda ham {message} qaytaradi (o'chirildi yoki arxivlandi)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(r['message'].toString()), backgroundColor: Colors.green));
      }
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
    }
  }

  Widget _stat(String label, dynamic value, Color color) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
            const SizedBox(height: 2),
            Text(_money(value),
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      );

  Widget _supplierCard(Map<String, dynamic> s) {
    final debt = _num(s['total_debt']).toDouble();
    final active = s['is_active'] != false;
    final phone = (s['phone'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SupplierLedgerPage(
                supplierId: _num(s['id']).toInt(),
                supplierName: (s['name'] ?? '').toString(),
              ),
            ),
          ).then((_) => _load()),
          onLongPress: () => _showSupplierDialog(supplier: s),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text((s['name'] ?? '').toString(),
                        style: TextStyle(
                            color: AppTheme.text,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                  ),
                  if (!active)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                          color: AppTheme.warningSoft,
                          borderRadius: BorderRadius.circular(999)),
                      child: Text(tr('Arxiv'),
                          style: const TextStyle(
                              color: AppTheme.warning,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: AppTheme.accentSoft,
                        borderRadius: BorderRadius.circular(999)),
                    child: Text('${_num(s['lot_count']).toInt()} ${tr('partiya')}',
                        style: TextStyle(
                            color: AppTheme.accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    icon: Icon(Icons.edit, size: 18, color: AppTheme.textSoft),
                    tooltip: tr('Tahrirlash'),
                    onPressed: () => _showSupplierDialog(supplier: s),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.danger),
                    tooltip: tr('O\'chirish'),
                    onPressed: () => _deleteSupplier(s),
                  ),
                ]),
                if (phone.isNotEmpty)
                  Text(phone, style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
                const SizedBox(height: 10),
                Row(children: [
                  _stat(tr('Zakupka'), s['total_purchases'], Colors.blue),
                  _stat(tr('To\'langan'), s['total_paid'], AppTheme.success),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr('Qarz'),
                            style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
                        const SizedBox(height: 2),
                        debt > 0
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                    color: AppTheme.dangerSoft,
                                    borderRadius: BorderRadius.circular(999)),
                                child: Text(_money(debt),
                                    style: const TextStyle(
                                        color: AppTheme.danger,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                              )
                            : Text(_money(0),
                                style: TextStyle(
                                    color: AppTheme.textSoft,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                      ],
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        iconTheme: IconThemeData(color: AppTheme.text),
        title: Text(tr('Postavshiklar'),
            style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
              icon: Icon(Icons.refresh, color: AppTheme.textSoft), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.accent,
        onPressed: () => _showSupplierDialog(),
        child: Icon(Icons.add, color: AppTheme.onAccent),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : _suppliers.isEmpty
              ? Center(
                  child: Text(tr('Postavshiklar yo\'q'),
                      style: TextStyle(color: AppTheme.textSoft)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _suppliers.length,
                    itemBuilder: (_, i) {
                      final s = _suppliers[i];
                      return s is Map
                          ? _supplierCard(Map<String, dynamic>.from(s))
                          : const SizedBox.shrink();
                    },
                  ),
                ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// POSTAVSHIK KARTOTEKASI (ledger)
// ═══════════════════════════════════════════════════════════════════════════

class SupplierLedgerPage extends StatefulWidget {
  const SupplierLedgerPage(
      {super.key, required this.supplierId, required this.supplierName});

  final int supplierId;
  final String supplierName;

  @override
  State<SupplierLedgerPage> createState() => _SupplierLedgerPageState();
}

class _SupplierLedgerPageState extends State<SupplierLedgerPage> {
  Map<String, dynamic>? _data;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final r = await ApiService.get('/stock/suppliers/${widget.supplierId}/ledger');
      if (!mounted) return;
      if (r is Map && r['supplier'] != null) {
        setState(() {
          _data = Map<String, dynamic>.from(r);
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        if (r is Map && r['message'] != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(r['message'].toString()), backgroundColor: Colors.red));
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
    }
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppTheme.bg,
        labelStyle: TextStyle(color: AppTheme.textSoft),
        prefixIcon: Icon(icon, color: AppTheme.accent),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppTheme.textSoft)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppTheme.accent)),
      );

  // ── Qarz to'lash dialogi ──
  void _showPayDialog() {
    final totals = _data?['totals'] is Map ? _data!['totals'] as Map : {};
    final debt = _num(totals['debt']).toDouble();
    final amountCtrl = TextEditingController(text: debt.toStringAsFixed(0));
    final noteCtrl = TextEditingController();
    String method = 'cash';
    bool fromKassa = true;
    bool saving = false;

    Widget chip(String label, bool sel, VoidCallback onTap) => Expanded(
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: sel ? AppTheme.accentSoft : AppTheme.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: sel ? AppTheme.accent : AppTheme.border),
              ),
              alignment: Alignment.center,
              child: Text(label,
                  style: TextStyle(
                      color: sel ? AppTheme.accent : AppTheme.textSoft,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ),
          ),
        );

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text(tr('Qarz to\'lash'),
              style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 17)),
          content: SizedBox(
            width: (MediaQuery.of(context).size.width * 0.9).clamp(0.0, 380.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: decimalFormatters,
                    style: TextStyle(color: AppTheme.text),
                    decoration: _dec(tr('Summa'), Icons.payments),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('${tr('Qarz')}: ${_money(debt)}',
                        style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    chip(tr('Naqd'), method == 'cash', () => setD(() => method = 'cash')),
                    const SizedBox(width: 8),
                    chip(tr('Karta'), method == 'card', () => setD(() => method = 'card')),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    chip(tr('Kassadan'), fromKassa, () => setD(() => fromKassa = true)),
                    const SizedBox(width: 8),
                    chip(tr('Boshqa joydan'), !fromKassa,
                        () => setD(() => fromKassa = false)),
                  ]),
                  const SizedBox(height: 10),
                  TextField(
                      controller: noteCtrl,
                      style: TextStyle(color: AppTheme.text),
                      decoration: _dec(tr('Izoh'), Icons.notes)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success, foregroundColor: Colors.white),
              onPressed: saving
                  ? null
                  : () async {
                      final amount = double.tryParse(amountCtrl.text.trim()) ?? 0;
                      if (amount <= 0) {
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                            content: Text(tr('Summani kiriting')),
                            backgroundColor: Colors.red));
                        return;
                      }
                      setD(() => saving = true);
                      try {
                        final r = await ApiService.post(
                          '/stock/suppliers/${widget.supplierId}/pay',
                          {
                            'amount': amount,
                            'method': method,
                            'from_kassa': fromKassa,
                            if (noteCtrl.text.trim().isNotEmpty)
                              'note': noteCtrl.text.trim(),
                          },
                          idempotencyKey: ApiService.newIdempotencyKey(),
                        );
                        if (!mounted) return;
                        if (r is Map && r['message'] != null) {
                          if (ctx.mounted) setD(() => saving = false);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(r['message'].toString()),
                              backgroundColor: Colors.red));
                        } else {
                          if (ctx.mounted) Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(tr('To\'lov saqlandi')),
                              backgroundColor: Colors.green));
                          _load();
                        }
                      } catch (e) {
                        if (ctx.mounted) setD(() => saving = false);
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('${tr('Xato')}: $e'),
                            backgroundColor: Colors.red));
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(tr('To\'lash')),
            ),
          ],
        ),
      ),
    );
  }

  // ── Kichik quruvchilar ──

  Widget _kpi(String label, String value, Color color) => Container(
        width: 158,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
          ],
        ),
      );

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999)),
        child: Text(text,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      );

  Widget _section(String title, IconData icon, List<Widget> children,
      {bool expanded = false, int count = 0}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: expanded,
          leading: Icon(icon, color: AppTheme.accent, size: 20),
          iconColor: AppTheme.accent,
          collapsedIconColor: AppTheme.textSoft,
          title: Row(children: [
            Flexible(
              child: Text(title,
                  style: TextStyle(
                      color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 14)),
            ),
            const SizedBox(width: 8),
            if (count > 0) _badge('$count', AppTheme.accent),
          ]),
          children: children.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(tr('Ma\'lumot yo\'q'),
                        style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
                  )
                ]
              : children,
        ),
      ),
    );
  }

  Widget _lotRow(Map l) {
    final debt = _num(l['debt_amount']).toDouble();
    final invoice = (l['invoice_no'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(
                  '${l['lot_code'] ?? ''}${invoice.isNotEmpty ? ' • $invoice' : ''}',
                  style: TextStyle(
                      color: AppTheme.text, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            Text(_d(l['received_at']),
                style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
          ]),
          const SizedBox(height: 2),
          Text('${l['ingredient_name'] ?? ''}',
              style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: Text(
                  '${_qty(l['quantity'])} ${l['unit'] ?? ''} × ${_num(l['unit_cost']).toDouble().toStringAsFixed(0)} = ${_money(l['total_cost'])}',
                  style: TextStyle(color: AppTheme.text, fontSize: 12)),
            ),
            if (debt > 0) ...[
              _badge('${tr('Qarz')}: ${_money(debt)}', AppTheme.danger),
              const SizedBox(width: 6),
            ],
            _badge('${l['status'] ?? ''}', AppTheme.textSoft),
          ]),
        ],
      ),
    );
  }

  Widget _paymentRow(Map p) {
    final refund = (p['kind'] ?? '') == 'refund';
    final amountColor = refund ? Colors.orange : AppTheme.success;
    final lot = (p['lot_code'] ?? '').toString();
    final invoice = (p['invoice_no'] ?? '').toString();
    final note = (p['note'] ?? '').toString();
    final paidBy = (p['paid_by_name'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(_d(p['created_at']),
                  style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
            ),
            if (refund) ...[
              _badge(tr('Vozvrat'), Colors.orange),
              const SizedBox(width: 6),
            ],
            Text(_money(p['amount']),
                style: TextStyle(
                    color: amountColor, fontWeight: FontWeight.bold, fontSize: 13)),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            _badge((p['method'] ?? '') == 'card' ? tr('Karta') : tr('Naqd'),
                AppTheme.accent),
            const SizedBox(width: 6),
            if (lot.isNotEmpty || invoice.isNotEmpty)
              Expanded(
                child: Text('$lot${invoice.isNotEmpty ? ' • $invoice' : ''}',
                    style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
              )
            else
              const Spacer(),
            if (paidBy.isNotEmpty)
              Text(paidBy, style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
          ]),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(note,
                style: TextStyle(
                    color: AppTheme.textSoft, fontSize: 11, fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }

  Widget _returnRow(Map r) {
    final note = (r['note'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${r['lot_code'] ?? ''} • ${r['ingredient_name'] ?? ''}',
                    style: TextStyle(
                        color: AppTheme.text, fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                Text('${_d(r['created_at'])}${note.isNotEmpty ? ' • $note' : ''}',
                    style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
              ],
            ),
          ),
          Text(
              '${_qty(r['quantity'])} × ${_num(r['unit_cost']).toDouble().toStringAsFixed(0)}',
              style: const TextStyle(
                  color: Colors.orange, fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ),
    );
  }

  List<Widget> _priceGroups(List prices) {
    final Map<String, List<Map>> groups = {};
    for (final p in prices) {
      if (p is! Map) continue;
      groups.putIfAbsent((p['ingredient_name'] ?? '').toString(), () => []).add(p);
    }
    final out = <Widget>[];
    groups.forEach((name, list) {
      final chips = <Widget>[];
      for (int i = 0; i < list.length; i++) {
        final cost = _num(list[i]['unit_cost']).toDouble();
        Color c = AppTheme.textSoft;
        if (i > 0) {
          final prev = _num(list[i - 1]['unit_cost']).toDouble();
          if (cost > prev) {
            c = AppTheme.danger; // qimmatlashdi
          } else if (cost < prev) {
            c = AppTheme.success; // arzonlashdi
          }
        }
        chips.add(Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
              color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(6)),
          child: Text('${_d(list[i]['date'])}: ${cost.toStringAsFixed(0)}',
              style: TextStyle(color: c, fontSize: 11)),
        ));
      }
      out.add(Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name,
                style: TextStyle(
                    color: AppTheme.text, fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: chips),
          ],
        ),
      ));
    });
    return out;
  }

  Widget _discountRow(Map d) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${d['lot_code'] ?? ''} • ${d['ingredient_name'] ?? ''}',
                      style: TextStyle(
                          color: AppTheme.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                  const SizedBox(height: 2),
                  Text('${_d(d['date'])} • ${_money(d['total_cost'])}',
                      style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
                ],
              ),
            ),
            Text('-${_money(d['discount_amount'])}',
                style: const TextStyle(
                    color: AppTheme.success, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      );

  Widget _overdueRow(Map o) {
    final invoice = (o['invoice_no'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${o['lot_code'] ?? ''}${invoice.isNotEmpty ? ' • $invoice' : ''}',
                    style: TextStyle(
                        color: AppTheme.text, fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                Text('${o['ingredient_name'] ?? ''} • ${_d(o['date'])}',
                    style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
              ],
            ),
          ),
          Text(_money(o['debt_amount']),
              style: const TextStyle(
                  color: AppTheme.danger, fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(width: 8),
          _badge('${_num(o['age_days']).toInt()} ${tr('kun')}', AppTheme.danger),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.bg,
        elevation: 0,
        iconTheme: IconThemeData(color: AppTheme.text),
        title: Text(widget.supplierName,
            style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [
          IconButton(
              icon: Icon(Icons.refresh, color: AppTheme.textSoft), onPressed: _load),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : d == null
              ? Center(
                  child: Text(tr('Ma\'lumot yo\'q'),
                      style: TextStyle(color: AppTheme.textSoft)))
              : _buildBody(d),
    );
  }

  Widget _buildBody(Map<String, dynamic> d) {
    final sup = d['supplier'] is Map ? d['supplier'] as Map : {};
    final totals = d['totals'] is Map ? d['totals'] as Map : {};
    final rating = _num(d['rating']).toInt();
    final ratingColor = rating >= 80
        ? AppTheme.success
        : rating >= 50
            ? Colors.orange
            : AppTheme.danger;
    final debt = _num(totals['debt']).toDouble();
    final avgDays = totals['avg_payment_days'];
    final overdue = d['overdue'] is List ? d['overdue'] as List : [];
    final lots = d['lots'] is List ? d['lots'] as List : [];
    final payments = d['payments'] is List ? d['payments'] as List : [];
    final returns = d['returns'] is List ? d['returns'] as List : [];
    final prices = d['price_history'] is List ? d['price_history'] as List : [];
    final discounts = d['discounts'] is List ? d['discounts'] as List : [];
    final phone = (sup['phone'] ?? '').toString();
    final contact = (sup['contact_person'] ?? '').toString();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Shapka: nom + reyting doirasi ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((sup['name'] ?? widget.supplierName).toString(),
                        style: TextStyle(
                            color: AppTheme.text,
                            fontWeight: FontWeight.bold,
                            fontSize: 17)),
                    if (phone.isNotEmpty || contact.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                          [phone, contact]
                              .where((e) => e.isNotEmpty)
                              .join(' • '),
                          style: TextStyle(color: AppTheme.textSoft, fontSize: 13)),
                    ],
                  ],
                ),
              ),
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ratingColor.withValues(alpha: 0.12),
                  border: Border.all(color: ratingColor, width: 2),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('$rating',
                        style: TextStyle(
                            color: ratingColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 22)),
                    Text(tr('Reyting'),
                        style: TextStyle(color: AppTheme.textSoft, fontSize: 9)),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),

          // ── KPI kartochkalari ──
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _kpi(tr('Jami zakupka'), _money(totals['purchases']), AppTheme.text),
              _kpi(tr('To\'langan'), _money(totals['paid']), AppTheme.success),
              _kpi(tr('Qarz'), _money(debt),
                  debt > 0 ? AppTheme.danger : AppTheme.textSoft),
              _kpi(tr('Chegirmalar'), _money(totals['discounts']), AppTheme.violet),
              _kpi(
                  tr('O\'rtacha to\'lov muddati'),
                  avgDays == null
                      ? '-'
                      : '~${_num(avgDays).toDouble().toStringAsFixed(0)} ${tr('kun')}',
                  AppTheme.text),
              _kpi(tr('Partiyalar'), '${_num(totals['lot_count']).toInt()}',
                  AppTheme.accent),
            ],
          ),
          const SizedBox(height: 12),

          // ── Qarz to'lash tugmasi ──
          if (debt > 0) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.payments, size: 18),
                label: Text(tr('Qarz to\'lash'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                onPressed: _showPayDialog,
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Kechikkan to'lovlar ──
          if (overdue.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.danger),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: AppTheme.danger, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(tr('Kechikkan to\'lovlar'),
                          style: const TextStyle(
                              color: AppTheme.danger,
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                    ),
                    Text(_money(d['overdue_total']),
                        style: const TextStyle(
                            color: AppTheme.danger,
                            fontWeight: FontWeight.bold,
                            fontSize: 14)),
                  ]),
                  const SizedBox(height: 4),
                  ...overdue.whereType<Map>().map(_overdueRow),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Ochiladigan bo'limlar ──
          _section(tr('Partiyalar'), Icons.inventory_2,
              lots.whereType<Map>().map(_lotRow).toList(),
              expanded: true, count: lots.length),
          _section(tr('To\'lovlar tarixi'), Icons.receipt_long,
              payments.whereType<Map>().map(_paymentRow).toList(),
              count: payments.length),
          _section(tr('Vozvratlar'), Icons.keyboard_return,
              returns.whereType<Map>().map(_returnRow).toList(),
              count: returns.length),
          _section(tr('Narx o\'zgarishi'), Icons.trending_up, _priceGroups(prices)),
          _section(tr('Chegirmalar tarixi'), Icons.percent,
              discounts.whereType<Map>().map(_discountRow).toList(),
              count: discounts.length),

          // ── Reyting izohi ──
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Text(tr('Reyting: to\'lovlar 60% + muddat 30% + faollik 10%'),
                  style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../../core/lang.dart';
import '../../core/num_input.dart';

/// Partiyalar (lot) va srok nazorati sahifalari.
/// - [LotsPage]  — barcha partiyalar (yoki bitta mahsulotniki), filtr + detal dialog,
///   to'lash / spisaniya / vozvrat / bloklash amallari.
/// - [ExpiryPage] — srok o'tgan / tez tugaydigan partiyalar + oylik yo'qotishlar.
/// API: GET /stock/lots, GET /stock/lots/:id, POST pay|writeoff|return|block, GET /stock/expiry.

// ═══════════════ Umumiy yordamchilar ═══════════════

/// ISO sana -> 'YYYY-MM-DD' (bo'sh bo'lsa em-tire).
String _d(dynamic s) {
  if (s == null) return '—';
  final t = s.toString();
  if (t.isEmpty) return '—';
  return t.split('T')[0];
}

double _num(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0;

/// Pul: 1234567 -> '1 234 568' (so'm matni chaqiruvchida qo'shiladi).
String _money(dynamic v) {
  final n = _num(v);
  final neg = n < 0;
  final s = n.abs().round().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return (neg ? '-' : '') + buf.toString();
}

/// Miqdor: butun bo'lsa kasrsiz, aks holda 2 xona.
String _qty(dynamic v) {
  final n = _num(v);
  if (n == n.roundToDouble()) return n.toStringAsFixed(0);
  return n.toStringAsFixed(2);
}

/// Srok rangi: o'tgan — qizil, 5 kun ichida — apelsin, aks holda null.
Color? _expiryColor(String? expiryDate) {
  if (expiryDate == null || expiryDate.isEmpty) return null;
  final p = DateTime.tryParse(expiryDate.split('T')[0]);
  if (p == null) return null;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final e = DateTime(p.year, p.month, p.day);
  if (e.isBefore(today)) return Colors.red;
  if (e.difference(today).inDays <= 5) return Colors.orange;
  return null;
}

/// Srokgacha necha kun qoldi (o'tgan bo'lsa manfiy), sana yo'q bo'lsa null.
int? _daysLeft(String? expiryDate) {
  if (expiryDate == null || expiryDate.isEmpty) return null;
  final p = DateTime.tryParse(expiryDate.split('T')[0]);
  if (p == null) return null;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return DateTime(p.year, p.month, p.day).difference(today).inDays;
}

/// Partiya holati -> rangli badge.
Widget _statusBadge(String? status) {
  Color c;
  String label;
  switch (status) {
    case 'active':
      c = Colors.green;
      label = tr('Aktiv');
      break;
    case 'depleted':
      c = Colors.grey;
      label = tr('Tugadi');
      break;
    case 'written_off':
      c = Colors.red;
      label = tr('Spisan');
      break;
    case 'blocked':
      c = Colors.orange;
      label = tr('Bloklangan');
      break;
    default:
      c = Colors.grey;
      label = status ?? '';
  }
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: c.withValues(alpha: 0.5)),
    ),
    child: Text(label, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.bold)),
  );
}

/// Sarf sababi (consumption reason) -> o'zbekcha.
String _reasonUz(String? r) {
  switch (r) {
    case 'sale':
      return tr('Sotuv');
    case 'pf_production':
      return tr('P/F');
    case 'writeoff':
      return tr('Spisaniya');
    case 'expired':
      return tr('Srok o\'tdi');
    case 'inventory':
      return tr('Inventar');
    case 'restore':
      return tr('Qaytarish');
    case 'manual':
      return tr('Korrektirovka');
    case 'return':
      return tr('Vozvrat');
    default:
      return r ?? '';
  }
}

InputDecoration _dec(String label, IconData icon) => InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: AppTheme.textSoft),
      prefixIcon: Icon(icon, color: AppTheme.accent),
      filled: true,
      fillColor: AppTheme.bg,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.textSoft)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppTheme.accent)),
    );

/// Detal dialogdagi "kalit: qiymat" qatori.
Widget _kv(String k, String v, {Color? color, bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 150, child: Text(k, style: TextStyle(color: AppTheme.textSoft, fontSize: 12.5))),
        Expanded(
          child: Text(v,
              style: TextStyle(
                  color: color ?? AppTheme.text,
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
        ),
      ]),
    );

/// Kartadagi kichik "ikonka + matn" bo'lagi.
Widget _iconText(IconData icon, String text, {Color? color}) => Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: color ?? AppTheme.textSoft),
      const SizedBox(width: 4),
      Text(text, style: TextStyle(color: color ?? AppTheme.textSoft, fontSize: 12)),
    ]);

// ═══════════════ Partiya amallari (LotsPage va ExpiryPage baham ko'radi) ═══════════════

mixin _LotActions<T extends StatefulWidget> on State<T> {
  /// Amal (to'lash/spisaniya/vozvrat/blok) muvaffaqiyatli o'tgach ro'yxatni yangilash.
  Future<void> _reloadAfterAction();

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? Colors.red : Colors.green),
    );
  }

  Widget _toggleBox(String label, bool sel) => Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: sel ? AppTheme.accent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: sel ? AppTheme.accent : AppTheme.border),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: sel ? AppTheme.accent : AppTheme.textSoft,
                fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                fontSize: 13)),
      );

  // ─── Partiya detali ───
  Future<void> _showLotDetail(int lotId) async {
    dynamic r;
    try {
      r = await ApiService.get('/stock/lots/$lotId');
    } on ApiException catch (e) {
      _snack(e.message, error: true);
      return;
    }
    if (!mounted) return;
    if (r is! Map || r['id'] == null) {
      _snack((r is Map && r['message'] != null) ? r['message'].toString() : tr('Ma\'lumot yo\'q'), error: true);
      return;
    }
    final lot = Map<String, dynamic>.from(r);
    final payments = (lot['payments'] as List?) ?? [];
    final consumptions = (lot['consumptions'] as List?) ?? [];
    final status = lot['status']?.toString() ?? '';
    final unit = (lot['unit'] ?? lot['ingredient_unit'] ?? '').toString();
    final remaining = _num(lot['remaining_quantity']);
    final debt = _num(lot['debt_amount']);
    final discount = _num(lot['discount_amount']);
    final expiry = lot['expiry_date']?.toString();

    // Amal tugagach: detalni yopib, ro'yxatni yangilab, yangi ma'lumot bilan qayta ochamiz.
    Future<void> runAction(BuildContext dctx, Future<bool?> Function() action) async {
      final ok = await action();
      if (ok == true && dctx.mounted) {
        Navigator.pop(dctx);
        await _reloadAfterAction();
        if (mounted) _showLotDetail(lotId);
      }
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (dctx) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Row(children: [
          Expanded(
            child: Text('${lot['lot_code'] ?? ''}',
                style: TextStyle(color: AppTheme.text, fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis),
          ),
          _statusBadge(status),
        ]),
        content: SizedBox(
          width: (MediaQuery.of(context).size.width * 0.9).clamp(0.0, 460.0),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _kv(tr('Mahsulot'), '${lot['ingredient_name'] ?? ''}${unit.isNotEmpty ? ' ($unit)' : ''}'),
                if (lot['supplier_name'] != null)
                  _kv(tr('Yetkazib beruvchi'), lot['supplier_name'].toString()),
                if ((lot['invoice_no'] ?? '').toString().isNotEmpty)
                  _kv(tr('Nakladnoy'), lot['invoice_no'].toString()),
                _kv(tr('Xarid sanasi'), _d(lot['purchase_date'])),
                _kv(tr('Kelgan sana'), _d(lot['received_at'])),
                if ((expiry ?? '').isNotEmpty)
                  _kv(tr('Srok'), _d(expiry), color: _expiryColor(expiry), bold: _expiryColor(expiry) != null),
                _kv(tr('Miqdori'), '${_qty(lot['quantity'])} $unit'),
                _kv(tr('Ishlatilgan'), '${_qty(lot['used_quantity'])} $unit'),
                _kv(tr('Qoldiq'), '${_qty(remaining)} $unit', bold: true),
                _kv(tr('Birlik narxi'), '${_money(lot['unit_cost'])} ${tr('so\'m')}'),
                if (discount > 0) _kv(tr('Chegirma'), '${_money(discount)} ${tr('so\'m')}'),
                _kv(tr('Jami summa'), '${_money(lot['total_cost'])} ${tr('so\'m')}', bold: true),
                _kv(tr('Qoldiq qiymati'), '${_money(lot['remaining_cost'])} ${tr('so\'m')}'),
                _kv(tr('To\'langan'), '${_money(lot['paid_amount'])} ${tr('so\'m')}', color: Colors.green),
                _kv(tr('Qarz'), '${_money(debt)} ${tr('so\'m')}', color: debt > 0 ? Colors.red : null, bold: debt > 0),
                if ((lot['note'] ?? '').toString().isNotEmpty) _kv(tr('Izoh'), lot['note'].toString()),
                if (lot['created_by_name'] != null) _kv(tr('Kiritdi'), lot['created_by_name'].toString()),
                _kv(tr('Yaratilgan'), _d(lot['created_at'])),
                const SizedBox(height: 12),
                // ─── Amallar (faqat tegishlilari) ───
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (debt > 0)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: AppTheme.onAccent),
                      icon: const Icon(Icons.payments, size: 16),
                      label: Text(tr('To\'lash')),
                      onPressed: () => runAction(dctx, () => _payDialog(lot)),
                    ),
                  if (remaining > 0 && (status == 'active' || status == 'blocked'))
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: AppTheme.onAccent),
                      icon: const Icon(Icons.delete_sweep, size: 16),
                      label: Text(tr('Spisaniya')),
                      onPressed: () => runAction(dctx, () => _writeoffDialog(lot)),
                    ),
                  if (remaining > 0)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.purple, foregroundColor: AppTheme.onAccent),
                      icon: const Icon(Icons.u_turn_left, size: 16),
                      label: Text(tr('Vozvrat')),
                      onPressed: () => runAction(dctx, () => _returnDialog(lot)),
                    ),
                  if (status == 'active' || status == 'blocked')
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: status == 'blocked' ? Colors.teal : Colors.orange,
                          foregroundColor: AppTheme.onAccent),
                      icon: Icon(status == 'blocked' ? Icons.lock_open : Icons.block, size: 16),
                      label: Text(status == 'blocked' ? tr('Blokdan chiqarish') : tr('Bloklash')),
                      onPressed: () => runAction(dctx, () => _blockDialog(lot)),
                    ),
                ]),
                // ─── To'lovlar tarixi ───
                if (payments.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(tr('To\'lovlar'), style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  ...payments.map((p) => _paymentRow(Map<String, dynamic>.from(p as Map))),
                ],
                // ─── Sarf tarixi ───
                if (consumptions.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(tr('Harakatlar'), style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  ...consumptions.map((c) => _consumptionRow(Map<String, dynamic>.from(c as Map), unit)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: Text(tr('Yopish'), style: TextStyle(color: AppTheme.textSoft)),
          ),
        ],
      ),
    );
  }

  Widget _paymentRow(Map<String, dynamic> p) {
    final refund = p['kind'] == 'refund';
    final c = refund ? Colors.orange : Colors.green;
    final method = p['method'] == 'card' ? tr('Karta') : tr('Naqd');
    final kassa = p['from_kassa'] == true ? tr('Kassadan') : tr('Boshqa joydan');
    final note = (p['note'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(refund ? Icons.undo : Icons.payments, size: 15, color: c),
        const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${refund ? tr('Vozvrat') : tr('To\'lov')} — $method, $kassa',
                style: TextStyle(color: AppTheme.text, fontSize: 12.5)),
            Text(
              '${_d(p['created_at'])}${p['paid_by_name'] != null ? ' • ${p['paid_by_name']}' : ''}${note.isNotEmpty ? ' • $note' : ''}',
              style: TextStyle(color: AppTheme.textSoft, fontSize: 11),
            ),
          ]),
        ),
        Text('${refund ? '-' : '+'}${_money(p['amount'])}',
            style: TextStyle(color: c, fontSize: 12.5, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _consumptionRow(Map<String, dynamic> c, String unit) {
    final reason = c['reason']?.toString();
    final q = _num(c['quantity']);
    final value = q * _num(c['unit_cost']);
    final note = (c['note'] ?? '').toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AppTheme.accentSoft,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(_reasonUz(reason), style: TextStyle(color: AppTheme.accent, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${_qty(q)} $unit${note.isNotEmpty ? ' • $note' : ''}',
            style: TextStyle(color: AppTheme.text, fontSize: 12.5),
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${_money(value)} ${tr('so\'m')}', style: TextStyle(color: AppTheme.text, fontSize: 12)),
          Text(_d(c['created_at']), style: TextStyle(color: AppTheme.textSoft, fontSize: 10.5)),
        ]),
      ]),
    );
  }

  // ─── To'lash (qarz yopish) ───
  Future<bool?> _payDialog(Map<String, dynamic> lot) {
    final debt = _num(lot['debt_amount']);
    final amountController = TextEditingController(text: debt > 0 ? debt.toStringAsFixed(0) : '');
    final noteController = TextEditingController();
    String method = 'cash';
    bool fromKassa = true;
    bool saving = false;
    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text('${lot['lot_code'] ?? ''} — ${tr('To\'lash')}', style: TextStyle(color: AppTheme.text)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                inputFormatters: decimalFormatters,
                style: TextStyle(color: AppTheme.text),
                decoration: _dec('${tr('Summa')} (${tr('so\'m')})', Icons.payments),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setStateDialog(() => method = 'cash'),
                    child: _toggleBox(tr('Naqd'), method == 'cash'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setStateDialog(() => method = 'card'),
                    child: _toggleBox(tr('Karta'), method == 'card'),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setStateDialog(() => fromKassa = true),
                    child: _toggleBox(tr('Kassadan'), fromKassa),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setStateDialog(() => fromKassa = false),
                    child: _toggleBox(tr('Boshqa joydan'), !fromKassa),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                style: TextStyle(color: AppTheme.text),
                decoration: _dec(tr('Izoh'), Icons.note),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: saving
                  ? null
                  : () async {
                      final amount = double.tryParse(amountController.text) ?? 0;
                      if (amount <= 0) return;
                      setStateDialog(() => saving = true);
                      try {
                        final r = await ApiService.post('/stock/lots/${lot['id']}/pay', {
                          'amount': amount,
                          'method': method,
                          'from_kassa': fromKassa,
                          'note': noteController.text.trim(),
                        }, idempotencyKey: ApiService.newIdempotencyKey());
                        if (r is Map && r['message'] != null && r['ok'] != true) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(r['message'].toString()), backgroundColor: Colors.red),
                            );
                          }
                          return;
                        }
                        if (context.mounted) Navigator.pop(context, true);
                        _snack('${tr('To\'lov qilindi')}: ${_money(amount)} ${tr('so\'m')}');
                      } on ApiException catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e.message), backgroundColor: Colors.red),
                          );
                        }
                      } finally {
                        if (context.mounted) setStateDialog(() => saving = false);
                      }
                    },
              child: Text(tr('To\'lash'), style: TextStyle(color: AppTheme.onAccent)),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Spisaniya ───
  Future<bool?> _writeoffDialog(Map<String, dynamic> lot) {
    final remaining = _num(lot['remaining_quantity']);
    final unit = (lot['unit'] ?? lot['ingredient_unit'] ?? '').toString();
    final qtyController = TextEditingController(
        text: remaining == remaining.roundToDouble() ? remaining.toStringAsFixed(0) : remaining.toString());
    final reasonController = TextEditingController();
    bool saving = false;
    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text('${lot['lot_code'] ?? ''} — ${tr('Spisaniya')}', style: TextStyle(color: AppTheme.text)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                inputFormatters: decimalFormatters,
                style: TextStyle(color: AppTheme.text),
                decoration: _dec('${tr('Miqdori')} ($unit)', Icons.numbers),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                style: TextStyle(color: AppTheme.text),
                decoration: _dec(tr('Sabab'), Icons.help_outline),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: saving
                  ? null
                  : () async {
                      final q = double.tryParse(qtyController.text) ?? 0;
                      if (q <= 0) return;
                      if (reasonController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(tr('Sabab kiritilishi shart')), backgroundColor: Colors.red),
                        );
                        return;
                      }
                      setStateDialog(() => saving = true);
                      try {
                        final r = await ApiService.post('/stock/lots/${lot['id']}/writeoff', {
                          'quantity': q,
                          'reason': reasonController.text.trim(),
                        }, idempotencyKey: ApiService.newIdempotencyKey());
                        if (r is Map && r['message'] != null && r['ok'] != true) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(r['message'].toString()), backgroundColor: Colors.red),
                            );
                          }
                          return;
                        }
                        if (context.mounted) Navigator.pop(context, true);
                        final loss = (r is Map) ? _num(r['loss_value']) : 0.0;
                        _snack('${tr('Spisaniya qilindi')}. ${tr('Yo\'qotish')}: ${_money(loss)} ${tr('so\'m')}');
                      } on ApiException catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e.message), backgroundColor: Colors.red),
                          );
                        }
                      } finally {
                        if (context.mounted) setStateDialog(() => saving = false);
                      }
                    },
              child: Text(tr('Spisaniya'), style: TextStyle(color: AppTheme.onAccent)),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Vozvrat (yetkazib beruvchiga qaytarish) ───
  Future<bool?> _returnDialog(Map<String, dynamic> lot) {
    final remaining = _num(lot['remaining_quantity']);
    final unit = (lot['unit'] ?? lot['ingredient_unit'] ?? '').toString();
    final qtyController = TextEditingController(
        text: remaining == remaining.roundToDouble() ? remaining.toStringAsFixed(0) : remaining.toString());
    final reasonController = TextEditingController();
    bool refundToKassa = false;
    bool saving = false;
    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text('${lot['lot_code'] ?? ''} — ${tr('Vozvrat')}', style: TextStyle(color: AppTheme.text)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                inputFormatters: decimalFormatters,
                style: TextStyle(color: AppTheme.text),
                decoration: _dec('${tr('Miqdori')} ($unit)', Icons.numbers),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                style: TextStyle(color: AppTheme.text),
                decoration: _dec(tr('Sabab'), Icons.help_outline),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: refundToKassa,
                activeColor: AppTheme.accent,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(tr('Pul kassaga qaytadi'), style: TextStyle(color: AppTheme.text, fontSize: 13)),
                onChanged: (v) => setStateDialog(() => refundToKassa = v ?? false),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: saving
                  ? null
                  : () async {
                      final q = double.tryParse(qtyController.text) ?? 0;
                      if (q <= 0) return;
                      setStateDialog(() => saving = true);
                      try {
                        final r = await ApiService.post('/stock/lots/${lot['id']}/return', {
                          'quantity': q,
                          'refund_to_kassa': refundToKassa,
                          'reason': reasonController.text.trim(),
                        }, idempotencyKey: ApiService.newIdempotencyKey());
                        if (r is Map && r['message'] != null && r['ok'] != true) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(r['message'].toString()), backgroundColor: Colors.red),
                            );
                          }
                          return;
                        }
                        if (context.mounted) Navigator.pop(context, true);
                        final value = (r is Map) ? _num(r['value']) : 0.0;
                        _snack('${tr('Vozvrat qilindi')}: ${_money(value)} ${tr('so\'m')}');
                      } on ApiException catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e.message), backgroundColor: Colors.red),
                          );
                        }
                      } finally {
                        if (context.mounted) setStateDialog(() => saving = false);
                      }
                    },
              child: Text(tr('Vozvrat'), style: TextStyle(color: AppTheme.onAccent)),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Bloklash / blokdan chiqarish ───
  Future<bool?> _blockDialog(Map<String, dynamic> lot) {
    final toBlock = lot['status'] != 'blocked';
    final reasonController = TextEditingController();
    bool saving = false;
    final title = toBlock ? tr('Bloklash') : tr('Blokdan chiqarish');
    return showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text('${lot['lot_code'] ?? ''} — $title', style: TextStyle(color: AppTheme.text)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(
                toBlock ? tr('Partiya bloklanadi — sarf qilinmaydi') : tr('Partiya yana ishlatiladi'),
                style: TextStyle(color: AppTheme.textSoft, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                style: TextStyle(color: AppTheme.text),
                decoration: _dec(tr('Sabab'), Icons.help_outline),
              ),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: toBlock ? Colors.orange : Colors.green),
              onPressed: saving
                  ? null
                  : () async {
                      setStateDialog(() => saving = true);
                      try {
                        final r = await ApiService.post('/stock/lots/${lot['id']}/block', {
                          'blocked': toBlock,
                          'reason': reasonController.text.trim(),
                        }, idempotencyKey: ApiService.newIdempotencyKey());
                        if (r is Map && r['message'] != null && r['ok'] != true) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(r['message'].toString()), backgroundColor: Colors.red),
                            );
                          }
                          return;
                        }
                        if (context.mounted) Navigator.pop(context, true);
                        _snack(tr('Saqlandi'));
                      } on ApiException catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(e.message), backgroundColor: Colors.red),
                          );
                        }
                      } finally {
                        if (context.mounted) setStateDialog(() => saving = false);
                      }
                    },
              child: Text(title, style: TextStyle(color: AppTheme.onAccent)),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════ 1. Partiyalar ro'yxati ═══════════════

class LotsPage extends StatefulWidget {
  const LotsPage({super.key, this.ingredientId, this.ingredientName});

  /// Berilsa — faqat shu mahsulotning partiyalari ko'rsatiladi.
  final int? ingredientId;
  final String? ingredientName;

  @override
  State<LotsPage> createState() => _LotsPageState();
}

class _LotsPageState extends State<LotsPage> with _LotActions<LotsPage> {
  List<dynamic> _lots = [];
  bool _isLoading = true;
  String? _error;
  String _filter = 'all'; // all|active|debt|remaining|blocked|depleted

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Future<void> _reloadAfterAction() => _load();

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // BARCHA partiyalarni yuklaymiz — filtr chiplar mijoz tomonida saralaydi
      var q = '/stock/lots?limit=500';
      if (widget.ingredientId != null) q += '&ingredient_id=${widget.ingredientId}';
      final r = await ApiService.get(q);
      if (!mounted) return;
      setState(() {
        _lots = r is List ? r : [];
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    }
  }

  List<dynamic> get _filtered {
    switch (_filter) {
      case 'active':
        return _lots.where((l) => l['status'] == 'active').toList();
      case 'debt':
        return _lots.where((l) => _num(l['debt_amount']) > 0).toList();
      case 'remaining':
        return _lots.where((l) => _num(l['remaining_quantity']) > 0).toList();
      case 'blocked':
        return _lots.where((l) => l['status'] == 'blocked').toList();
      case 'depleted':
        return _lots.where((l) => l['status'] == 'depleted').toList();
      default:
        return _lots;
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
          title: Text(
            widget.ingredientName != null
                ? '${tr('Partiyalar')} — ${widget.ingredientName}'
                : tr('Partiyalar'),
            style: TextStyle(color: AppTheme.text, fontSize: 17),
          ),
          actions: [
            IconButton(icon: Icon(Icons.refresh, color: AppTheme.text), onPressed: _load),
          ],
        ),
        body: _isLoading
            ? Center(child: CircularProgressIndicator(color: AppTheme.accent))
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('${tr('Xato')}: $_error', style: const TextStyle(color: Colors.red)),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
                      children: [
                        _filterBar(),
                        const SizedBox(height: 12),
                        if (_filtered.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 40),
                            child: Center(
                              child: Text(tr('Ma\'lumot yo\'q'), style: TextStyle(color: AppTheme.textSoft)),
                            ),
                          )
                        else
                          ..._filtered.map((l) => _lotCard(Map<String, dynamic>.from(l as Map))),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _filterBar() {
    Widget chip(String key, String label) {
      final sel = _filter == key;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          onTap: () => setState(() => _filter = key),
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
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        chip('all', tr('Barchasi')),
        chip('active', tr('Aktiv')),
        chip('debt', tr('Qarzdor')),
        chip('remaining', tr('Qoldiqli')),
        chip('blocked', tr('Bloklangan')),
        chip('depleted', tr('Tugagan')),
      ]),
    );
  }

  Widget _lotCard(Map<String, dynamic> lot) {
    final unit = (lot['unit'] ?? lot['ingredient_unit'] ?? '').toString();
    final remaining = _num(lot['remaining_quantity']);
    final debt = _num(lot['debt_amount']);
    final expiry = lot['expiry_date']?.toString();
    final expColor = _expiryColor(expiry);
    final id = int.tryParse(lot['id'].toString()) ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: id > 0 ? () => _showLotDetail(id) : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text('${lot['lot_code'] ?? ''}',
                    style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 14),
                    overflow: TextOverflow.ellipsis),
              ),
              _statusBadge(lot['status']?.toString()),
              if (debt > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
                  ),
                  child: Text('${tr('Qarz')}: ${_money(debt)}',
                      style: const TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ]),
            if (widget.ingredientId == null && lot['ingredient_name'] != null) ...[
              const SizedBox(height: 4),
              Text(lot['ingredient_name'].toString(),
                  style: TextStyle(color: AppTheme.text, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
            const SizedBox(height: 6),
            Wrap(spacing: 12, runSpacing: 4, children: [
              if (lot['supplier_name'] != null)
                _iconText(Icons.local_shipping, lot['supplier_name'].toString()),
              if ((lot['invoice_no'] ?? '').toString().isNotEmpty)
                _iconText(Icons.receipt_long, lot['invoice_no'].toString()),
              _iconText(Icons.event, _d(lot['received_at'])),
              if ((expiry ?? '').isNotEmpty)
                _iconText(Icons.hourglass_bottom, '${tr('Srok')}: ${_d(expiry)}', color: expColor),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: Text('${tr('Qoldiq')}: ${_qty(remaining)} / ${_qty(lot['quantity'])} $unit',
                    style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
              ),
              Text('${_money(lot['unit_cost'])} ${tr('so\'m')}${unit.isNotEmpty ? '/$unit' : ''}',
                  style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
              const SizedBox(width: 10),
              Text('${_money(lot['total_cost'])} ${tr('so\'m')}',
                  style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 13)),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════ 2. Srok nazorati ═══════════════

class ExpiryPage extends StatefulWidget {
  const ExpiryPage({super.key});

  @override
  State<ExpiryPage> createState() => _ExpiryPageState();
}

class _ExpiryPageState extends State<ExpiryPage> with _LotActions<ExpiryPage> {
  int _days = 5;
  Map<String, dynamic>? _data;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Future<void> _reloadAfterAction() => _load();

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final r = await ApiService.get('/stock/expiry?days=$_days');
      if (!mounted) return;
      setState(() {
        _data = r is Map ? Map<String, dynamic>.from(r) : null;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
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
          title: Text(tr('Srok nazorati'), style: TextStyle(color: AppTheme.text, fontSize: 17)),
          actions: [
            IconButton(icon: Icon(Icons.refresh, color: AppTheme.text), onPressed: _load),
          ],
        ),
        body: _isLoading
            ? Center(child: CircularProgressIndicator(color: AppTheme.accent))
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('${tr('Xato')}: $_error', style: const TextStyle(color: Colors.red)),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
                      children: _body(),
                    ),
                  ),
      ),
    );
  }

  List<Widget> _body() {
    final d = _data;
    if (d == null) {
      return [Center(child: Text(tr('Ma\'lumot yo\'q'), style: TextStyle(color: AppTheme.textSoft)))];
    }
    final expiring = (d['expiring'] as List?) ?? [];
    final expired = (d['expired'] as List?) ?? [];
    final losses = (d['losses_by_month'] as List?) ?? [];
    final expiredCount = _num(d['expired_count']).round();
    final expiredValue = _num(d['expired_value']);
    final lossesTotal = _num(d['losses_total']);

    return [
      _daysBar(),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: _kpiCard(tr('Srok o\'tgan'), '$expiredCount',
              '${_money(expiredValue)} ${tr('so\'m')}', Colors.red, Icons.event_busy),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _kpiCard(tr('Tez tugaydi'), '${expiring.length}',
              '$_days ${tr('kun')}', Colors.orange, Icons.hourglass_bottom),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _kpiCard(tr('Jami yo\'qotish'), _money(lossesTotal), tr('so\'m'), Colors.red,
              Icons.trending_down),
        ),
      ]),
      _sectionTitle(tr('Srok o\'tgan partiyalar'), Colors.red),
      if (expired.isEmpty)
        Text(tr('Yo\'q'), style: TextStyle(color: AppTheme.textSoft, fontSize: 13))
      else
        ...expired.map((l) => _expiryRow(Map<String, dynamic>.from(l as Map), expired: true)),
      _sectionTitle(tr('Muddati tugayapti'), Colors.orange),
      if (expiring.isEmpty)
        Text(tr('Yo\'q'), style: TextStyle(color: AppTheme.textSoft, fontSize: 13))
      else
        ...expiring.map((l) => _expiryRow(Map<String, dynamic>.from(l as Map), expired: false)),
      _sectionTitle(tr('Yo\'qotishlar (12 oy)'), null),
      if (losses.isEmpty)
        Text(tr('Yo\'q'), style: TextStyle(color: AppTheme.textSoft, fontSize: 13))
      else
        ..._lossBars(losses),
    ];
  }

  Widget _daysBar() {
    Widget chip(int n) {
      final sel = _days == n;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          onTap: () {
            setState(() => _days = n);
            _load();
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? AppTheme.accent : AppTheme.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: sel ? AppTheme.accent : AppTheme.border),
            ),
            child: Text('$n ${tr('kun')}',
                style: TextStyle(
                    color: sel ? AppTheme.onAccent : AppTheme.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 13)),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [chip(3), chip(5), chip(7), chip(14)]),
    );
  }

  Widget _kpiCard(String label, String value, String sub, Color color, IconData icon) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label,
                  style: TextStyle(color: AppTheme.textSoft, fontSize: 11),
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18)),
          Text(sub, style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
        ]),
      );

  Widget _sectionTitle(String title, Color? color) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(title,
            style: TextStyle(color: color ?? AppTheme.text, fontWeight: FontWeight.bold, fontSize: 14)),
      );

  /// Kompakt partiya qatori: bosilsa — detal; srok o'tganlarda tez "Spisaniya" tugmasi.
  Widget _expiryRow(Map<String, dynamic> lot, {required bool expired}) {
    final unit = (lot['unit'] ?? lot['ingredient_unit'] ?? '').toString();
    final remaining = _num(lot['remaining_quantity']);
    final expiry = lot['expiry_date']?.toString();
    final days = _daysLeft(expiry);
    final id = int.tryParse(lot['id'].toString()) ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: id > 0 ? () => _showLotDetail(id) : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: (expired ? Colors.red : Colors.orange).withValues(alpha: 0.4)),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${lot['ingredient_name'] ?? ''}',
                    style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  '${lot['lot_code'] ?? ''} • ${_qty(remaining)} $unit • ${_money(lot['remaining_cost'])} ${tr('so\'m')}',
                  style: TextStyle(color: AppTheme.textSoft, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text('${tr('Srok')}: ${_d(expiry)}',
                    style: TextStyle(
                        color: _expiryColor(expiry) ?? AppTheme.textSoft,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
            const SizedBox(width: 8),
            if (expired)
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red,
                  backgroundColor: Colors.red.withValues(alpha: 0.1),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                onPressed: () async {
                  final ok = await _writeoffDialog(lot);
                  if (ok == true) _load();
                },
                child: Text(tr('Spisaniya'), style: const TextStyle(fontSize: 12)),
              )
            else if (days != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('$days ${tr('kun')}',
                    style: const TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
          ]),
        ),
      ),
    );
  }

  /// Oylik yo'qotishlar — oddiy gorizontal chiziqlar (kutubxonasiz).
  List<Widget> _lossBars(List<dynamic> losses) {
    final byMonth = <String, double>{};
    for (final m in losses) {
      final k = (m['month'] ?? '').toString();
      if (k.isEmpty) continue;
      byMonth[k] = (byMonth[k] ?? 0) + _num(m['value']);
    }
    final keys = byMonth.keys.toList()..sort();
    double maxV = 0;
    for (final k in keys) {
      if (byMonth[k]! > maxV) maxV = byMonth[k]!;
    }
    if (maxV <= 0) maxV = 1;

    return keys
        .map((k) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                SizedBox(width: 62, child: Text(k, style: TextStyle(color: AppTheme.textSoft, fontSize: 11))),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(children: [
                      Container(height: 14, color: AppTheme.bg),
                      FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: (byMonth[k]! / maxV).clamp(0.0, 1.0),
                        child: Container(height: 14, color: Colors.red.withValues(alpha: 0.75)),
                      ),
                    ]),
                  ),
                ),
                SizedBox(
                  width: 92,
                  child: Text(_money(byMonth[k]),
                      textAlign: TextAlign.right,
                      style: TextStyle(color: AppTheme.text, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ]),
            ))
        .toList();
  }
}

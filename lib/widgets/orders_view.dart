import 'package:flutter/material.dart';
import '../core/api_service.dart';
import '../core/constants.dart';
import '../core/app_theme.dart';
import '../core/lang.dart';

/// Zakazlar ko'rinishi — ham admin, ham ofitsant oynasida ishlatiladi.
/// Tugallanmagan (stol bo'yicha) / Tugallangan (ofitsant bo'yicha) tablari.
/// [canComplete] true bo'lsa "Tugatish (To'landi)" tugmasi ko'rinadi (kassir/admin).
class OrdersView extends StatefulWidget {
  final bool canComplete;
  final String? title;
  const OrdersView({super.key, this.canComplete = false, this.title});

  @override
  State<OrdersView> createState() => _OrdersViewState();
}

class _OrdersViewState extends State<OrdersView> {
  List<dynamic> _orders = [];      // tugallanmagan
  List<dynamic> _paidOrders = [];  // tugallangan (bugun)
  int _orderTab = 0;
  int? _expandedUnpaidId;
  String? _expandedWaiter;
  bool _loading = true;
  bool _mutating = false; // pul operatsiyasi ketmoqda — ikki marta bosishdan himoya
  // Kassa kuni 02:30 da yopiladi — "biznes bugun" = (hozir - 2:30) sanasi.
  // Yarim tundan keyin (00:00-02:30) ochilganda ham kechagi kun ko'rsatiladi.
  static DateTime get _bizNow => DateTime.now().subtract(const Duration(hours: 2, minutes: 30));
  DateTime _selectedDate = _bizNow;

  String get _dateStr =>
      '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
  bool get _isToday {
    final n = _bizNow;
    return _selectedDate.year == n.year && _selectedDate.month == n.month && _selectedDate.day == n.day;
  }

  // ─── Mavzu ranglari (global AppTheme) ───
  Color get _card => AppTheme.card;
  Color get _accent => AppTheme.accent;
  Color get _accentLight => AppTheme.accentSoft;
  Color get _text => AppTheme.text;
  Color get _textSoft => AppTheme.textSoft;
  Color get _cardBorder => AppTheme.border;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.get(AppConstants.orders),
        ApiService.get('${AppConstants.orders}?status=paid&date=$_dateStr'),
      ]);
      if (!mounted) return;
      setState(() {
        _orders = results[0] is List ? results[0] : [];
        _paidOrders = results[1] is List ? results[1] : [];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Hisob/chek chiqarish (print-agent chop etadi) — aktiv zakazda "Hisob", tugallanganda qayta chek
  Future<void> _printBill(int orderId) async {
    try {
      final res = await ApiService.post('${AppConstants.orders}/$orderId/bill', {});
      if (!mounted) return;
      final ok = !(res is Map && res['message'] != null && res['ok'] != true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok ? tr('Chek chiqarilmoqda...') : res['message'].toString()),
        backgroundColor: ok ? Colors.teal : Colors.red,
        duration: const Duration(milliseconds: 1500),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
      }
    }
  }

  // Tugallangan zakazlar uchun sana tanlash
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 400)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _load();
    }
  }

  Future<void> _updateStatus(int orderId, String status, [Map<String, dynamic>? extra]) async {
    if (_mutating) return; // so'rov ketayotganda takror bosish ishlamaydi
    setState(() => _mutating = true);
    try {
      // Idempotency-Key — tarmoq uzilib retry bo'lsa ham to'lov ikki marta o'tmaydi
      final res = await ApiService.put(
          '${AppConstants.orders}/$orderId/status', {'status': status, ...?extra},
          idempotencyKey: ApiService.newIdempotencyKey());
      // 409 — masalan "Zakaz allaqachon to'langan": faqat message keladi (zakaz maydonlari yo'q)
      if (res is Map && res['id'] == null && res['ok'] != true && res['message'] != null) {
        if (mounted) {
          // Server summani jonli order_items'dan qayta hisoblaydi. To'lov dialogi eskirgan
          // snapshot'dan hisoblab yuborsa (dialog ochilgach taom qo'shilgan/o'chirilgan)
          // 400 "...teng emas" keladi — kassirga aniq ko'rsatamiz, keyingi _load ro'yxatni yangilaydi.
          final msg = res['message'].toString();
          final stale = msg.contains('teng emas');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(stale
                  ? tr('Zakaz o\'zgardi (taom qo\'shilgan/o\'chirilgan). Ro\'yxat yangilandi — to\'lovni qaytadan oching.')
                  : msg),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _confirmComplete(Map<String, dynamic> order) async {
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _PaymentDialog(order: order),
    );
    if (payload != null) await _updateStatus(order['id'] as int, 'paid', payload);
  }

  Widget _orderTabChip(String label, int tab, int count) {
    final selected = _orderTab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _orderTab = tab),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? _accent : _card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? _accent : _cardBorder),
          ),
          child: Text(
            '$label ($count)',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : _textSoft,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyOrders(String msg) {
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(Icons.receipt_long, color: _textSoft.withValues(alpha: 0.5), size: 64),
        const SizedBox(height: 12),
        Text(msg, textAlign: TextAlign.center, style: TextStyle(color: _textSoft, fontSize: 16)),
      ],
    );
  }

  Widget _orderItems(List itemList, {int? orderId, bool canCancel = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: itemList.map<Widget>((oi) {
        if (oi == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(
            children: [
              Icon(Icons.fiber_manual_record, color: _textSoft, size: 8),
              const SizedBox(width: 6),
              Expanded(
                child: Text(oi['name']?.toString() ?? '',
                    style: TextStyle(color: _text.withValues(alpha: 0.85), fontSize: 13)),
              ),
              Text('x${oi['quantity']}', style: TextStyle(color: _textSoft, fontSize: 12)),
              if (canCancel && orderId != null && oi['id'] != null) ...[
                const SizedBox(width: 4),
                InkWell(
                  onTap: () => _cancelItem(orderId, oi['id'] as int, oi['name']?.toString() ?? '',
                      num.tryParse(oi['quantity']?.toString() ?? '1') ?? 1),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(Icons.cancel, color: Colors.red.withValues(alpha: 0.7), size: 18),
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  // Bitta taomni bekor qilish (to'lanmagan zakazda).
  // qtyHave > 1 bo'lsa — nechtasini bekor qilishni tanlash mumkin (masalan 5 tadan 2 tasi).
  Future<void> _cancelItem(int orderId, int itemId, String name, num qtyHave) async {
    final total = qtyHave.toInt();
    int? chosen;
    if (total <= 1) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: _card,
          title: Text(tr('Taomni bekor qilish'), style: TextStyle(color: _text)),
          content: Text('"$name" — ${tr('shu taomni zakazdan o\'chirasizmi?')}',
              style: TextStyle(color: _textSoft)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false),
                child: Text(tr('Yo\'q'), style: TextStyle(color: _textSoft))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('Ha, bekor qil'), style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (ok != true) return;
      chosen = total;
    } else {
      int sel = 1; // nechtasini bekor qilamiz (default 1)
      chosen = await showDialog<int>(
        context: context,
        builder: (_) => StatefulBuilder(
          builder: (ctx, setSt) => AlertDialog(
            backgroundColor: _card,
            title: Text('"$name"', style: TextStyle(color: _text, fontSize: 16)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${tr('Zakazda')}: $total. ${tr('Nechtasini bekor qilamiz?')}',
                  style: TextStyle(color: _textSoft, fontSize: 13)),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _stepBtn(Icons.remove, () { if (sel > 1) setSt(() => sel--); }),
                SizedBox(
                  width: 72,
                  child: Text('$sel', textAlign: TextAlign.center,
                      style: TextStyle(color: _text, fontSize: 28, fontWeight: FontWeight.bold)),
                ),
                _stepBtn(Icons.add, () { if (sel < total) setSt(() => sel++); }),
              ]),
              const SizedBox(height: 10),
              Text(sel >= total ? tr('Butun taom o\'chiriladi') : '${tr('Qoladi')}: ${total - sel}',
                  style: TextStyle(color: _textSoft, fontSize: 12)),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx),
                  child: Text(tr('Yo\'q'), style: TextStyle(color: _textSoft))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(ctx, sel),
                child: Text('$sel ${tr('ta bekor qil')}', style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      );
      if (chosen == null) return;
    }

    // chosen == total -> butun taom (qty parametrsiz); aks holda qisman (?qty=N)
    final full = chosen >= total;
    final url = '${AppConstants.orders}/$orderId/items/$itemId${full ? '' : '?qty=$chosen'}';
    try {
      final res = await ApiService.delete(url);
      if (res is Map && res['ok'] != true && res['message'] != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'].toString()), backgroundColor: Colors.red));
        }
        return;
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Widget _stepBtn(IconData ic, VoidCallback onTap) => Material(
        color: _cardBorder,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(padding: const EdgeInsets.all(10), child: Icon(ic, color: _text, size: 22)),
        ),
      );

  // Maqsad stolni tanlash dialogi (ko'chirish uchun umumiy). Tanlangan table id qaytaradi.
  Future<int?> _pickTargetTable(dynamic currentTableId, {String? title}) async {
    List<dynamic> tables = [];
    try {
      final r = await ApiService.get(AppConstants.tables);
      tables = r is List ? r : [];
    } catch (_) {}
    if (!mounted) return null;
    return showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        title: Text(title ?? tr('Stolni ko\'chirish / birlashtirish'), style: TextStyle(color: _text, fontSize: 16)),
        content: SizedBox(
          width: 340,
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: tables.where((t) => t['id'] != currentTableId).map<Widget>((t) {
                final occupied = t['status']?.toString() == 'occupied';
                final label = t['number']?.toString() ?? t['name']?.toString() ?? '?';
                return InkWell(
                  onTap: () => Navigator.pop(context, t['id'] as int),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: 96,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: (occupied ? Colors.orange : Colors.green).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: occupied ? Colors.orange : Colors.green),
                    ),
                    child: Column(children: [
                      Icon(Icons.table_restaurant, color: occupied ? Colors.orange : Colors.green),
                      const SizedBox(height: 4),
                      Text(label, style: TextStyle(color: _text, fontWeight: FontWeight.bold)),
                      Text(occupied ? tr('birlashadi') : tr('bo\'sh'),
                          style: TextStyle(color: occupied ? Colors.orange : Colors.green, fontSize: 11)),
                    ]),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Bekor'), style: TextStyle(color: _textSoft))),
        ],
      ),
    );
  }

  // Zakazni BUTUNLIGICHA boshqa stolga ko'chirish / birlashtirish
  Future<void> _moveOrder(Map order) async {
    if (_mutating) return;
    final picked = await _pickTargetTable(order['table_id']);
    if (picked == null) return;
    setState(() => _mutating = true);
    try {
      final res = await ApiService.put('${AppConstants.orders}/${order['id']}/move', {'table_id': picked},
          idempotencyKey: ApiService.newIdempotencyKey());
      if (!mounted) return;
      if (res is Map && res['ok'] != true && res['message'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'].toString()), backgroundColor: Colors.red));
      } else {
        final merged = res is Map && res['merged'] == true;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(merged ? tr('Stollar birlashtirildi') : tr('Zakaz ko\'chirildi')),
            backgroundColor: Colors.green));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  // Zakazni QISMAN ko'chirish: taomlarni tanlab, har biridan nechtadan ko'chirishni belgilaydi.
  Future<void> _moveOrderItems(Map order) async {
    if (_mutating) return;
    final items = (order['items'] is List ? order['items'] as List : [])
        .where((oi) => oi != null && oi['id'] != null && ((num.tryParse(oi['quantity']?.toString() ?? '0') ?? 0) > 0))
        .toList();
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Ko\'chiriladigan taom yo\'q')), backgroundColor: Colors.orange));
      return;
    }
    // order_item id -> ko'chiriladigan miqdor
    final Map<int, int> sel = {for (final oi in items) oi['id'] as int: 0};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) {
          int chosenCount() => sel.values.fold(0, (a, b) => a + b);
          return AlertDialog(
            backgroundColor: _card,
            title: Text(tr('Qaysi taomni ko\'chiramiz?'), style: TextStyle(color: _text, fontSize: 16)),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: items.map<Widget>((oi) {
                    final id = oi['id'] as int;
                    final have = (num.tryParse(oi['quantity']?.toString() ?? '0') ?? 0).toInt();
                    final cur = sel[id] ?? 0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('${oi['name'] ?? ''}  ·  ${tr('bor')}: $have',
                                style: TextStyle(color: _text, fontSize: 13)),
                          ),
                          _moveStep(Icons.remove, cur > 0 ? () => setSt(() => sel[id] = cur - 1) : null),
                          SizedBox(
                            width: 28,
                            child: Text('$cur',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: _accent, fontWeight: FontWeight.bold, fontSize: 15)),
                          ),
                          _moveStep(Icons.add, cur < have ? () => setSt(() => sel[id] = cur + 1) : null),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false),
                  child: Text(tr('Bekor'), style: TextStyle(color: _textSoft))),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _accent),
                onPressed: chosenCount() > 0 ? () => Navigator.pop(ctx, true) : null,
                child: Text('${tr('Davom')} (${chosenCount()})', style: const TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true) return;
    final payload = sel.entries.where((e) => e.value > 0)
        .map((e) => {'order_item_id': e.key, 'quantity': e.value}).toList();
    if (payload.isEmpty) return;
    // Hammasini tanlagan bo'lsa — butun ko'chirish bilan bir xil, lekin move-items ham to'g'ri ishlaydi.
    if (!mounted) return;
    final picked = await _pickTargetTable(order['table_id'], title: tr('Qaysi stolga ko\'chiramiz?'));
    if (picked == null) return;
    setState(() => _mutating = true);
    try {
      final res = await ApiService.put('${AppConstants.orders}/${order['id']}/move-items',
          {'table_id': picked, 'items': payload}, idempotencyKey: ApiService.newIdempotencyKey());
      if (!mounted) return;
      if (res is Map && res['ok'] != true && res['message'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'].toString()), backgroundColor: Colors.red));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr('Taomlar ko\'chirildi')), backgroundColor: Colors.green));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  // Kichik +/- tugma (qisman ko'chirish stepperi uchun; null = o'chirilgan)
  Widget _moveStep(IconData ic, VoidCallback? onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: (onTap == null ? _textSoft : _accent).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(ic, size: 18, color: onTap == null ? _textSoft : _accent),
        ),
      );

  // To'langan zakazni QAYTA OCHISH — noto'g'ri to'lovni tuzatish uchun
  Future<void> _reopenOrder(Map o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        title: Text(tr('Zakazni qayta ochish'), style: TextStyle(color: _text)),
        content: Text(
            '#${o['id']} — ${tr('to\'lovni bekor qilib qayta ochamizmi? Kassa, sklad va qarz qaytariladi, keyin tahrirlab qayta to\'lash mumkin.')}',
            style: TextStyle(color: _textSoft)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Yo\'q'), style: TextStyle(color: _textSoft))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Ha, qayta och'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true || _mutating) return;
    setState(() => _mutating = true);
    try {
      final res = await ApiService.put('${AppConstants.orders}/${o['id']}/reopen', {},
          idempotencyKey: ApiService.newIdempotencyKey());
      if (!mounted) return;
      if (res is Map && res['ok'] != true && res['message'] != null) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'].toString()), backgroundColor: Colors.red));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr('Zakaz qayta ochildi')), backgroundColor: Colors.green));
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  // Butun zakazni o'chirish (to'langan bo'lsa pul/kassa/sklad ham qaytariladi)
  Future<void> _deleteOrder(Map order) async {
    final isPaid = order['status']?.toString() == 'paid';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card,
        title: Text(tr('Zakazni o\'chirish'), style: TextStyle(color: _text)),
        content: Text(
          isPaid
              ? '#${order['id']} — ${tr('zakazni o\'chirasizmi? Savdo va kassadan ham ayriladi, sklad qaytariladi.')}'
              : '#${order['id']} — ${tr('zakazni butunlay o\'chirasizmi?')}',
          style: TextStyle(color: _textSoft),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Yo\'q'), style: TextStyle(color: _textSoft))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Ha, o\'chir'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (_mutating) return; // so'rov ketayotganda takror bosish ishlamaydi
    setState(() => _mutating = true);
    try {
      // Idempotency-Key — to'langan zakaz o'chirilganda pul qaytadi, takror so'rov xavfli
      final res = await ApiService.delete('${AppConstants.orders}/${order['id']}',
          idempotencyKey: ApiService.newIdempotencyKey());
      if (res is Map && res['ok'] != true && res['message'] != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'].toString()), backgroundColor: Colors.red));
        }
        return;
      }
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  // Tugallangan zakaz to'lov tafsiloti (karta/naqd/qarz + chegirma)
  Widget _payInfo(Map o) {
    final disc = double.tryParse(o['discount_percent']?.toString() ?? '0') ?? 0;
    final card = double.tryParse(o['paid_card']?.toString() ?? '0') ?? 0;
    final cash = double.tryParse(o['paid_cash']?.toString() ?? '0') ?? 0;
    final debt = double.tryParse(o['paid_debt']?.toString() ?? '0') ?? 0;
    final reason = o['discount_reason']?.toString() ?? '';
    final debtor = o['debtor_name']?.toString() ?? '';

    Widget chip(IconData ic, String t, Color c) => Container(
          margin: const EdgeInsets.only(right: 6, top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(ic, size: 12, color: c),
            const SizedBox(width: 4),
            Text(t, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w600)),
          ]),
        );

    final chips = <Widget>[];
    if (card > 0) chips.add(chip(Icons.credit_card, '${tr('Karta')}: ${card.toStringAsFixed(0)}', Colors.blue));
    if (cash > 0) chips.add(chip(Icons.payments, '${tr('Naqd')}: ${cash.toStringAsFixed(0)}', Colors.green));
    if (debt > 0) {
      chips.add(chip(Icons.account_balance_wallet,
          '${tr('Qarz')}: ${debt.toStringAsFixed(0)}${debtor.isNotEmpty ? ' ($debtor)' : ''}', Colors.deepOrange));
    }
    if (chips.isEmpty && disc <= 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (disc > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '${tr('Chegirma')}: ${disc == disc.truncateToDouble() ? disc.toInt() : disc}%${reason.isNotEmpty ? ' — $reason' : ''}',
              style: const TextStyle(color: Colors.purple, fontSize: 11),
            ),
          ),
        if (chips.isNotEmpty) Wrap(children: chips),
      ],
    );
  }

  Widget _statusBtn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }

  // TUGALLANMAGAN — stol bo'yicha
  Widget _buildUnpaidList() {
    if (_orders.isEmpty) return _emptyOrders(tr('Tugallanmagan zakaz yo\'q'));
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _orders.length,
      itemBuilder: (_, i) {
        final order = _orders[i];
        final id = order['id'] as int;
        final tableNum = order['table_number'] ?? order['table_name'] ?? '?';
        final total = double.tryParse(order['total_amount']?.toString() ?? '0') ?? 0;
        final itemList = order['items'] is List ? order['items'] as List : [];
        final expanded = _expandedUnpaidId == id;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _accent.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _expandedUnpaidId = expanded ? null : id),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Text('#$id', style: TextStyle(color: _textSoft, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('${tr('Stol')} $tableNum',
                            style: TextStyle(color: _accent, fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                      const SizedBox(width: 8),
                      Text('${itemList.length} ${tr('taom')}', style: TextStyle(color: _textSoft, fontSize: 12)),
                      const Spacer(),
                      Text('${total.toStringAsFixed(0)} сом',
                          style: TextStyle(color: _text, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(width: 6),
                      Icon(expanded ? Icons.expand_less : Icons.expand_more, color: _textSoft),
                    ],
                  ),
                ),
              ),
              if (expanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Divider(color: _textSoft.withValues(alpha: 0.3), height: 1),
                      const SizedBox(height: 8),
                      _orderItems(itemList, orderId: id, canCancel: widget.canComplete),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          // ↔ Stolni ko'chirish/birlashtirish — HAMMA (o'z zakazini)
                          _statusBtn(tr('↔ Ko\'chirish'), Colors.deepPurple, () => _moveOrder(order)),
                          // ⇢ Qisman ko'chirish — tanlangan taomlar/miqdor
                          if (itemList.isNotEmpty)
                            _statusBtn(tr('⇢ Qisman'), Colors.indigo, () => _moveOrderItems(order)),
                          // 🧾 Счёт (pri-chek) — HAMMA (oddiy ofitsant ham) chiqara oladi
                          _statusBtn(tr('🧾 Hisob (Счёт)'), Colors.blue, () => _printBill(order['id'] as int)),
                          // O'chirish + Tugatish (to'lov) — FAQAT kassir/admin
                          if (widget.canComplete) ...[
                            _statusBtn(tr('O\'chirish'), Colors.red, () => _deleteOrder(order)),
                            _statusBtn(tr('✓ Tugatish (To\'landi)'), Colors.teal, () => _confirmComplete(order)),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // TUGALLANGAN — ofitsant bo'yicha
  Widget _buildPaidList() {
    if (_paidOrders.isEmpty) return _emptyOrders(tr('Tugallangan zakaz yo\'q'));
    final Map<String, List<dynamic>> byWaiter = {};
    for (final o in _paidOrders) {
      final w = (o['waiter_name'] ?? tr('Noma\'lum')).toString();
      byWaiter.putIfAbsent(w, () => []).add(o);
    }
    final waiters = byWaiter.keys.toList();
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: waiters.length,
      itemBuilder: (_, i) {
        final w = waiters[i];
        final orders = byWaiter[w]!;
        final sum = orders.fold<double>(
            0, (s, o) => s + (double.tryParse(o['total_amount']?.toString() ?? '0') ?? 0));
        final expanded = _expandedWaiter == w;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.teal.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => _expandedWaiter = expanded ? null : w),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.teal.withValues(alpha: 0.2),
                        child: Text(w.isNotEmpty ? w[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(w, style: TextStyle(color: _text, fontWeight: FontWeight.bold, fontSize: 15)),
                            Text('${orders.length} ${tr('ta zakaz')}', style: TextStyle(color: _textSoft, fontSize: 12)),
                          ],
                        ),
                      ),
                      Text('${sum.toStringAsFixed(0)} сом',
                          style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(width: 6),
                      Icon(expanded ? Icons.expand_less : Icons.expand_more, color: _textSoft),
                    ],
                  ),
                ),
              ),
              if (expanded)
                ...orders.map((o) {
                  final tableNum = o['table_number'] ?? o['table_name'] ?? '?';
                  final total = double.tryParse(o['total_amount']?.toString() ?? '0') ?? 0;
                  final itemList = o['items'] is List ? o['items'] as List : [];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _accentLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('#${o['id']}  ', style: TextStyle(color: _textSoft, fontWeight: FontWeight.bold, fontSize: 13)),
                              Text('${tr('Stol')} $tableNum',
                                  style: TextStyle(color: _accent, fontWeight: FontWeight.bold, fontSize: 13)),
                              const Spacer(),
                              Text('${total.toStringAsFixed(0)} сом',
                                  style: TextStyle(color: _text, fontWeight: FontWeight.bold, fontSize: 13)),
                              if (widget.canComplete) ...[
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: () => _printBill(o['id'] as int),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Icon(Icons.print, color: _accent, size: 18),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: () => _reopenOrder(o),
                                  borderRadius: BorderRadius.circular(12),
                                  child: const Icon(Icons.lock_open, color: Colors.orange, size: 18),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: () => _deleteOrder(o),
                                  borderRadius: BorderRadius.circular(12),
                                  child: Icon(Icons.delete_outline,
                                      color: Colors.red.withValues(alpha: 0.75), size: 18),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 6),
                          _orderItems(itemList),
                          _payInfo(o),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([AppTheme.instance, Lang.instance]),
      builder: (context, _) => _content(),
    );
  }

  Widget _content() {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: _accent));
    }
    return Column(
      children: [
        // Sarlavha + yangilash
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              if (widget.title != null)
                Text(widget.title!,
                    style: TextStyle(color: _text, fontSize: 22, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.refresh, color: _textSoft),
                onPressed: _load,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Row(
            children: [
              _orderTabChip(tr('Tugallanmagan'), 0, _orders.length),
              const SizedBox(width: 8),
              _orderTabChip(tr('Tugallangan'), 1, _paidOrders.length),
            ],
          ),
        ),
        if (_orderTab == 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(children: [
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _accent.withValues(alpha: 0.4)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.calendar_today, color: _accent, size: 15),
                    const SizedBox(width: 8),
                    Text(_isToday ? tr('Bugun') : _dateStr,
                        style: TextStyle(color: _text, fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_drop_down, color: _textSoft, size: 18),
                  ]),
                ),
              ),
              if (!_isToday) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    setState(() => _selectedDate = _bizNow);
                    _load();
                  },
                  child: Text(tr('Bugunga'), style: TextStyle(color: _accent)),
                ),
              ],
            ]),
          ),
        Expanded(
          child: RefreshIndicator(
            color: _accent,
            onRefresh: _load,
            child: _orderTab == 0 ? _buildUnpaidList() : _buildPaidList(),
          ),
        ),
      ],
    );
  }
}

// Zakaz yopish — to'lov dialogi (chegirma + karta/naqd/qarz bo'lib to'lash)
class _PaymentDialog extends StatefulWidget {
  final Map<String, dynamic> order;
  const _PaymentDialog({required this.order});
  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _discCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _cardCtrl = TextEditingController();
  final _debtCtrl = TextEditingController();
  final _debtorCtrl = TextEditingController();
  final _givenCashCtrl = TextEditingController(); // kassir uchun: mijoz bergan naqd (faqat qaytim ko'rsatgichi)

  double get _subtotal => double.tryParse(widget.order['total_amount']?.toString() ?? '0') ?? 0;

  double _n(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(' ', '').replaceAll(',', '.')) ?? 0;

  double get _discPct {
    final v = _n(_discCtrl);
    return v < 0 ? 0 : (v > 100 ? 100 : v);
  }
  double get _finalAmount => (_subtotal * (100 - _discPct) / 100).roundToDouble();
  double get _card => _n(_cardCtrl);
  double get _debt => _n(_debtCtrl);
  double get _cash => _finalAmount - _card - _debt; // qoldiq = naqd
  bool get _over => (_card + _debt) > _finalAmount + 0.5;
  bool get _valid => !_over && (_debt <= 0 || _debtorCtrl.text.trim().isNotEmpty);

  String _money(num v) {
    final s = v.toStringAsFixed(0);
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return b.toString();
  }

  @override
  void dispose() {
    _discCtrl.dispose();
    _reasonCtrl.dispose();
    _cardCtrl.dispose();
    _debtCtrl.dispose();
    _debtorCtrl.dispose();
    _givenCashCtrl.dispose();
    super.dispose();
  }

  InputDecoration _dec(String label, {String? suffix}) => InputDecoration(
        labelText: label,
        suffixText: suffix,
        isDense: true,
        labelStyle: TextStyle(color: AppTheme.textSoft, fontSize: 13),
        suffixStyle: TextStyle(color: AppTheme.textSoft),
        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.accent)),
      );

  @override
  Widget build(BuildContext context) {
    final items = widget.order['items'] is List ? widget.order['items'] as List : [];
    final cash = _cash < 0 ? 0.0 : _cash;

    return AlertDialog(
      backgroundColor: AppTheme.card,
      title: Text('${tr('To\'lov')}  •  #${widget.order['id']}', style: TextStyle(color: AppTheme.text)),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...items.where((e) => e != null).map((oi) {
                final qty = num.tryParse(oi['quantity'].toString()) ?? 1;
                final price = double.tryParse(oi['price']?.toString() ?? '0') ?? 0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(children: [
                    Expanded(child: Text(oi['name']?.toString() ?? '', style: TextStyle(color: AppTheme.text, fontSize: 13))),
                    Text('x$qty  ', style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
                    Text(_money(price * qty), style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
                  ]),
                );
              }),
              Divider(color: AppTheme.border),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(tr('Jami:'), style: TextStyle(color: AppTheme.textSoft, fontSize: 13)),
                Text('${_money(_subtotal)} ${tr('so\'m')}', style: TextStyle(color: AppTheme.textSoft, fontSize: 13)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                SizedBox(
                  width: 92,
                  child: TextField(
                    controller: _discCtrl,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: AppTheme.text),
                    onChanged: (_) => setState(() {}),
                    decoration: _dec(tr('Chegirma'), suffix: '%'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _reasonCtrl,
                    style: TextStyle(color: AppTheme.text),
                    decoration: _dec(tr('Chegirma sababi')),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(tr('Yakuniy'), style: TextStyle(color: AppTheme.text, fontSize: 15, fontWeight: FontWeight.bold)),
                Text('${_money(_finalAmount)} ${tr('so\'m')}',
                    style: TextStyle(color: AppTheme.accent, fontSize: 18, fontWeight: FontWeight.bold)),
              ]),
              Divider(color: AppTheme.border),
              // Tez to'lov: to'liq naqd / to'liq karta (qo'lda kiritmasdan)
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _cardCtrl.clear();
                      _debtCtrl.clear();
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                      ),
                      child: Text(tr('To\'liq naqd'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() {
                      _debtCtrl.clear();
                      _cardCtrl.text = _finalAmount.toStringAsFixed(0);
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.withValues(alpha: 0.4)),
                      ),
                      child: Text(tr('To\'liq karta'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _cardCtrl,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: AppTheme.text),
                    onChanged: (_) => setState(() {}),
                    decoration: _dec(tr('Karta')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _debtCtrl,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(color: AppTheme.text),
                    onChanged: (_) => setState(() {}),
                    decoration: _dec(tr('Qarz')),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: (_over ? Colors.red : Colors.green).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(_over ? tr('Summa oshib ketdi') : tr('Naqd'),
                      style: TextStyle(color: _over ? Colors.red : Colors.green, fontSize: 14, fontWeight: FontWeight.bold)),
                  if (!_over)
                    Text('${_money(cash)} ${tr('so\'m')}',
                        style: const TextStyle(color: Colors.green, fontSize: 15, fontWeight: FontWeight.bold)),
                ]),
              ),
              // sdacha-change: kassir mijoz bergan naqdni kiritsa, ortiqchasi = qaytim.
              // Serverga yuboriladigan split o'zgarmaydi (paid_cash = cash), bu faqat ko'rsatgich.
              if (!_over && cash > 0) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _givenCashCtrl,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(color: AppTheme.text),
                  onChanged: (_) => setState(() {}),
                  decoration: _dec(tr('Berilgan naqd')),
                ),
                if (_n(_givenCashCtrl) > cash) ...[
                  const SizedBox(height: 6),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text(tr('Qaytim'),
                        style: TextStyle(color: AppTheme.text, fontSize: 14, fontWeight: FontWeight.bold)),
                    Text('${_money(_n(_givenCashCtrl) - cash)} ${tr('so\'m')}',
                        style: const TextStyle(color: Colors.orange, fontSize: 15, fontWeight: FontWeight.bold)),
                  ]),
                ],
              ],
              if (_debt > 0) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _debtorCtrl,
                  style: TextStyle(color: AppTheme.text),
                  onChanged: (_) => setState(() {}),
                  decoration: _dec(tr('Mijoz ism-familiyasi')),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
          onPressed: _valid
              ? () => Navigator.pop(context, {
                    'discount_percent': _discPct,
                    'discount_reason': _reasonCtrl.text.trim(),
                    'paid_card': _card,
                    'paid_cash': cash,
                    'paid_debt': _debt,
                    'debtor_name': _debtorCtrl.text.trim(),
                  })
              : null,
          child: Text(tr('Tugatish'), style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

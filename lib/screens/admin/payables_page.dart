import 'package:flutter/material.dart';
import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../../core/lang.dart';

// KREDITORLAR — restoranга qarzга/qisman olingan buyumlar (mebel, dekor, uskuna).
// "Kimga qancha qarzmiz" + tavsif + to'langan/qolgan; qismlаб to'lash.
class PayablesPage extends StatefulWidget {
  const PayablesPage({super.key});
  @override
  State<PayablesPage> createState() => _PayablesPageState();
}

class _PayablesPageState extends State<PayablesPage> {
  bool _loading = true;
  List<dynamic> _items = [];
  num _owed = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  num _n(dynamic v) => v is num ? v : (num.tryParse(v?.toString() ?? '0') ?? 0);
  String _money(num v) {
    final s = v.abs().toStringAsFixed(0);
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return (v < 0 ? '-' : '') + b.toString();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await ApiService.get('/expenses/payables');
      if (mounted) {
        setState(() {
          _items = (r is Map ? r['items'] : null) as List? ?? [];
          _owed = _n(r is Map ? r['total_owed'] : 0);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${tr('Kreditorlar yuklanmadi')}: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Widget _srcMethodRow(BuildContext ctx, StateSetter setSt, String method, bool fromKassa,
      void Function(String) onM, void Function(bool) onK) {
    Widget chip(String label, bool sel, VoidCallback t) => Expanded(
          child: GestureDetector(
            onTap: t,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: sel ? AppTheme.accent.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: sel ? AppTheme.accent : AppTheme.border),
              ),
              child: Text(label,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: sel ? AppTheme.accent : AppTheme.textSoft)),
            ),
          ),
        );
    return Column(children: [
      Row(children: [
        chip(tr('Naqd'), method == 'cash', () => onM('cash')),
        const SizedBox(width: 8),
        chip(tr('Karta'), method == 'card', () => onM('card')),
      ]),
      const SizedBox(height: 8),
      Align(alignment: Alignment.centerLeft, child: Text(tr('Pul manbasi'), style: TextStyle(color: AppTheme.textSoft, fontSize: 12))),
      const SizedBox(height: 4),
      Row(children: [
        chip(tr('Kassadan'), fromKassa, () => onK(true)),
        const SizedBox(width: 8),
        chip(tr('Boshqa joydan'), !fromKassa, () => onK(false)),
      ]),
    ]);
  }

  Future<void> _add() async {
    final nameC = TextEditingController();
    final credC = TextEditingController();
    final descC = TextEditingController();
    final totalC = TextEditingController();
    final paidC = TextEditingController();
    String method = 'cash';
    bool fromKassa = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text(tr('Kreditor qo\'shish'), style: TextStyle(color: AppTheme.text)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _tf(nameC, tr('Nima olindi (masalan: Dekor stul)')),
              _tf(credC, tr('Kimga qarzmiz (ixtiyoriy)')),
              _tf(descC, tr('Izoh (ixtiyoriy)')),
              _tf(totalC, tr('To\'liq qiymati'), num: true),
              _tf(paidC, tr('Hozir to\'landi (ixtiyoriy)'), num: true),
              const SizedBox(height: 8),
              _srcMethodRow(ctx, setSt, method, fromKassa,
                  (m) => setSt(() => method = m), (k) => setSt(() => fromKassa = k)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Saqlash'), style: TextStyle(color: AppTheme.accent))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final total = double.tryParse(totalC.text.trim().replaceAll(' ', '')) ?? 0;
    if (nameC.text.trim().isEmpty || total <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('Nomi va to\'liq qiymatini kiriting')), backgroundColor: Colors.orange));
      }
      return;
    }
    try {
      final r = await ApiService.post('/expenses/payables', {
        'name': nameC.text.trim(),
        'creditor': credC.text.trim().isEmpty ? null : credC.text.trim(),
        'description': descC.text.trim().isEmpty ? null : descC.text.trim(),
        'total_amount': total,
        'paid_now': double.tryParse(paidC.text.trim().replaceAll(' ', '')) ?? 0,
        'method': method,
        'from_kassa': fromKassa,
      }, idempotencyKey: ApiService.newIdempotencyKey());
      if (mounted && r is Map && r['id'] == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r['message']?.toString() ?? tr('Xato')), backgroundColor: Colors.red));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Saqlandi')), backgroundColor: Colors.green));
      }
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _pay(Map item) async {
    final remaining = _n(item['remaining']);
    final amtC = TextEditingController(text: remaining > 0 ? remaining.toStringAsFixed(0) : '');
    String method = 'cash';
    bool fromKassa = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text('${item['name']} — ${tr('To\'lash')}', style: TextStyle(color: AppTheme.text)),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(alignment: Alignment.centerLeft, child: Text('${tr('Qoldiq')}: ${_money(remaining)}', style: TextStyle(color: AppTheme.textSoft, fontSize: 12))),
            _tf(amtC, tr('Summa'), num: true),
            const SizedBox(height: 8),
            _srcMethodRow(ctx, setSt, method, fromKassa,
                (m) => setSt(() => method = m), (k) => setSt(() => fromKassa = k)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('To\'lash'), style: TextStyle(color: Colors.green))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final amt = double.tryParse(amtC.text.trim().replaceAll(' ', '')) ?? 0;
    if (amt <= 0) return;
    // Postavshik qarzi — boshqa endpoint (FIFO partiyalarga taqsimlaydi)
    final isSupplier = item['type'] == 'supplier';
    final path = isSupplier
        ? '/stock/suppliers/${item['id']}/pay'
        : '/expenses/payables/${item['id']}/pay';
    try {
      final r = await ApiService.post(path,
          {'amount': amt, 'method': method, 'from_kassa': fromKassa}, idempotencyKey: ApiService.newIdempotencyKey());
      if (mounted) {
        final okr = r is Map &&
            (r['ok'] == true ||
                (r['message'] != null &&
                    r['message'].toString().toLowerCase().contains('topilmadi') != true &&
                    r['message'].toString().toLowerCase().contains('katta') != true));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text((r is Map ? (r['message'] ?? tr('To\'landi')) : tr('To\'landi')).toString()),
          backgroundColor: okr ? Colors.green : Colors.orange));
      }
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _delete(Map item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('O\'chirish'), style: TextStyle(color: AppTheme.text)),
        content: Text('${item['name']} — ${tr('o\'chirilsinmi?')}', style: TextStyle(color: AppTheme.textSoft)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text(tr('O\'chirish'), style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.delete('/expenses/payables/${item['id']}');
      _load();
    } catch (_) {}
  }

  Widget _tf(TextEditingController c, String label, {bool num = false}) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextField(
          controller: c,
          keyboardType: num ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          style: TextStyle(color: AppTheme.text),
          decoration: InputDecoration(labelText: label, labelStyle: TextStyle(color: AppTheme.textSoft)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.card,
        iconTheme: IconThemeData(color: AppTheme.text),
        title: Text(tr('Kreditorlar (biz qarzmiz)'), style: TextStyle(color: AppTheme.text)),
        actions: [IconButton(icon: Icon(Icons.refresh, color: AppTheme.text), onPressed: _load)],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppTheme.accent,
        onPressed: _add,
        child: Icon(Icons.add, color: AppTheme.onAccent),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : Column(children: [
              Container(
                margin: const EdgeInsets.all(14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
                ),
                child: Row(children: [
                  Icon(Icons.trending_down, color: Colors.red),
                  const SizedBox(width: 10),
                  Text(tr('Jami qarzmiz'), style: TextStyle(color: AppTheme.textSoft, fontSize: 13)),
                  const Spacer(),
                  Text('${_money(_owed)} ${tr('so\'m')}',
                      style: const TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold)),
                ]),
              ),
              Expanded(
                child: _items.isEmpty
                    ? Center(child: Text(tr('Kreditor yo\'q'), style: TextStyle(color: AppTheme.textSoft)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AppTheme.accent,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          itemCount: _items.length,
                          itemBuilder: (_, i) => _row(_items[i] as Map),
                        ),
                      ),
              ),
            ]),
    );
  }

  Widget _row(Map it) {
    final total = _n(it['total_amount']);
    final paid = _n(it['paid_amount']);
    final remaining = _n(it['remaining']);
    final closed = remaining <= 0.5;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: closed ? Colors.green.withValues(alpha: 0.4) : AppTheme.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (it['type'] == 'supplier')
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(color: AppTheme.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Text(tr('Postavshik'), style: TextStyle(color: AppTheme.accent, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          Expanded(child: Text(it['name']?.toString() ?? '', style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 15))),
          if (closed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
              child: Text(tr('To\'landi'), style: const TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
            )
          else
            Text('${_money(remaining)} ${tr('so\'m')}', style: const TextStyle(color: Colors.red, fontSize: 15, fontWeight: FontWeight.bold)),
        ]),
        if ((it['creditor']?.toString() ?? '').isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 2), child: Text('${tr('Kimga')}: ${it['creditor']}', style: TextStyle(color: AppTheme.textSoft, fontSize: 12))),
        if ((it['description']?.toString() ?? '').isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 2), child: Text(tr(it['description'].toString()), style: TextStyle(color: AppTheme.textSoft, fontSize: 12))),
        const SizedBox(height: 4),
        Text('${tr('To\'langan')}: ${_money(paid)} / ${_money(total)}  •  ${it['date'] ?? ''}',
            style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
        const SizedBox(height: 6),
        Row(children: [
          if (!closed)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pay(it),
                icon: const Icon(Icons.payments, size: 16, color: Colors.green),
                label: Text(tr('To\'lash'), style: const TextStyle(color: Colors.green, fontSize: 12)),
                style: OutlinedButton.styleFrom(side: BorderSide(color: AppTheme.border), padding: const EdgeInsets.symmetric(vertical: 4)),
              ),
            ),
          if (!closed) const SizedBox(width: 8),
          // Postavshik qarzini bu yerdan o'chirib bo'lmaydi (partiyalarga bog'liq)
          if (it['type'] != 'supplier')
            IconButton(
              icon: Icon(Icons.delete_outline, color: AppTheme.textSoft, size: 20),
              onPressed: () => _delete(it),
            ),
        ]),
      ]),
    );
  }
}

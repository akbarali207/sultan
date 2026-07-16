import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../core/api_service.dart';
import '../core/constants.dart';
import '../core/app_theme.dart';
import '../core/lang.dart';

/// Kassa ko'rinishi — admin va kassir oynalarida ishlatiladi.
/// Davr bo'yicha tushum/chiqim (karta/naqd), qarz qoldig'i, tranzaksiyalar va qarzdorlar.
class CashboxView extends StatefulWidget {
  const CashboxView({super.key});

  @override
  State<CashboxView> createState() => _CashboxViewState();
}

class _CashboxViewState extends State<CashboxView> {
  bool _loading = true;
  String _period = 'today';
  String? _selectedDate; // aniq kun tanlanganda (YYYY-MM-DD), period o'rniga from/to ishlaydi
  int _tab = 0; // 0 = tranzaksiyalar, 1 = qarzdorlar
  String _txFilter = 'all'; // all | income | expense
  String _methodFilter = 'all'; // all | cash | card — to'lov usuli
  final TextEditingController _amountCtrl = TextEditingController(); // summa bo'yicha qidiruv
  bool _busy = false; // pul operatsiyasi ketmoqda — ikki marta bosishdan himoya
  Map<String, dynamic>? _data;

  // Kassa parol bilan himoyalangan — har ochilganda parol so'raydi
  bool _unlocked = false;
  bool _checking = false;
  String? _pwError;
  final TextEditingController _pwCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Ma'lumot parol kiritilgandan keyin yuklanadi
  }

  @override
  void dispose() {
    _pwCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    final pw = _pwCtrl.text;
    if (pw.isEmpty) {
      setState(() => _pwError = tr('Parolni kiriting'));
      return;
    }
    setState(() {
      _checking = true;
      _pwError = null;
    });
    try {
      final res = await ApiService.post(AppConstants.verifyPassword, {'password': pw});
      if (!mounted) return;
      if (res is Map && res['ok'] == true) {
        _pwCtrl.clear();
        setState(() {
          _unlocked = true;
          _checking = false;
        });
        _load();
      } else {
        setState(() {
          _pwError = tr('Parol noto\'g\'ri');
          _checking = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pwError = tr('Xato');
        _checking = false;
      });
    }
  }

  Widget _lockScreen() {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppTheme.accent.withValues(alpha: 0.12), shape: BoxShape.circle),
                    child: Icon(Icons.lock, size: 36, color: AppTheme.accent),
                  ),
                  const SizedBox(height: 14),
                  Text(tr('Kassa himoyalangan'),
                      style: TextStyle(color: AppTheme.text, fontSize: 19, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(tr('Davom etish uchun parolingizni kiriting'),
                      textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSoft, fontSize: 13)),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _pwCtrl,
                    obscureText: true,
                    autofocus: true,
                    onSubmitted: (_) => _unlock(),
                    style: TextStyle(color: AppTheme.text),
                    decoration: InputDecoration(
                      labelText: tr('Parol'),
                      labelStyle: TextStyle(color: AppTheme.textSoft),
                      errorText: _pwError,
                      prefixIcon: Icon(Icons.key, color: AppTheme.accent),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.textSoft), borderRadius: BorderRadius.circular(10)),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.accent), borderRadius: BorderRadius.circular(10)),
                      errorBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.red), borderRadius: BorderRadius.circular(10)),
                      focusedErrorBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.red), borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.accent, padding: const EdgeInsets.symmetric(vertical: 14)),
                      onPressed: _checking ? null : _unlock,
                      child: _checking
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(tr('Kirish'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Davr so'rovi: aniq kun tanlansa from/to, aks holda period
  String _rangeQuery() =>
      _selectedDate != null ? 'from=$_selectedDate&to=$_selectedDate' : 'period=$_period';

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await ApiService.get('${AppConstants.cashbox}?${_rangeQuery()}');
      if (mounted) {
        setState(() {
          _data = d is Map<String, dynamic> ? d : null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double _d(dynamic v) => double.tryParse(v?.toString() ?? '0') ?? 0;

  String _money(num v) {
    final neg = v < 0;
    final s = v.abs().toStringAsFixed(0);
    final b = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
      b.write(s[i]);
    }
    return (neg ? '-' : '') + b.toString();
  }

  String _periodLabel() {
    if (_selectedDate != null) return _selectedDate!;
    switch (_period) {
      case 'week': return tr('Hafta');
      case 'month': return tr('Oy');
      default: return tr('Bugun');
    }
  }

  // Kassa PDF hisoboti — savdo/karta/qarz/harajat + qoldiq + elektron pechat
  Future<void> _generatePdf() async {
    final d = _data;
    if (d == null) return;
    final income = (d['income'] as Map?) ?? {};
    final expense = (d['expense'] as Map?) ?? {};
    final net = (d['net'] as Map?) ?? {};
    final debt = (d['debt'] as Map?) ?? {};

    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();
    final now = DateTime.now();
    final two = (int x) => x.toString().padLeft(2, '0');
    final dateStr = '${two(now.day)}.${two(now.month)}.${now.year} ${two(now.hour)}:${two(now.minute)}';
    final blue = PdfColor.fromInt(0xFF2F80ED);

    pw.Widget kvRow(String k, double v, {PdfColor? color, bool bold = false}) => pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 6),
          decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(k, style: pw.TextStyle(font: bold ? fontBold : font, fontSize: bold ? 13 : 12, color: color ?? PdfColors.grey800)),
            pw.Text('${_money(v)} сом', style: pw.TextStyle(font: fontBold, fontSize: bold ? 14 : 12, color: color ?? PdfColors.black)),
          ]),
        );

    // Elektron pechat (dumaloq, biroz qiyshaygan)
    pw.Widget stamp() => pw.Transform.rotate(
          angle: -0.12,
          child: pw.Container(
            width: 122,
            height: 122,
            decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, border: pw.Border.all(color: blue, width: 2.5)),
            child: pw.Center(
              child: pw.Container(
                width: 104,
                height: 104,
                decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, border: pw.Border.all(color: blue, width: 1)),
                child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
                  pw.SvgImage(
                    svg: '<svg viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg"><polygon points="12,1.5 14.9,8.6 22.5,9.2 16.7,14 18.6,21.5 12,17.3 5.4,21.5 7.3,14 1.5,9.2 9.1,8.6" fill="#2F80ED"/></svg>',
                    width: 13,
                    height: 13,
                  ),
                  pw.Text('SULTAN', style: pw.TextStyle(font: fontBold, fontSize: 18, color: blue)),
                  pw.Text('SISTEMA', style: pw.TextStyle(font: fontBold, fontSize: 10, color: blue, letterSpacing: 2)),
                  pw.SizedBox(height: 3),
                  pw.Container(width: 58, height: 0.7, color: blue),
                  pw.SizedBox(height: 3),
                  pw.Text(tr('ELEKTRON'), style: pw.TextStyle(font: font, fontSize: 7, color: blue, letterSpacing: 1)),
                  pw.Text('${two(now.day)}.${two(now.month)}.${now.year}', style: pw.TextStyle(font: font, fontSize: 7, color: blue)),
                ]),
              ),
            ),
          ),
        );

    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('SULTAN', style: pw.TextStyle(font: fontBold, fontSize: 24, color: blue)),
            pw.Text(tr('Kassa hisoboti'), style: pw.TextStyle(font: font, fontSize: 13, color: PdfColors.grey700)),
          ]),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('${tr('Davr')}: ${_periodLabel()}', style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700)),
            pw.Text(dateStr, style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700)),
          ]),
        ]),
        pw.SizedBox(height: 8),
        pw.Divider(color: blue, thickness: 2, height: 2),
        pw.SizedBox(height: 16),

        pw.Text(tr('Tushum (savdo)'), style: pw.TextStyle(font: fontBold, fontSize: 14, color: PdfColors.green800)),
        pw.SizedBox(height: 4),
        kvRow(tr('Jami savdo'), _d(income['total'])),
        kvRow(tr('Karta'), _d(income['card']), color: blue),
        kvRow(tr('Naqd'), _d(income['cash']), color: PdfColors.green800),
        kvRow(tr('Qarz'), _d(debt['outstanding']), color: PdfColors.orange800),

        pw.SizedBox(height: 16),
        pw.Text(tr('Chiqim (harajat)'), style: pw.TextStyle(font: fontBold, fontSize: 14, color: PdfColors.red800)),
        pw.SizedBox(height: 4),
        kvRow(tr('Jami harajat'), _d(expense['total']), color: PdfColors.red800),
        kvRow(tr('Karta'), _d(expense['card'])),
        kvRow(tr('Naqd'), _d(expense['cash'])),

        pw.SizedBox(height: 18),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFEAF2FE), borderRadius: pw.BorderRadius.circular(10), border: pw.Border.all(color: blue, width: 1)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(tr('Kassada bo\'lishi kerak'), style: pw.TextStyle(font: fontBold, fontSize: 14, color: blue)),
            pw.SizedBox(height: 6),
            kvRow(tr('Kartada'), _d(net['card']), color: blue, bold: true),
            kvRow(tr('Naqd (qo\'lda)'), _d(net['cash']), color: PdfColors.green800, bold: true),
            pw.SizedBox(height: 2),
            kvRow(tr('Jami qoldiq'), _d(net['total']), bold: true),
          ]),
        ),

        pw.Spacer(),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(tr('Kassir imzosi'), style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey600)),
            pw.SizedBox(height: 22),
            pw.Container(width: 150, height: 0.7, color: PdfColors.grey500),
          ]),
          stamp(),
        ]),
      ]),
    ));

    final bytes = await pdf.save();
    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'kassa_hisobot_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}.pdf';
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

  // PDF tanlash menyusi — Qisqacha yoki To'liq
  void _showPdfMenu() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('PDF hisobot'), style: TextStyle(color: AppTheme.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.description_outlined, color: AppTheme.accent),
              title: Text(tr('Qisqacha'), style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold)),
              subtitle: Text(tr('Hozirgi holat — savdo/karta/naqd/qoldiq'),
                  style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
              onTap: () { Navigator.pop(context); _generatePdf(); },
            ),
            Divider(color: AppTheme.border),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.receipt_long, color: Colors.green),
              title: Text(tr('To\'liq hisobot'), style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold)),
              subtitle: Text(tr('Harajat, ofitsant, taom, qarzdor — boshliqqa'),
                  style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
              onTap: () { Navigator.pop(context); _generateFullPdf(); },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
        ],
      ),
    );
  }

  // TO'LIQ kassa hisoboti — boshliqqa topshirish uchun (10 bo'lim)
  Future<void> _generateFullPdf() async {
    final cb = _data;
    if (cb == null) return;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('To\'liq hisobot tayyorlanmoqda...')), duration: const Duration(seconds: 2)));
    }
    final income = (cb['income'] as Map?) ?? {};
    final expense = (cb['expense'] as Map?) ?? {};
    final opening = _d(cb['opening']);
    final debtOut = _d((cb['debt'] as Map?)?['outstanding']);

    Map<String, dynamic> sum = {};
    try {
      final r = await ApiService.get('${AppConstants.reportSummary}?${_rangeQuery()}');
      if (r is Map<String, dynamic>) sum = r;
    } catch (_) {}

    final font = await PdfGoogleFonts.notoSansRegular();
    final fontBold = await PdfGoogleFonts.notoSansBold();
    final now = DateTime.now();
    final two = (int x) => x.toString().padLeft(2, '0');
    final dateStr = '${two(now.day)}.${two(now.month)}.${now.year} ${two(now.hour)}:${two(now.minute)}';
    final blue = PdfColor.fromInt(0xFF2F80ED);
    final headerBg = PdfColor.fromInt(0xFFEFF4FB);
    final shClr = PdfColor.fromInt(0xFFD35400);
    final soClr = PdfColor.fromInt(0xFF8B5A2B);

    final incCard = _d(income['card']), incCash = _d(income['cash']);
    final expCard = _d(expense['card']), expCash = _d(expense['cash']);
    final topCard = incCard - expCard, topCash = incCash - expCash;

    pw.Widget cell(String t, {bool right = false, bool bold = false, PdfColor? color}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
          child: pw.Text(t,
              textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
              style: pw.TextStyle(font: bold ? fontBold : font, fontSize: 9, color: color ?? PdfColors.black)),
        );

    pw.Widget makeTable(List<String> headers, List<List<String>> data, List<double> widths, List<bool> rightCols, {List<PdfColor?>? rowColors}) {
      final rows = <pw.TableRow>[
        pw.TableRow(decoration: pw.BoxDecoration(color: headerBg), children: [
          for (int i = 0; i < headers.length; i++) cell(headers[i], right: rightCols[i], bold: true, color: PdfColors.grey800),
        ]),
      ];
      for (int r = 0; r < data.length; r++) {
        rows.add(pw.TableRow(children: [
          for (int i = 0; i < data[r].length; i++) cell(data[r][i], right: rightCols[i], color: rowColors != null ? rowColors[r] : null),
        ]));
      }
      return pw.Table(
        border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
        columnWidths: { for (int i = 0; i < widths.length; i++) i: pw.FlexColumnWidth(widths[i]) },
        children: rows,
      );
    }

    pw.Widget secTitle(String t, PdfColor c) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 13, bottom: 5),
          child: pw.Text(t, style: pw.TextStyle(font: fontBold, fontSize: 12, color: c)),
        );

    pw.Widget kv(String k, double v, {PdfColor? c, bool bold = false}) => pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 3.5),
          decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
          child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text(k, style: pw.TextStyle(font: bold ? fontBold : font, fontSize: bold ? 12 : 11, color: c ?? PdfColors.grey800)),
            pw.Text('${_money(v)} сом', style: pw.TextStyle(font: fontBold, fontSize: bold ? 13 : 11, color: c ?? PdfColors.black)),
          ]),
        );

    pw.Widget stamp() => pw.Transform.rotate(
          angle: -0.12,
          child: pw.Container(
            width: 116, height: 116,
            decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, border: pw.Border.all(color: blue, width: 2.5)),
            child: pw.Center(child: pw.Container(
              width: 98, height: 98,
              decoration: pw.BoxDecoration(shape: pw.BoxShape.circle, border: pw.Border.all(color: blue, width: 1)),
              child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
                pw.Text('SULTAN', style: pw.TextStyle(font: fontBold, fontSize: 17, color: blue)),
                pw.Text('SISTEMA', style: pw.TextStyle(font: fontBold, fontSize: 9, color: blue, letterSpacing: 2)),
                pw.SizedBox(height: 3),
                pw.Container(width: 52, height: 0.7, color: blue),
                pw.SizedBox(height: 3),
                pw.Text(tr('ELEKTRON'), style: pw.TextStyle(font: font, fontSize: 7, color: blue, letterSpacing: 1)),
                pw.Text('${two(now.day)}.${two(now.month)}.${now.year}', style: pw.TextStyle(font: font, fontSize: 7, color: blue)),
              ]),
            )),
          ),
        );

    final expList = (((sum['expenses_list'] as List?) ?? []).where((e) => e['from_kassa'] == true)).toList();
    final waiters = (sum['waiter_sales'] as List?) ?? [];
    final dishes = (sum['dishes_by_category'] as List?) ?? [];
    final debtors = (sum['debtors'] as List?) ?? [];

    final Map<String, List<dynamic>> byCat = {};
    for (final r in dishes) { byCat.putIfAbsent((r['category'] ?? '—').toString(), () => []).add(r); }
    bool isSh(String c) { final l = c.toLowerCase(); return l.contains('шашл') || l.contains('shashl'); }
    bool isSo(String c) { final l = c.toLowerCase(); return l.contains('самс') || l.contains('сомс') || l.contains('somsa'); }
    num qtyOf(dynamic it) => num.tryParse((it['qty'] ?? 0).toString()) ?? 0;
    List<List<String>> dishRows(List<dynamic> items) =>
        [for (final it in items) [it['dish']?.toString() ?? '', qtyOf(it).toString(), _money(_d(it['amount']))]];
    List<PdfColor?> dishColors(List<dynamic> items) =>
        [for (final it in items) (qtyOf(it) > 0 ? null : PdfColors.grey500)];

    final content = <pw.Widget>[];
    content.add(pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('SULTAN', style: pw.TextStyle(font: fontBold, fontSize: 22, color: blue)),
        pw.Text(tr('To\'liq kassa hisoboti'), style: pw.TextStyle(font: font, fontSize: 12, color: PdfColors.grey700)),
      ]),
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
        pw.Text('${tr('Davr')}: ${_periodLabel()}', style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700)),
        pw.Text(dateStr, style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey700)),
      ]),
    ]));
    content.add(pw.SizedBox(height: 6));
    content.add(pw.Divider(color: blue, thickness: 2, height: 2));

    // 1. Tushum
    content.add(secTitle(tr('1. Tushum (kirim)'), PdfColors.green800));
    content.add(kv(tr('Karta'), incCard, c: blue));
    content.add(kv(tr('Naqd'), incCash, c: PdfColors.green800));
    content.add(kv(tr('Jami tushum'), incCard + incCash, bold: true));

    // 2. Harajatlar
    content.add(secTitle(tr('2. Harajatlar (kassadan)'), PdfColors.red800));
    if (expList.isEmpty) {
      content.add(pw.Text(tr('Harajat yo\'q'), style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey600)));
    } else {
      content.add(makeTable(
        [tr('Nima uchun'), tr('Usul'), tr('Summa')],
        [for (final e in expList) [
          '${e['type_name'] ?? ''}${(e['name'] ?? '').toString().trim().isNotEmpty ? ' — ${e['name']}' : ''}',
          (e['method'] == 'card') ? tr('Karta') : tr('Naqd'),
          _money(_d(e['amount'])),
        ]],
        [5, 1.5, 2], [false, false, true],
      ));
    }
    content.add(pw.SizedBox(height: 4));
    content.add(kv(tr('Harajat — karta'), expCard, c: PdfColors.red800));
    content.add(kv(tr('Harajat — naqd'), expCash, c: PdfColors.red800));

    // 3. Topshiriladigan
    content.add(pw.SizedBox(height: 10));
    content.add(pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFEAF2FE), borderRadius: pw.BorderRadius.circular(8), border: pw.Border.all(color: blue, width: 1)),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(tr('3. TOPSHIRILADIGAN (harajat ayrilgan)'), style: pw.TextStyle(font: fontBold, fontSize: 13, color: blue)),
        pw.SizedBox(height: 4),
        kv(tr('Naqd'), topCash, c: PdfColors.green800, bold: true),
        kv(tr('Karta'), topCard, c: blue, bold: true),
        kv(tr('JAMI TOPSHIRILADIGAN'), topCash + topCard, bold: true),
        pw.SizedBox(height: 3),
        pw.Text('${tr('Float (kassada qoladi)')}: ${_money(opening)} сом  ·  ${tr('Qarz (olinmagan)')}: ${_money(debtOut)} сом',
            style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600)),
      ]),
    ));

    // 4. Ofitsantlar
    content.add(secTitle(tr('4. Ofitsantlar'), blue));
    if (waiters.isEmpty) {
      content.add(pw.Text(tr('Ma\'lumot yo\'q'), style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey600)));
    } else {
      content.add(makeTable(
        [tr('Ism'), tr('Zakaz'), tr('Savdo')],
        [for (final w in waiters) [w['full_name']?.toString() ?? '', (w['orders'] ?? 0).toString(), _money(_d(w['sales']))]],
        [4, 1.3, 2], [false, true, true],
      ));
    }

    // 5+. Shashlik, Somsa, boshqa taomlar
    final shashCats = byCat.keys.where(isSh).toList();
    final somsaCats = byCat.keys.where(isSo).toList();
    final otherCats = byCat.keys.where((c) => !isSh(c) && !isSo(c)).toList()..sort();
    int sn = 5;
    for (final c in shashCats) {
      content.add(secTitle('$sn. $c', shClr));
      content.add(makeTable([tr('Taom'), tr('Dona'), tr('Summa')], dishRows(byCat[c]!), [4, 1.2, 2], [false, true, true], rowColors: dishColors(byCat[c]!)));
      sn++;
    }
    for (final c in somsaCats) {
      content.add(secTitle('$sn. $c', soClr));
      content.add(makeTable([tr('Taom'), tr('Dona'), tr('Summa')], dishRows(byCat[c]!), [4, 1.2, 2], [false, true, true], rowColors: dishColors(byCat[c]!)));
      sn++;
    }
    content.add(secTitle('$sn. ${tr('Boshqa taomlar (sotilgan)')}', blue));
    for (final c in otherCats) {
      final soldItems = byCat[c]!.where((it) => qtyOf(it) > 0).toList();
      if (soldItems.isEmpty) continue;
      content.add(pw.Padding(padding: const pw.EdgeInsets.only(top: 6, bottom: 3),
          child: pw.Text(c, style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.grey700))));
      content.add(makeTable([tr('Taom'), tr('Dona'), tr('Summa')], dishRows(soldItems), [4, 1.2, 2], [false, true, true]));
    }
    sn++;

    // Qarzdorlar
    content.add(secTitle('$sn. ${tr('Qarzdorlar')}', PdfColors.orange800));
    if (debtors.isEmpty) {
      content.add(pw.Text(tr('Qarzdor yo\'q'), style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey600)));
    } else {
      content.add(makeTable(
        [tr('Ism'), tr('Sana'), tr('Summa')],
        [for (final dd in debtors) [dd['debtor_name']?.toString() ?? '—', (dd['dt'] ?? dd['date'] ?? '').toString(), _money(_d(dd['amount']))]],
        [3, 2.5, 2], [false, false, true],
      ));
    }
    sn++;

    // Umuman sotilmagan taomlar (0)
    content.add(secTitle('$sn. ${tr('Umuman sotilmagan taomlar (0)')}', PdfColors.grey700));
    final unsold = <String, List<dynamic>>{};
    for (final entry in byCat.entries) {
      final z = entry.value.where((it) => qtyOf(it) == 0).toList();
      if (z.isNotEmpty) unsold[entry.key] = z;
    }
    if (unsold.isEmpty) {
      content.add(pw.Text(tr('Hammasi sotilgan'), style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey600)));
    } else {
      for (final entry in unsold.entries) {
        content.add(pw.Padding(padding: const pw.EdgeInsets.only(top: 5, bottom: 2),
            child: pw.Text('${entry.key}:', style: pw.TextStyle(font: fontBold, fontSize: 10, color: PdfColors.grey700))));
        content.add(pw.Text(entry.value.map((it) => it['dish']?.toString() ?? '').join(', '),
            style: pw.TextStyle(font: font, fontSize: 9, color: PdfColors.grey600)));
      }
    }

    // Imzolar + pechat
    content.add(pw.SizedBox(height: 22));
    content.add(pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
      pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text(tr('Kassir imzosi'), style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey600)),
        pw.SizedBox(height: 18),
        pw.Container(width: 150, height: 0.7, color: PdfColors.grey500),
        pw.SizedBox(height: 14),
        pw.Text(tr('Boshliq imzosi'), style: pw.TextStyle(font: font, fontSize: 10, color: PdfColors.grey600)),
        pw.SizedBox(height: 18),
        pw.Container(width: 150, height: 0.7, color: PdfColors.grey500),
      ]),
      stamp(),
    ]));

    final pdf = pw.Document();
    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (ctx) => content,
    ));

    final bytes = await pdf.save();
    final dir = await getApplicationDocumentsDirectory();
    final fileName = 'kassa_toliq_${now.year}${two(now.month)}${two(now.day)}_${two(now.hour)}${two(now.minute)}.pdf';
    final filePath = '${dir.path}/$fileName';
    await File(filePath).writeAsBytes(bytes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${tr('PDF saqlandi')}: $filePath'), backgroundColor: Colors.green, duration: const Duration(seconds: 4)));
    }
    await OpenFilex.open(filePath);
  }

  String _sourceLabel(String src) {
    switch (src) {
      case 'order': return tr('Zakaz');
      case 'debt': return tr('Qarz');
      case 'salary': return tr('Oylik');
      case 'advance': return tr('Avans');
      case 'expense': return tr('Xarajat');
      case 'stock': return tr('Sklad');
      case 'opening': return tr('Kassa ochilishi');
      default: return tr('Qo\'lda');
    }
  }

  // Kun yakunlash (Z-hisobot) + kech yopishlarni tasdiqlash (director/admin)
  Future<void> _closeDay() async {
    List<dynamic> pending = [];
    try {
      final r = await ApiService.get('/reports/day-closes?status=pending');
      pending = r is List ? r : [];
    } catch (_) {}
    if (!mounted) return;
    // Yopiladigan biznes-kun — default JORIY biznes-kun (tun-yarim o'tsa ham
    // 02:30 gacha oldingi kun). Kech qolган kassir kechagi kunni tanlab yopa oladi.
    DateTime bizToday = DateTime.now().subtract(const Duration(hours: 2, minutes: 30));
    DateTime selDate = DateTime(bizToday.year, bizToday.month, bizToday.day);
    String d2(int n) => n.toString().padLeft(2, '0');
    String fmt(DateTime d) => '${d.year}-${d2(d.month)}-${d2(d.day)}';
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text(tr('Kun yakunlash (Z)'), style: TextStyle(color: AppTheme.text, fontSize: 17)),
          content: SizedBox(
            width: (MediaQuery.of(context).size.width * 0.9).clamp(0.0, 360.0),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Kunni yopish (Z-hisobot). Vaqtida (02:30 gача) yopilmasa — direktor tasdig\'i kerak.'),
                    style: TextStyle(color: AppTheme.textSoft, fontSize: 13)),
                const SizedBox(height: 12),
                // Yopiladigan kunni tanlash (kech qolганда kechagi kun)
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: selDate,
                      firstDate: DateTime(2024, 1, 1),
                      lastDate: DateTime(bizToday.year, bizToday.month, bizToday.day),
                    );
                    if (picked != null) setSt(() => selDate = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.textSoft.withValues(alpha: 0.4)),
                        borderRadius: BorderRadius.circular(8)),
                    child: Row(children: [
                      Icon(Icons.calendar_today, size: 16, color: AppTheme.textSoft),
                      const SizedBox(width: 8),
                      Text('${tr('Kun')}: ${fmt(selDate)}',
                          style: TextStyle(color: AppTheme.text, fontSize: 13, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
                    icon: const Icon(Icons.event_available, color: Colors.white),
                    label: Text(tr('Kunni yopish'), style: const TextStyle(color: Colors.white)),
                    onPressed: () async {
                      try {
                        final res = await ApiService.post('/reports/close-day', {'biz_date': fmt(selDate)},
                            idempotencyKey: ApiService.newIdempotencyKey());
                        if (!ctx.mounted) return;
                        final st = res is Map ? res['status']?.toString() : null;
                        final okClose = st == 'closed' || st == 'approved';
                        final msg = st == 'pending'
                            ? tr('Yuborildi — direktor tasdig\'ini kutmoqda')
                            : okClose
                                ? tr('Kun yopildi ✓')
                                : (res is Map ? (res['message']?.toString() ?? tr('Xato')) : tr('Xato'));
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                            content: Text(msg), backgroundColor: okClose ? Colors.green : Colors.orange));
                        Navigator.pop(ctx);
                      } catch (e) {
                        if (!ctx.mounted) return;
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                            content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
                      }
                    },
                  ),
                ),
                if (pending.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(tr('Tasdiqlash kutilmoqda (kech yopilgan):'),
                      style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 13)),
                  ...pending.map((p) => Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('${p['biz_date']} — ${p['closed_by_name'] ?? ''}',
                                  style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.w600, fontSize: 13)),
                              Text('${tr('Savdo')}: ${p['sales']}  ·  ${tr('Kassa')}: ${p['received']}',
                                  style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
                            ]),
                          ),
                          IconButton(
                            icon: const Icon(Icons.check_circle, color: Colors.green),
                            tooltip: tr('Tasdiqlash'),
                            onPressed: () async {
                              try {
                                await ApiService.post('/reports/day-closes/${p['id']}/approve', {'approve': true});
                                setSt(() => pending.remove(p));
                              } catch (e) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                      content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
                                }
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.cancel, color: Colors.red),
                            tooltip: tr('Rad etish'),
                            onPressed: () async {
                              try {
                                await ApiService.post('/reports/day-closes/${p['id']}/approve', {'approve': false});
                                setSt(() => pending.remove(p));
                              } catch (e) {
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                                      content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
                                }
                              }
                            },
                          ),
                        ]),
                      )),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Yopish'), style: TextStyle(color: AppTheme.textSoft))),
          ],
        ),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([AppTheme.instance, Lang.instance]),
      builder: (context, _) => _content(),
    );
  }

  Widget _content() {
    if (!_unlocked) return _lockScreen();
    final income = (_data?['income'] as Map?) ?? {};
    final expense = (_data?['expense'] as Map?) ?? {};
    final net = (_data?['net'] as Map?) ?? {};
    final debt = (_data?['debt'] as Map?) ?? {};
    final txs = (_data?['transactions'] as List?) ?? [];
    final debtors = (_data?['debtors'] as List?) ?? [];

    return Scaffold(
      backgroundColor: AppTheme.bg,
      floatingActionButton: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'pulKirim',
            backgroundColor: Colors.green,
            onPressed: () => _addManual(initialKind: 'income'),
            icon: const Icon(Icons.add, color: Colors.white),
            label: Text(tr('Pul kiritish'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          FloatingActionButton.extended(
            heroTag: 'pulChiqim',
            backgroundColor: Colors.red,
            onPressed: () => _addManual(initialKind: 'expense'),
            icon: const Icon(Icons.remove, color: Colors.white),
            label: Text(tr('Pul chiqarish'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          FloatingActionButton(
            heroTag: 'kunYopish',
            backgroundColor: Colors.blueGrey,
            tooltip: tr('Kun yakunlash (Z)'),
            onPressed: _closeDay,
            child: const Icon(Icons.event_available, color: Colors.white),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(Icons.point_of_sale, color: AppTheme.accent),
                    const SizedBox(width: 8),
                    Text(tr('Kassa'),
                        style: TextStyle(color: AppTheme.text, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    // Chiplar + tugmalar tor telefonda sig'masa — gorizontal scroll (reverse: o'ngga tekislangan)
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        reverse: true,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _periodChip(tr('Bugun'), 'today'),
                            _periodChip(tr('Hafta'), 'week'),
                            _periodChip(tr('Oy'), 'month'),
                            _dateChip(),
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: tr('Kassani ochish'),
                              icon: Icon(Icons.lock_open, color: AppTheme.accent),
                              onPressed: _openRegister,
                            ),
                            IconButton(
                              tooltip: tr('PDF hisobot'),
                              icon: Icon(Icons.picture_as_pdf, color: AppTheme.accent),
                              onPressed: _data == null ? null : _showPdfMenu,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Karta / Naqd / Qarz (qoldiq)
                Row(
                  children: [
                    _card(tr('Karta'), _money(_d(net['card'])), Colors.blue, Icons.credit_card),
                    const SizedBox(width: 8),
                    _card(tr('Naqd'), _money(_d(net['cash'])), Colors.green, Icons.payments),
                    const SizedBox(width: 8),
                    _card(tr('Qarz'), _money(_d(debt['outstanding'])), Colors.deepOrange, Icons.account_balance_wallet),
                  ],
                ),
                if (_d(_data?['opening']) > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(children: [
                      Icon(Icons.lock_open, color: AppTheme.textSoft, size: 13),
                      const SizedBox(width: 6),
                      Text('${tr('Kassa ochildi')}: ${_money(_d(_data?['opening']))} ${tr('so\'m')}',
                          style: TextStyle(color: AppTheme.textSoft, fontSize: 12)),
                    ]),
                  ),
                const SizedBox(height: 8),
                // Tushum / Chiqim
                Row(
                  children: [
                    Expanded(
                      child: _miniRow(Icons.arrow_downward, tr('Tushum'), _money(_d(income['total'])), Colors.green,
                          active: _txFilter == 'income',
                          onTap: () => setState(() {
                                _txFilter = _txFilter == 'income' ? 'all' : 'income';
                                _tab = 0;
                              })),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _miniRow(Icons.arrow_upward, tr('Chiqim'), _money(_d(expense['total'])), Colors.red,
                          active: _txFilter == 'expense',
                          onTap: () => setState(() {
                                _txFilter = _txFilter == 'expense' ? 'all' : 'expense';
                                _tab = 0;
                              })),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _tabChip(tr('Tranzaksiyalar'), 0, _applyTxFilters(txs).length),
                    const SizedBox(width: 8),
                    _tabChip(tr('Qarzdorlar'), 1, debtors.length),
                  ],
                ),
                // To'lov usuli filtri (naqd/karta) + summa bo'yicha qidiruv — faqat tranzaksiyalar tabida
                if (_tab == 0) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    _methodChip(tr('Hammasi'), 'all'),
                    const SizedBox(width: 6),
                    _methodChip(tr('Naqd'), 'cash'),
                    const SizedBox(width: 6),
                    _methodChip(tr('Karta'), 'card'),
                    const SizedBox(width: 10),
                    Expanded(child: SizedBox(height: 38, child: TextField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      style: TextStyle(color: AppTheme.text, fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: tr('Summa bo\'yicha qidirish'),
                        hintStyle: TextStyle(color: AppTheme.textSoft, fontSize: 12),
                        prefixIcon: Icon(Icons.search, size: 16, color: AppTheme.textSoft),
                        suffixIcon: _amountCtrl.text.isEmpty ? null : IconButton(
                          icon: Icon(Icons.close, size: 15, color: AppTheme.textSoft),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => setState(() => _amountCtrl.clear()),
                        ),
                        filled: true,
                        fillColor: AppTheme.bg,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.border)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppTheme.accent)),
                      ),
                    ))),
                  ]),
                ],
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: AppTheme.accent))
                : RefreshIndicator(
                    color: AppTheme.accent,
                    onRefresh: _load,
                    child: _tab == 0 ? _txList(txs) : _debtorList(debtors),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _periodChip(String label, String value) {
    final sel = _period == value && _selectedDate == null;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: GestureDetector(
        onTap: () {
          setState(() { _period = value; _selectedDate = null; });
          _load();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

  // Aniq kun tanlash chipi — bosilganda kalendar ochiladi
  Widget _dateChip() {
    final sel = _selectedDate != null;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: GestureDetector(
        onTap: _pickDate,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: sel ? AppTheme.accent : AppTheme.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: sel ? AppTheme.accent : AppTheme.border),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.calendar_today, size: 13, color: sel ? Colors.white : AppTheme.textSoft),
            const SizedBox(width: 5),
            Text(sel ? _selectedDate! : tr('Kun tanlash'),
                style: TextStyle(color: sel ? Colors.white : AppTheme.textSoft, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final init = _selectedDate != null ? (DateTime.tryParse(_selectedDate!) ?? now) : now;
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(2024, 1, 1),
      lastDate: now,
    );
    if (picked != null) {
      final ds = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      setState(() => _selectedDate = ds);
      _load();
    }
  }

  Widget _card(String label, String value, Color color, IconData icon) {
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
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 4),
            FittedBox(child: Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold))),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _miniRow(IconData icon, String label, String value, Color color, {VoidCallback? onTap, bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.12) : AppTheme.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? color : AppTheme.border, width: active ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Icon(active ? Icons.filter_alt : icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: active ? color : AppTheme.textSoft, fontSize: 12, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
            const Spacer(),
            Flexible(
              child: FittedBox(
                child: Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabChip(String label, int tab, int count) {
    final sel = _tab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = tab),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: sel ? AppTheme.accent : AppTheme.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: sel ? AppTheme.accent : AppTheme.border),
          ),
          child: Text('$label ($count)',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: sel ? Colors.white : AppTheme.textSoft,
                  fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                  fontSize: 13)),
        ),
      ),
    );
  }

  // Barcha filtrlar: kind (tushum/chiqim) + to'lov usuli (naqd/karta) + summa qidiruv
  List _applyTxFilters(List txs) {
    final q = _amountCtrl.text.trim();
    return txs.where((t) {
      if (_txFilter != 'all' && (t['kind']?.toString() ?? '') != _txFilter) return false;
      if (_methodFilter != 'all' && (t['method']?.toString() ?? 'cash') != _methodFilter) return false;
      if (q.isNotEmpty && !_d(t['amount']).round().toString().contains(q)) return false;
      return true;
    }).toList();
  }

  Widget _methodChip(String label, String key) {
    final sel = _methodFilter == key;
    return InkWell(
      onTap: () => setState(() => _methodFilter = key),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: sel ? AppTheme.accent : AppTheme.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: sel ? AppTheme.accent : AppTheme.border),
        ),
        child: Text(label, style: TextStyle(color: sel ? Colors.white : AppTheme.text, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    );
  }

  Widget _txList(List txs) {
    final shown = _applyTxFilters(txs);
    if (shown.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 100),
        Center(child: Text(tr('Tranzaksiya yo\'q'), style: TextStyle(color: AppTheme.textSoft))),
      ]);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
      itemCount: shown.length,
      itemBuilder: (_, i) {
        final t = shown[i] as Map<String, dynamic>;
        final isIncome = t['kind'] == 'income';
        final method = t['method']?.toString() ?? 'cash';
        final amount = _d(t['amount']);
        final source = t['source']?.toString() ?? 'manual';
        final note = t['note']?.toString() ?? '';
        final at = t['at']?.toString() ?? '';
        final c = isIncome ? Colors.green : Colors.red;
        final isManual = source == 'manual';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: c.withValues(alpha: 0.15),
                child: Icon(isIncome ? Icons.arrow_downward : Icons.arrow_upward, color: c, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(_sourceLabel(source),
                            style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(width: 6),
                        Icon(method == 'card' ? Icons.credit_card : Icons.payments,
                            size: 12, color: AppTheme.textSoft),
                      ],
                    ),
                    Text('${note.isNotEmpty ? '$note  •  ' : ''}$at',
                        style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
                  ],
                ),
              ),
              Text('${isIncome ? '+' : '-'}${_money(amount)}',
                  style: TextStyle(color: c, fontSize: 14, fontWeight: FontWeight.bold)),
              if (isManual)
                IconButton(
                  icon: Icon(Icons.close, size: 16, color: AppTheme.textSoft),
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    await ApiService.delete('${AppConstants.cashbox}/${t['id']}');
                    await _load();
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _debtorList(List debtors) {
    if (debtors.isEmpty) {
      return ListView(children: [
        const SizedBox(height: 100),
        Center(child: Text(tr('Qarzdor yo\'q'), style: TextStyle(color: AppTheme.textSoft))),
      ]);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
      itemCount: debtors.length,
      itemBuilder: (_, i) {
        final d = debtors[i] as Map<String, dynamic>;
        final name = d['debtor_name']?.toString() ?? '';
        final remaining = _d(d['remaining']);
        final amount = _d(d['amount']);
        final paid = _d(d['paid_amount']);
        final date = d['date']?.toString() ?? '';
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.deepOrange.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.deepOrange.withValues(alpha: 0.15),
                child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold, fontSize: 14)),
                    Text('$date  •  ${tr('Jami:')} ${_money(amount)}${paid > 0 ? ' (${_money(paid)} ${tr('to\'landi')})' : ''}',
                        style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${_money(remaining)} ${tr('so\'m')}',
                      style: const TextStyle(color: Colors.deepOrange, fontSize: 15, fontWeight: FontWeight.bold)),
                  GestureDetector(
                    onTap: () => _payDebt(d),
                    child: Container(
                      margin: const EdgeInsets.only(top: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                      ),
                      child: Text(tr('To\'lash'),
                          style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _payDebt(Map<String, dynamic> d) async {
    final remaining = _d(d['remaining']);
    final ctrl = TextEditingController(text: remaining.toStringAsFixed(0));
    String method = 'cash';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text(tr('Qarzni to\'lash'), style: TextStyle(color: AppTheme.text)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${d['debtor_name']}  •  ${tr('Qoldiq')}: ${_money(remaining)} ${tr('so\'m')}',
                  style: TextStyle(color: AppTheme.textSoft, fontSize: 13)),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                onTap: () => ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length),
                style: TextStyle(color: AppTheme.text),
                decoration: InputDecoration(
                  labelText: tr('Summa'),
                  suffixText: tr('so\'m'),
                  labelStyle: TextStyle(color: AppTheme.textSoft),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _methodToggle(tr('Naqd'), method == 'cash', () => setSt(() => method = 'cash')),
                  const SizedBox(width: 8),
                  _methodToggle(tr('Karta'), method == 'card', () => setSt(() => method = 'card')),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('To\'lash'), style: TextStyle(color: AppTheme.accent))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final amt = double.tryParse(ctrl.text.trim().replaceAll(' ', '')) ?? 0;
    if (amt <= 0) return;
    if (_busy) return; // so'rov ketayotganda takror bosish ishlamaydi
    setState(() => _busy = true);
    try {
      // Idempotency-Key — qarz to'lovi retry'da ikki marta o'tmasligi uchun
      final res = await ApiService.post('${AppConstants.debts}/${d['id']}/pay', {'amount': amt, 'method': method},
          idempotencyKey: ApiService.newIdempotencyKey());
      // 4xx (qarz allaqachon to'langan, xato summa) da xato TASHLANMAYDI — {message} qaytadi.
      if (res is Map && res['paid'] == null && res['message'] != null && res['message'] != 'ok') {
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
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addManual({String initialKind = 'income'}) async {
    final ctrl = TextEditingController();
    final noteCtrl = TextEditingController();
    String kind = initialKind;
    String method = 'cash';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text(tr('Yangi harakat'), style: TextStyle(color: AppTheme.text)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _methodToggle(tr('Kirim'), kind == 'income', () => setSt(() => kind = 'income'), color: Colors.green),
                  const SizedBox(width: 8),
                  _methodToggle(tr('Chiqim'), kind == 'expense', () => setSt(() => kind = 'expense'), color: Colors.red),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _methodToggle(tr('Naqd'), method == 'cash', () => setSt(() => method = 'cash')),
                  const SizedBox(width: 8),
                  _methodToggle(tr('Karta'), method == 'card', () => setSt(() => method = 'card')),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                style: TextStyle(color: AppTheme.text),
                decoration: InputDecoration(
                    labelText: tr('Summa'), suffixText: tr('so\'m'), labelStyle: TextStyle(color: AppTheme.textSoft)),
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
    final amt = double.tryParse(ctrl.text.trim().replaceAll(' ', '')) ?? 0;
    if (amt <= 0) return;
    if (_busy) return; // so'rov ketayotganda takror bosish ishlamaydi
    setState(() => _busy = true);
    try {
      // Idempotency-Key — kirim/chiqim retry'da ikki marta yozilmasligi uchun
      final res = await ApiService.post(AppConstants.cashbox, {
        'kind': kind,
        'method': method,
        'amount': amt,
        'note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      }, idempotencyKey: ApiService.newIdempotencyKey());
      if (res is Map && res['id'] == null && res['message'] != null) {
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
      if (mounted) setState(() => _busy = false);
    }
  }

  // Kassani ochish — boshlang'ich naqd qoldiqni kiritish (bugungi)
  Future<void> _openRegister() async {
    final cur = _d(_data?['opening']);
    final ctrl = TextEditingController(text: cur > 0 ? cur.toStringAsFixed(0) : '');
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: Text(tr('Kassani ochish'), style: TextStyle(color: AppTheme.text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('Kassa qancha naqd pul bilan ochilyapti?'),
                style: TextStyle(color: AppTheme.textSoft, fontSize: 13)),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              onTap: () => ctrl.selection = TextSelection(baseOffset: 0, extentOffset: ctrl.text.length),
              style: TextStyle(color: AppTheme.text),
              decoration: InputDecoration(
                  labelText: tr('Boshlang\'ich summa'), suffixText: tr('so\'m'),
                  labelStyle: TextStyle(color: AppTheme.textSoft)),
            ),
            TextField(
              controller: noteCtrl,
              style: TextStyle(color: AppTheme.text),
              decoration: InputDecoration(
                  labelText: tr('Izoh (ixtiyoriy)'), labelStyle: TextStyle(color: AppTheme.textSoft)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(tr('Bekor'), style: TextStyle(color: AppTheme.textSoft))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Ochish'), style: TextStyle(color: AppTheme.onAccent)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final amt = double.tryParse(ctrl.text.trim().replaceAll(' ', '')) ?? 0;
    if (_busy) return; // so'rov ketayotganda takror bosish ishlamaydi
    setState(() => _busy = true);
    try {
      // Idempotency-Key — kassa ochilishi retry'da ikki marta yozilmasligi uchun
      await ApiService.post('${AppConstants.cashbox}/open', {'amount': amt, 'note': noteCtrl.text.trim()},
          idempotencyKey: ApiService.newIdempotencyKey());
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${tr('Xato')}: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _methodToggle(String label, bool sel, VoidCallback onTap, {Color? color}) {
    final c = color ?? AppTheme.accent;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: sel ? c.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: sel ? c : AppTheme.border),
          ),
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(color: sel ? c : AppTheme.textSoft, fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
        ),
      ),
    );
  }
}

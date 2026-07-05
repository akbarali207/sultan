import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Kirillni qo'llaydigan shrift yuklaydi.
/// 1) Windows tizim shrifti (offline, internetsiz) — eng ishonchli.
/// 2) Bo'lmasa internetdan Noto Sans.
/// 3) Hech biri bo'lmasa null (standart shrift — kirill chiqmasligi mumkin).
Future<pw.Font?> _loadFont({required bool bold}) async {
  // 1) Windows tizim Arial (kirillni to'liq qo'llaydi)
  final candidates = bold
      ? [r'C:\Windows\Fonts\arialbd.ttf', r'C:\Windows\Fonts\arial.ttf']
      : [r'C:\Windows\Fonts\arial.ttf'];
  for (final path in candidates) {
    try {
      final f = File(path);
      if (await f.exists()) {
        final bytes = await f.readAsBytes();
        return pw.Font.ttf(bytes.buffer.asByteData());
      }
    } catch (_) {}
  }
  // 2) Internetdan (Noto Sans kirillni qo'llaydi)
  try {
    return bold
        ? await PdfGoogleFonts.notoSansBold()
        : await PdfGoogleFonts.notoSansRegular();
  } catch (_) {}
  return null;
}

/// 80mm kuhnya cheki PDF hujjatini quradi.
Future<pw.Document> _buildReceiptDoc({
  required int tableNumber,
  required String waiterName,
  required List<Map<String, dynamic>> items,
  required double total,
  String? note,
  int? orderId,
}) async {
  final now = DateTime.now();
  final dateStr = DateFormat('dd.MM.yyyy  HH:mm').format(now);

  final base = await _loadFont(bold: false);
  final bold = await _loadFont(bold: true);
  final theme = base != null
      ? pw.ThemeData.withFont(base: base, bold: bold ?? base)
      : null;

  final doc = theme != null ? pw.Document(theme: theme) : pw.Document();

  const pageFormat = PdfPageFormat(
    80 * PdfPageFormat.mm,
    double.infinity,
    marginAll: 4 * PdfPageFormat.mm,
  );

  pw.Widget divider() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Text('-' * 32, style: const pw.TextStyle(fontSize: 9)),
      );

  doc.addPage(
    pw.Page(
      pageFormat: pageFormat,
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
            child: pw.Text('SULTAN RESTORAN',
                style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text('KUHNYA CHEKI',
                style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          ),
          pw.SizedBox(height: 4),
          pw.Text(dateStr, style: const pw.TextStyle(fontSize: 9)),
          if (orderId != null)
            pw.Text('Zakaz №$orderId',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
          pw.Text('Ofitsant: $waiterName', style: const pw.TextStyle(fontSize: 9)),
          pw.Text('Stol: $tableNumber',
              style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
          divider(),
          ...items.map((it) {
            final name = (it['name'] ?? '').toString();
            final qty = it['qty'] ?? it['quantity'] ?? 1;
            return pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 1),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Text(name,
                        style: pw.TextStyle(
                            fontSize: 11, fontWeight: pw.FontWeight.bold)),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Text('x$qty',
                      style: pw.TextStyle(
                          fontSize: 12, fontWeight: pw.FontWeight.bold)),
                ],
              ),
            );
          }),
          divider(),
          if (note != null && note.trim().isNotEmpty) ...[
            pw.Text('Izoh: ${note.trim()}',
                style: pw.TextStyle(fontSize: 10, fontStyle: pw.FontStyle.italic)),
            pw.SizedBox(height: 4),
          ],
          pw.Center(
            child: pw.Text(DateFormat('HH:mm:ss').format(now),
                style: const pw.TextStyle(fontSize: 9)),
          ),
        ],
      ),
    ),
  );

  return doc;
}

/// Saqlangan printerga TO'G'RIDAN (dialogsiz) chek yuboradi.
/// Xato bo'lsa — ANIQ matn bilan Exception otadi (yutib yubormaydi).
Future<void> printKitchenReceipt({
  required int tableNumber,
  required String waiterName,
  required List<Map<String, dynamic>> items,
  required double total,
  String? note,
  int? orderId,
}) async {
  final doc = await _buildReceiptDoc(
    tableNumber: tableNumber,
    waiterName: waiterName,
    items: items,
    total: total,
    note: note,
    orderId: orderId,
  );

  final prefs = await SharedPreferences.getInstance();
  final savedUrl = prefs.getString('printer_url');
  if (savedUrl == null) {
    throw 'Printer tanlanmagan. Profil > Printerni sozlash dan tanlang.';
  }

  final printers = await Printing.listPrinters();
  Printer? target;
  for (final p in printers) {
    if (p.url == savedUrl) {
      target = p;
      break;
    }
  }
  if (target == null) {
    final saved = prefs.getString('printer_name') ?? savedUrl;
    throw 'Saqlangan printer ($saved) topilmadi. Profil > Printerni sozlash dan qayta tanlang.';
  }

  final ok = await Printing.directPrintPdf(
    printer: target,
    onLayout: (f) => doc.save(),
  );
  if (!ok) {
    throw 'Printerga yuborib bo\'lmadi (directPrintPdf=false). Printer: ${target.name}';
  }
}

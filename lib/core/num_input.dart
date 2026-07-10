import 'package:flutter/services.dart';

/// iPhone raqam-padi muammosi uchun: VERGULni NUQTAga o'giradi + faqat raqam va bitta nuqta.
/// Shunda ',' yozilsa ham (ba'zi locale'da pad vergul ko'rsatadi) qiymat to'g'ri saqlanadi
/// — `double.tryParse` faqat '.' ni tushunadi, vergul bo'lsa null qaytarardi (noto'g'ri qiymat).
class DecimalInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    String t = newValue.text.replaceAll(',', '.');
    t = t.replaceAll(RegExp(r'[^0-9.\-]'), ''); // faqat raqam, nuqta, minus
    final i = t.indexOf('.');
    if (i != -1) {
      t = t.substring(0, i + 1) + t.substring(i + 1).replaceAll('.', ''); // faqat bitta nuqta
    }
    if (t.contains('-')) t = '-${t.replaceAll('-', '')}'; // minus faqat boshda
    return TextEditingValue(text: t, selection: TextSelection.collapsed(offset: t.length));
  }
}

/// Raqamli (pul/miqdor) maydonlar uchun tayyor formatterlar.
final List<TextInputFormatter> decimalFormatters = [DecimalInputFormatter()];

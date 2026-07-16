import 'package:flutter/material.dart';
import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../../core/lang.dart';

// DAVOMAT TARIXI — davr bo'yicha: har kun kelish/ketish/soat + kechikish/erta ketish + jami.
// Filtrlar: xodim + sana oralig'i.
class AttendanceHistoryPage extends StatefulWidget {
  const AttendanceHistoryPage({super.key});
  @override
  State<AttendanceHistoryPage> createState() => _AttendanceHistoryPageState();
}

class _AttendanceHistoryPageState extends State<AttendanceHistoryPage> {
  bool _loading = true;
  List<dynamic> _staff = [];
  int? _userFilter; // null = barchasi
  late DateTime _from;
  late DateTime _to;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month, now.day);
    _load();
  }

  String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _dmy(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  num _n(dynamic v) => v is num ? v : (num.tryParse(v?.toString() ?? '0') ?? 0);
  String _fmtNum(num v) => v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
  String _hm(num min) {
    final h = (min ~/ 60).toInt();
    final m = (min % 60).toInt();
    return h > 0 ? '${h}ч ${m}м' : '${m}м';
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await ApiService.get('/reports/attendance-history?from=${_ymd(_from)}&to=${_ymd(_to)}');
      if (mounted) {
        setState(() {
          _staff = (r is Map ? r['staff'] : null) as List? ?? [];
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: DateTimeRange(start: _from, end: _to.isAfter(now) ? now : _to),
      builder: (c, w) => Theme(
        data: (AppTheme.dark ? ThemeData.dark() : ThemeData.light())
            .copyWith(colorScheme: (AppTheme.dark ? const ColorScheme.dark() : const ColorScheme.light()).copyWith(primary: AppTheme.accent)),
        child: w!,
      ),
    );
    if (picked != null) {
      setState(() {
        _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
        _to = DateTime(picked.end.year, picked.end.month, picked.end.day);
      });
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Tanlangan xodim joriy ro'yxatда bormi? Bo'lmasa — "Barcha" (null). Dropdown va ro'yxat mos bo'lsin.
    final selUser = _staff.any((s) => (s['user_id'] as num?)?.toInt() == _userFilter) ? _userFilter : null;
    final shown = selUser == null ? _staff : _staff.where((s) => (s['user_id'] as num?)?.toInt() == selUser).toList();
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.card,
        iconTheme: IconThemeData(color: AppTheme.text),
        title: Text(tr('Davomat tarixi'), style: TextStyle(color: AppTheme.text)),
        actions: [IconButton(icon: Icon(Icons.refresh, color: AppTheme.text), onPressed: _load)],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : Column(children: [
              // Filtrlar
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                child: Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickRange,
                      icon: Icon(Icons.date_range, size: 16, color: AppTheme.accent),
                      label: Text('${_dmy(_from)} – ${_dmy(_to)}', style: TextStyle(color: AppTheme.accent, fontSize: 12)),
                      style: OutlinedButton.styleFrom(side: BorderSide(color: AppTheme.border)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      // Tanlangan xodim yangi davrда ro'yxatда bo'lmasa — null (Barcha) ga qaytamiz,
                      // aks holda Flutter "value bitta item bilan mos kelishi kerak" deb kraş qiladi.
                      value: selUser,
                      isExpanded: true,
                      dropdownColor: AppTheme.card,
                      style: TextStyle(color: AppTheme.text, fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                        border: OutlineInputBorder(borderSide: BorderSide(color: AppTheme.border)),
                      ),
                      items: [
                        DropdownMenuItem<int?>(value: null, child: Text(tr('Barcha xodim'), style: TextStyle(color: AppTheme.text))),
                        ..._staff.map((s) => DropdownMenuItem<int?>(
                            value: (s['user_id'] as num).toInt(),
                            child: Text(s['full_name']?.toString() ?? '', overflow: TextOverflow.ellipsis, style: TextStyle(color: AppTheme.text)))),
                      ],
                      onChanged: (v) => setState(() => _userFilter = v),
                    ),
                  ),
                ]),
              ),
              Expanded(
                child: shown.isEmpty
                    ? Center(child: Text(tr('Davomat yo\'q'), style: TextStyle(color: AppTheme.textSoft)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: shown.length,
                        itemBuilder: (_, i) => _empCard(shown[i] as Map),
                      ),
              ),
            ]),
    );
  }

  Widget _empCard(Map s) {
    final rows = (s['rows'] as List?) ?? [];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _userFilter != null,
          iconColor: AppTheme.accent,
          collapsedIconColor: AppTheme.accent,
          title: Text(s['full_name']?.toString() ?? '', style: TextStyle(color: AppTheme.text, fontWeight: FontWeight.bold)),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(spacing: 10, runSpacing: 2, children: [
              _chip('${_n(s['days'])} ${tr('kun')}', AppTheme.accent),
              _chip('${_fmtNum(_n(s['total_hours']))} ${tr('soat')}', Colors.teal),
              if (_n(s['late_days']) > 0) _chip('${_n(s['late_days'])} ${tr('kechikish')} (${_hm(_n(s['total_late_min']))})', Colors.orange),
              Text('${s['work_start'] ?? '—'}–${s['work_end'] ?? '—'}', style: TextStyle(color: AppTheme.textSoft, fontSize: 11)),
            ]),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          children: [
            // Sarlavha
            Row(children: [
              Expanded(flex: 3, child: Text(tr('Sana'), style: TextStyle(color: AppTheme.textSoft, fontSize: 11))),
              Expanded(flex: 3, child: Text(tr('Kelish→Ketish'), style: TextStyle(color: AppTheme.textSoft, fontSize: 11))),
              Expanded(flex: 2, child: Text(tr('Soat'), textAlign: TextAlign.right, style: TextStyle(color: AppTheme.textSoft, fontSize: 11))),
            ]),
            const SizedBox(height: 2),
            for (final rr in rows) _dayRow(rr as Map),
          ],
        ),
      ),
    );
  }

  Widget _dayRow(Map r) {
    final late = _n(r['late_minutes']);
    final early = _n(r['early_minutes']);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(flex: 3, child: Text(r['day']?.toString() ?? '', style: TextStyle(color: AppTheme.text, fontSize: 12))),
        Expanded(
          flex: 3,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${r['check_in'] ?? '—'} → ${r['check_out'] ?? '—'}', style: TextStyle(color: AppTheme.text, fontSize: 12)),
            if (late > 0 || early > 0)
              Wrap(spacing: 4, children: [
                if (late > 0) _chip('${tr('kech')} ${_hm(late)}', Colors.orange),
                if (early > 0) _chip('${tr('erta')} ${_hm(early)}', Colors.deepOrange),
              ]),
          ]),
        ),
        Expanded(flex: 2, child: Text(_fmtNum(_n(r['hours'])), textAlign: TextAlign.right, style: TextStyle(color: AppTheme.accent, fontSize: 12, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  Widget _chip(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(6)),
        child: Text(t, style: TextStyle(color: c, fontSize: 10, fontWeight: FontWeight.w600)),
      );
}

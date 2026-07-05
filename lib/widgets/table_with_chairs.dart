import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Dumaloq stol + atrofida seats soni bo'yicha teng masofada stullar.
/// Admin (editor) va ofitsant (read-only) floor-plan'larida bir xil ishlatiladi.
/// O'lcham table_size bilan masshtablanadi (stol + stullar birga).
class TableWithChairs extends StatelessWidget {
  /// table_size = 1.0 dagi stol diametri (piksel).
  static const double defaultBase = 52.0;

  final String number;
  final int seats;
  final double tableSize; // 0.6..2.0
  final double baseDiameter;
  final Color color; // stol cheti + matn + stullar rangi
  final Color fill; // stol foni
  final String shape; // 'rect' (to'rtburchak) yoki 'circle' (dumaloq)

  const TableWithChairs({
    super.key,
    required this.number,
    required this.seats,
    this.tableSize = 1.0,
    this.baseDiameter = defaultBase,
    this.color = Colors.green,
    this.fill = const Color(0xFF0F3460),
    this.shape = 'rect',
  });

  // ── Geometriya (Positioned offset uchun parent ham foydalanadi) ──
  static double _tableDiameter(double base, double size) => base * size;
  static double _chairDiameter(double base, double size) => base * 0.32 * size;
  static double _ringRadius(double base, double size) =>
      _tableDiameter(base, size) / 2 + _chairDiameter(base, size) * 0.75 + 3;

  /// Stol + stullar halqasini o'rab turuvchi kvadrat tomoni (piksel).
  static double totalSize(double base, double size) {
    final chair = _chairDiameter(base, size);
    return 2 * (_ringRadius(base, size) + chair / 2);
  }

  @override
  Widget build(BuildContext context) {
    final d = _tableDiameter(baseDiameter, tableSize);
    final chair = _chairDiameter(baseDiameter, tableSize);
    final ring = _ringRadius(baseDiameter, tableSize);
    final total = totalSize(baseDiameter, tableSize);
    final center = total / 2;

    final numFont = (15 * tableSize).clamp(9.0, 26.0);
    final seatFont = (9 * tableSize).clamp(6.0, 15.0);

    // ── TO'RTBURCHAK stol: stullar yuqori va pastki qirralarda ──
    if (shape == 'rect') {
      final tableW = total - chair * 1.4;
      final tableH = total * 0.46;
      final left = (total - tableW) / 2;
      final top = (total - tableH) / 2;
      final topN = (seats / 2).ceil();
      final botN = seats - topN;

      Widget chairBox(double cx, double cy) => Positioned(
            left: cx - chair / 2,
            top: cy - chair / 2,
            child: Container(
              width: chair,
              height: chair,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(chair * 0.28),
                border: Border.all(color: Colors.white24, width: 1),
              ),
            ),
          );

      final chairs = <Widget>[];
      void rowChairs(int nn, double cy) {
        for (int i = 0; i < nn; i++) {
          final frac = (i + 1) / (nn + 1);
          chairs.add(chairBox(left + frac * tableW, cy));
        }
      }

      rowChairs(topN, top - chair * 0.62);
      rowChairs(botN, top + tableH + chair * 0.62);

      return SizedBox(
        width: total,
        height: total,
        child: Stack(
          children: [
            ...chairs,
            Positioned(
              left: left,
              top: top,
              child: Container(
                width: tableW,
                height: tableH,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color, width: 2.5),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 5, offset: const Offset(0, 2)),
                  ],
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(number,
                          style: TextStyle(color: color, fontSize: numFont.toDouble(), fontWeight: FontWeight.bold)),
                      Text('$seats kishi', style: TextStyle(color: Colors.white70, fontSize: seatFont.toDouble())),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      width: total,
      height: total,
      child: Stack(
        children: [
          // Stullar (stol ostida — stol ustiga chiqadi)
          if (seats > 0)
            for (int i = 0; i < seats; i++)
              _chair(i, center, ring, chair),
          // Stol
          Positioned(
            left: center - d / 2,
            top: center - d / 2,
            child: Container(
              width: d,
              height: d,
              decoration: BoxDecoration(
                color: fill,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 5,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      number,
                      style: TextStyle(
                        color: color,
                        fontSize: numFont.toDouble(),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '$seats kishi',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: seatFont.toDouble(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chair(int i, double center, double ring, double chair) {
    // Yuqoridan boshlaymiz (-90°), soat yo'nalishi bo'yicha teng taqsim
    final angle = 2 * math.pi * i / seats - math.pi / 2;
    final cx = center + ring * math.cos(angle);
    final cy = center + ring * math.sin(angle);
    return Positioned(
      left: cx - chair / 2,
      top: cy - chair / 2,
      child: Container(
        width: chair,
        height: chair,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(chair * 0.28),
          border: Border.all(color: Colors.white24, width: 1),
        ),
      ),
    );
  }
}

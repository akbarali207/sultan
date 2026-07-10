import 'package:flutter/material.dart';
import '../../core/app_theme.dart';

/// Sultan dizayn-tizimi — qayta-ishlatiladigan widgetlar. FAQAT KO'RINISH.
/// Ma'lumot/mantiq bulardan tashqarida; bular faqat stillaydi.

/// Yumshoq soya + chegara bilan karta.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final Color? color;
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(14),
      this.radius = AppTheme.rTile, this.onTap, this.color});
  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? AppTheme.card,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.softShadow,
      ),
      child: child,
    );
    if (onTap == null) return box;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(radius), child: box);
  }
}

/// Tabletka-chip (filtr / davr). Faol = accent fon, oq matn.
class AppChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  const AppChip({super.key, required this.label, this.selected = false, this.onTap, this.icon});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.rPill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accent : AppTheme.card,
          borderRadius: BorderRadius.circular(AppTheme.rPill),
          border: Border.all(color: selected ? AppTheme.accent : AppTheme.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null)
            Padding(padding: const EdgeInsets.only(right: 5),
                child: Icon(icon, size: 15, color: selected ? Colors.white : AppTheme.textSoft)),
          Text(label, style: TextStyle(color: selected ? Colors.white : AppTheme.textSoft,
              fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      ),
    );
  }
}

/// KPI-plitka: rangли ikonka + katta raqam (tabular) + label + delta.
class KpiTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final String? delta;
  final bool deltaUp;
  final double? width;
  const KpiTile({super.key, required this.icon, required this.color, required this.value,
      required this.label, this.delta, this.deltaUp = true, this.width});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppTheme.card, borderRadius: BorderRadius.circular(AppTheme.rTile),
          border: Border.all(color: AppTheme.border), boxShadow: AppTheme.softShadow),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(width: 30, height: 30, alignment: Alignment.center,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 18, color: color)),
          const SizedBox(width: 8),
          Expanded(child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppTheme.textSoft, fontSize: 11.5, height: 1.15))),
        ]),
        const SizedBox(height: 11),
        Text(value, style: TextStyle(color: AppTheme.text, fontSize: 19, fontWeight: FontWeight.w800,
            fontFeatures: AppTheme.tnum, letterSpacing: -0.4)),
        if (delta != null)
          Padding(padding: const EdgeInsets.only(top: 5), child: Row(children: [
            Icon(deltaUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 13,
                color: deltaUp ? AppTheme.success : AppTheme.danger),
            const SizedBox(width: 2),
            Text(delta!, style: TextStyle(color: deltaUp ? AppTheme.success : AppTheme.danger,
                fontSize: 11, fontWeight: FontWeight.w700)),
          ])),
      ]),
    );
  }
}

/// Seksiya sarlavhasi + ixtiyoriy "Hammasi" havolasi.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  const SectionHeader(this.title, {super.key, this.actionLabel, this.onAction});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: Text(title, style: TextStyle(color: AppTheme.text, fontSize: 15, fontWeight: FontWeight.w700))),
      if (actionLabel != null)
        InkWell(onTap: onAction, child: Text(actionLabel!,
            style: TextStyle(color: AppTheme.accent, fontSize: 12.5, fontWeight: FontWeight.w700))),
    ]);
  }
}

/// Proporsional bar (top taomlar / kategoriya / ofitsant).
class StatBar extends StatelessWidget {
  final String label;
  final String value;
  final double fraction; // 0..1
  final Gradient? gradient;
  final Color? color;
  const StatBar({super.key, required this.label, required this.value, required this.fraction, this.gradient, this.color});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppTheme.text, fontSize: 12.5, fontWeight: FontWeight.w600))),
        Text(value, style: TextStyle(color: AppTheme.textSoft, fontSize: 12, fontWeight: FontWeight.w700, fontFeatures: AppTheme.tnum)),
      ]),
      const SizedBox(height: 5),
      ClipRRect(borderRadius: BorderRadius.circular(5), child: Container(height: 8, color: AppTheme.track,
          child: FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: fraction.clamp(0.0, 1.0),
              child: Container(decoration: BoxDecoration(
                  gradient: gradient, color: gradient == null ? (color ?? AppTheme.accent) : null,
                  borderRadius: BorderRadius.circular(5)))))),
    ]);
  }
}

/// Kastom toggle (stop-list / tema). 48×27, animatsiyali.
class AppToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;
  const AppToggle({super.key, required this.value, this.onChanged, this.activeColor});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200), curve: Curves.easeInOut,
        width: 48, height: 27,
        decoration: BoxDecoration(color: value ? (activeColor ?? AppTheme.success) : AppTheme.track,
            borderRadius: BorderRadius.circular(14)),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 200), curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(padding: const EdgeInsets.all(3),
              child: Container(width: 21, height: 21, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle))),
        ),
      ),
    );
  }
}

/// Gradient shapka (ekran heroysi).
class HeroHeader extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  const HeroHeader({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(20, 56, 20, 18)});
  @override
  Widget build(BuildContext context) {
    return Container(width: double.infinity, padding: padding,
        decoration: const BoxDecoration(gradient: AppTheme.hero), child: child);
  }
}

/// Pastki navigatsiya elementi.
class NavItemData {
  final IconData icon;
  final String label;
  final int? badge;
  const NavItemData(this.icon, this.label, {this.badge});
}

/// Kastom pastki navigatsiya — faol tabga "pilyulya" + to'ldirilgan ikonka + bejik.
class AppBottomNav extends StatelessWidget {
  final List<NavItemData> items;
  final int current;
  final ValueChanged<int> onTap;
  const AppBottomNav({super.key, required this.items, required this.current, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppTheme.card,
          border: Border(top: BorderSide(color: AppTheme.border)), boxShadow: AppTheme.cardShadow),
      padding: EdgeInsets.only(top: 8, bottom: 8 + MediaQuery.of(context).padding.bottom),
      child: Row(children: [
        for (int i = 0; i < items.length; i++) Expanded(child: _item(items[i], i, i == current)),
      ]),
    );
  }

  Widget _item(NavItemData it, int index, bool active) {
    return InkWell(
      onTap: () => onTap(index),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Stack(clipBehavior: Clip.none, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            decoration: BoxDecoration(
                color: active ? AppTheme.accentSoft : Colors.transparent,
                borderRadius: BorderRadius.circular(12)),
            child: Icon(it.icon, size: 23, color: active ? AppTheme.accent : AppTheme.textSoft),
          ),
          if (it.badge != null && it.badge! > 0)
            Positioned(right: 6, top: -2, child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 16),
              decoration: BoxDecoration(color: AppTheme.danger, borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.card, width: 1.5)),
              child: Text('${it.badge}', textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
            )),
        ]),
        const SizedBox(height: 3),
        Text(it.label, style: TextStyle(color: active ? AppTheme.accent : AppTheme.textSoft,
            fontSize: 10.5, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// Pastki modal (yuqori burchak dumaloq rSheet).
Future<T?> showAppSheet<T>(BuildContext context, {required Widget child}) {
  return showModalBottomSheet<T>(
    context: context, backgroundColor: Colors.transparent, isScrollControlled: true,
    builder: (_) => Container(
      decoration: BoxDecoration(color: AppTheme.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppTheme.rSheet))),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(color: AppTheme.border, borderRadius: BorderRadius.circular(2))),
        child,
      ])),
    ),
  );
}

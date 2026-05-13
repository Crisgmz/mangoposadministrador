import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

/// Círculo con las iniciales de un negocio, coloreado de forma estable
/// según un hash del id (mismos colores siempre para el mismo negocio).
class BusinessAvatar extends StatelessWidget {
  const BusinessAvatar({
    required this.businessId,
    required this.businessName,
    this.size = 36,
    super.key,
  });

  final String businessId;
  final String businessName;
  final double size;

  static const _palette = <Color>[
    AppColors.primary,
    AppColors.accent,
    Color(0xFF6366F1), // indigo
    Color(0xFF06B6D4), // cyan
    Color(0xFFEC4899), // rose
    Color(0xFF8B5CF6), // violet
    Color(0xFF14B8A6), // teal
    Color(0xFFF59E0B), // amber
  ];

  Color get _color {
    if (businessId.isEmpty) return _palette[0];
    final hash = businessId.codeUnits.fold<int>(0, (s, c) => s + c);
    return _palette[hash % _palette.length];
  }

  String get _initials {
    final parts = businessName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '—';
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
    }
    return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = _color;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c, Color.lerp(c, Colors.white, 0.18)!],
        ),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

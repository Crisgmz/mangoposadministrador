import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../../app/theme/app_colors.dart';

/// Un KPI de la cinta.
class KpiCell {
  const KpiCell({
    required this.label,
    required this.value,
    required this.sublabel,
    required this.icon,
    required this.color,
    this.delta,
    this.deltaUp,
    this.progress,
    this.onTap,
  });

  final String label;
  final String value;
  final String sublabel;
  final IconData icon;
  final Color color;

  /// Variación contra el período anterior, ya formateada ("+8.4%", "+11").
  final String? delta;

  /// Si la variación es buena (verde) o mala (roja). En "fallas" subir es
  /// malo, en "ingresos" subir es bueno — por eso lo decide quien construye
  /// el KPI y no el signo del número.
  final bool? deltaUp;

  /// 0..1 — dibuja una barra bajo el valor. Solo para razones (17 de 24).
  final double? progress;

  final VoidCallback? onTap;
}

/// Cinta de KPIs: una sola card dividida en celdas, en vez de ocho tarjetas
/// sueltas.
///
/// Las ocho tarjetas anteriores ocupaban media pantalla y ninguna era más
/// importante que otra, así que el ojo no tenía dónde caer. Cinco celdas en
/// una cinta ocupan una franja y dejan el espacio ganado para lo que sí
/// exige decisión: la bandeja de acción.
class KpiStrip extends StatelessWidget {
  const KpiStrip({super.key, required this.cells});

  final List<KpiCell> cells;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Por debajo de ~200 px por celda los valores se truncan y la cinta
        // deja de ser legible: ahí pasa a grilla de dos columnas.
        final perCell = constraints.maxWidth / cells.length;
        if (perCell >= 190) {
          return _Ribbon(cells: cells);
        }
        final columns = constraints.maxWidth >= 420 ? 2 : 1;
        return _Grid(cells: cells, columns: columns);
      },
    );
  }
}

class _Ribbon extends StatelessWidget {
  const _Ribbon({required this.cells});
  final List<KpiCell> cells;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.6),
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.shadowCard,
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < cells.length; i++)
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: i == 0
                        ? null
                        : const Border(
                            left: BorderSide(color: AppColors.border),
                          ),
                  ),
                  child: _Cell(cell: cells[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.cells, required this.columns});
  final List<KpiCell> cells;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < cells.length; i += columns) {
      final slice = cells.skip(i).take(columns).toList();
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var j = 0; j < columns; j++) ...[
              if (j > 0) const SizedBox(width: 10),
              Expanded(
                child: j < slice.length
                    ? _CardCell(cell: slice[j])
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          IntrinsicHeight(child: rows[i]),
        ],
      ],
    );
  }
}

class _CardCell extends StatelessWidget {
  const _CardCell({required this.cell});
  final KpiCell cell;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.border, width: 0.6),
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppColors.shadowCard,
      ),
      clipBehavior: Clip.antiAlias,
      child: _Cell(cell: cell, compact: true),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.cell, this.compact = false});

  final KpiCell cell;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: compact
          ? const EdgeInsets.all(12)
          : const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: compact ? 22 : 26,
                height: compact ? 22 : 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cell.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(compact ? 7 : 9),
                ),
                child: Icon(
                  cell.icon,
                  size: compact ? 12 : 14,
                  color: cell.color,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cell.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 9 : 9.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.3,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 7 : 6),
          Text(
            cell.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 17 : 23,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              height: 1.05,
              color: AppColors.foreground,
            ),
          ),
          SizedBox(height: compact ? 2 : 6),
          Row(
            children: [
              if (cell.delta != null) ...[
                Text(
                  cell.delta!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: (cell.deltaUp ?? true)
                        ? AppColors.primary
                        : AppColors.destructive,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  cell.sublabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 10.5 : 11,
                    color: AppColors.mutedForeground,
                  ),
                ),
              ),
            ],
          ),
          if (cell.progress != null && !compact) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: cell.progress!.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: AppColors.muted,
                valueColor: AlwaysStoppedAnimation(cell.color),
              ),
            ),
          ],
        ],
      ),
    );

    if (cell.onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: cell.onTap, child: content),
    );
  }
}

/// Iconos que usa la Vista Global, en un solo sitio para que la cinta de
/// escritorio y la grilla móvil no se separen.
class KpiIcons {
  KpiIcons._();

  static const operating = HugeIcons.strokeRoundedWifi01;
  static const inbox = HugeIcons.strokeRoundedInbox;
  static const revenue = HugeIcons.strokeRoundedDollarCircle;
  static const ncf = HugeIcons.strokeRoundedInvoice03;
  static const printing = HugeIcons.strokeRoundedPrinter;
}

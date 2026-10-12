import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/widgets/empty_state.dart' show GlassCard;
import '../domain/dashboard_summary.dart';

const dashboardIncome = Color(0xFF40D5B0);
const dashboardExpense = Color(0xFFFFB85C);

String compactRupiah(num amount) => NumberFormat.compactCurrency(
  locale: 'id_ID',
  symbol: 'Rp ',
  decimalDigits: 1,
).format(amount);

class DashboardPanel extends StatelessWidget {
  const DashboardPanel({
    super.key,
    required this.title,
    required this.child,
    this.action,
  });
  final String title;
  final Widget child;
  final Widget? action;
  @override
  Widget build(BuildContext context) => SizedBox(
    height:
        AppTheme.dashboardPanelHeight +
        math.max(0, MediaQuery.textScalerOf(context).scale(14) / 14 - 1) * 160,
    child: GlassCard(
      padding: const EdgeInsets.all(AppTheme.pagePadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppTheme.minTouchTarget,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                if (action != null) ...[const SizedBox(width: 8), action!],
              ],
            ),
          ),
          const SizedBox(height: AppTheme.fieldSpacing),
          Expanded(
            child: DashboardScrollArea(
              key: ValueKey('dashboard-panel-scroll-$title'),
              child: child,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Every panel owns its scroll position; the page scrollbar stays independent.
class DashboardScrollArea extends StatefulWidget {
  const DashboardScrollArea({super.key, required this.child});
  final Widget child;
  @override
  State<DashboardScrollArea> createState() => _DashboardScrollAreaState();
}

class _DashboardScrollAreaState extends State<DashboardScrollArea> {
  final _controller = ScrollController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
    child: Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      interactive: true,
      thickness: 5,
      radius: const Radius.circular(8),
      child: SingleChildScrollView(
        controller: _controller,
        primary: false,
        padding: const EdgeInsets.only(right: 12),
        child: widget.child,
      ),
    ),
  );
}

class DashboardMetric extends StatelessWidget {
  const DashboardMetric({
    super.key,
    required this.title,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
    this.onTap,
    this.ratio,
  });
  final String title, value, detail;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final double? ratio;

  @override
  Widget build(BuildContext context) => SizedBox(
    height:
        AppTheme.dashboardMetricHeight +
        math.max(0, MediaQuery.textScalerOf(context).scale(14) / 14 - 1) * 160,
    child: GlassCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppTheme.pagePadding),
      child: DashboardScrollArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(icon, color: color, size: 20),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                if (ratio != null) ...[
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      value: ratio!.clamp(0, 1),
                      strokeWidth: 6,
                      strokeCap: StrokeCap.round,
                      color: color,
                      backgroundColor: Colors.white.withValues(alpha: .12),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: AppTheme.mutedText),
            ),
          ],
        ),
      ),
    ),
  );
}

class DashboardCashflowChart extends StatelessWidget {
  const DashboardCashflowChart({
    super.key,
    required this.points,
    required this.period,
  });
  final List<CashflowPoint> points;
  final CashflowPeriod period;
  @override
  Widget build(BuildContext context) {
    final highest = points.fold<int>(
      0,
      (value, p) => math.max(value, math.max(p.income, p.expense)),
    );
    final maxY = highest == 0 ? 100000.0 : highest * 1.25;
    final hasIncome = points.any((p) => p.hasIncome);
    final hasExpense = points.any((p) => p.hasExpense);
    final text = Theme.of(context).textTheme.bodySmall!
        .copyWith(fontSize: 10, color: AppTheme.mutedText);
    LineChartBarData series(bool income) => LineChartBarData(
      spots: [
        for (var i = 0; i < points.length; i++)
          (income ? points[i].hasIncome : points[i].hasExpense)
              ? FlSpot(
                  i.toDouble(),
                  (income ? points[i].income : points[i].expense).toDouble(),
                )
              : FlSpot.nullSpot,
      ],
      isCurved: false,
      color: income ? dashboardIncome : dashboardExpense,
      barWidth: 2.5,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: true,
        getDotPainter: (_, _, bar, _) => FlDotCirclePainter(
          radius: 3,
          color: bar.color!,
          strokeWidth: 1,
          strokeColor: Theme.of(context).colorScheme.surface,
        ),
      ),
      belowBarData: BarAreaData(
        show: true,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            (income ? dashboardIncome : dashboardExpense).withValues(
              alpha: .22,
            ),
            (income ? dashboardIncome : dashboardExpense).withValues(alpha: 0),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final item in [
              ('Pemasukan', dashboardIncome),
              ('Pengeluaran', dashboardExpense),
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 10, height: 4, color: item.$2),
                  const SizedBox(width: 6),
                  Text(item.$1, style: text.copyWith(fontSize: 12)),
                ],
              ),
          ],
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 210,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: math.max(1, points.length - 1).toDouble(),
              minY: 0,
              maxY: maxY,
              clipData: const FlClipData.all(),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxY / 4,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: Colors.white.withValues(alpha: .08),
                  strokeWidth: 1,
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 58,
                    interval: maxY / 4,
                    getTitlesWidget: (value, meta) =>
                        Text(compactRupiah(value), style: text),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: math
                        .max(
                          1,
                          (points.length /
                                  (period == CashflowPeriod.allTime ? 4 : 7))
                              .ceil(),
                        )
                        .toDouble(),
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (value != index.toDouble() ||
                          index < 0 ||
                          index >= points.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(points[index].label, style: text),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItems: (spots) => [
                    for (final spot in spots)
                      LineTooltipItem(
                        '${period == CashflowPeriod.weekly ? 'Minggu ${spot.x.toInt() + 1}' : points[spot.x.toInt()].label}\n'
                        '${spot.bar.color == dashboardIncome ? 'Pemasukan' : 'Pengeluaran'}\n'
                        '${formatRupiah(spot.y.round())}',
                        text.copyWith(
                          fontSize: 12,
                          color: spot.bar.color == dashboardIncome
                              ? dashboardIncome
                              : dashboardExpense,
                        ),
                      ),
                  ],
                ),
              ),
              lineBarsData: [
                if (hasIncome) series(true),
                if (hasExpense) series(false),
              ],
            ),
            duration: Duration.zero,
          ),
        ),
        if (!hasIncome && !hasExpense) ...[
          const SizedBox(height: 8),
          Text(
            'Belum ada arus kas pada periode ini.',
            style: text.copyWith(fontSize: 11),
          ),
        ],
      ],
    );
  }
}

class DashboardProgress extends StatelessWidget {
  const DashboardProgress({
    super.key,
    required this.value,
    required this.color,
  });
  final double value;
  final Color color;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: LinearProgressIndicator(
      value: value.clamp(0, 1),
      color: color,
      minHeight: 7,
      backgroundColor: Colors.white.withValues(alpha: .12),
    ),
  );
}

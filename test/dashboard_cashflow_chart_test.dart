import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:ledgy/core/theme/app_theme.dart';
import 'package:ledgy/features/dashboard/domain/dashboard_summary.dart';
import 'package:ledgy/features/dashboard/presentation/dashboard_widgets.dart';

CashflowPoint point(String label, {int? income, int? expense}) => CashflowPoint(
  label,
  income ?? 0,
  expense ?? 0,
  incomeCount: income == null ? 0 : 1,
  expenseCount: expense == null ? 0 : 1,
);

Future<LineChartData> showChart(
  WidgetTester tester,
  List<CashflowPoint> points, {
  CashflowPeriod period = CashflowPeriod.weekly,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: DashboardCashflowChart(points: points, period: period),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return tester.widget<LineChart>(find.byType(LineChart)).data;
}

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));
  testWidgets('grafik kosong tidak menggambar kedua garis pada nol', (
    tester,
  ) async {
    final data = await showChart(tester, [
      for (var i = 1; i <= 5; i++) point('M$i'),
    ]);
    expect(data.lineBarsData, isEmpty);
    expect(find.text('Belum ada arus kas pada periode ini.'), findsOneWidget);
  });

  testWidgets('data tunggal menjadi titik tanpa garis dari atau menuju nol', (
    tester,
  ) async {
    final data = await showChart(tester, [
      point('M1'),
      point('M2', income: 100),
      point('M3'),
    ]);
    final bar = data.lineBarsData.single;
    expect(bar.color, dashboardIncome);
    expect(bar.spots.first.isNull(), isTrue);
    expect(bar.spots[1], const FlSpot(1, 100));
    expect(bar.spots.last.isNull(), isTrue);
    expect(bar.dotData.show, isTrue);
    expect(find.textContaining('M1–M5:'), findsNothing);
    expect(find.textContaining('Total arus kas'), findsNothing);
  });

  testWidgets('garis terputus pada celah masing-masing jenis arus kas', (
    tester,
  ) async {
    final data = await showChart(tester, [
      point('M1', income: 100, expense: 30),
      point('M2', income: 200),
      point('M3'),
      point('M4', income: 300, expense: 60),
      point('M5'),
    ]);
    final income = data.lineBarsData[0], expense = data.lineBarsData[1];
    expect(income.spots.where((p) => !p.isNull()), [
      const FlSpot(0, 100),
      const FlSpot(1, 200),
      const FlSpot(3, 300),
    ]);
    expect(income.spots[2].isNull(), isTrue);
    expect(expense.spots[1].isNull(), isTrue);
    expect(expense.spots[2].isNull(), isTrue);
    expect(expense.spots[4].isNull(), isTrue);
  });

  testWidgets('tooltip pengeluaran tetap benar ketika tidak ada pemasukan', (
    tester,
  ) async {
    final data = await showChart(tester, [
      point('M1'),
      point('M2'),
      point('M3', expense: 50),
    ]);
    final bar = data.lineBarsData.single;
    final tooltip = data.lineTouchData.touchTooltipData.getTooltipItems([
      LineBarSpot(bar, 0, bar.spots[2]),
    ]).single!;
    expect(tooltip.text, contains('Minggu 3'));
    expect(tooltip.text, contains('Pengeluaran'));
    expect(tooltip.text, isNot(contains('Pemasukan')));
  });

  testWidgets(
    'keseluruhan tanpa transaksi tetap kosong dan dapat ditampilkan',
    (tester) async {
      final data = await showChart(tester, [], period: CashflowPeriod.allTime);
      expect(data.lineBarsData, isEmpty);
      expect(find.text('Belum ada arus kas pada periode ini.'), findsOneWidget);
    },
  );
}

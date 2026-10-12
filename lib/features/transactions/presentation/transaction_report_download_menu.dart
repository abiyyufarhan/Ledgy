import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../reports/data/finance_report_exporter.dart';

Future<FinanceReportFormat?> showTransactionReportDownloadMenu({
  required BuildContext context,
  required BuildContext anchorContext,
}) {
  final anchor = anchorContext.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(
            context,
            rootNavigator: true,
          ).overlay!.context.findRenderObject()!
          as RenderBox;
  final origin = anchor.localToGlobal(Offset.zero, ancestor: overlay);
  return showMenu<FinanceReportFormat>(
    context: context,
    useRootNavigator: true,
    position: RelativeRect.fromRect(
      Rect.fromLTWH(
        origin.dx,
        origin.dy + anchor.size.height + AppTheme.menuMargin,
        anchor.size.width,
        0,
      ),
      Offset.zero & overlay.size,
    ),
    semanticLabel: 'Download Laporan',
    constraints: const BoxConstraints.tightFor(width: 220),
    color: const Color(0xFF2B3A4D),
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: Color(0xDFFFFFFF)),
    ),
    clipBehavior: Clip.antiAlias,
    menuPadding: const EdgeInsets.all(12),
    popUpAnimationStyle: AnimationStyle(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppTheme.menuDuration,
    ),
    items: const [
      PopupMenuItem<FinanceReportFormat>(
        enabled: false,
        padding: EdgeInsets.zero,
        child: Padding(
          padding: EdgeInsets.only(top: 4, bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Download',
                  style: TextStyle(
                    color: AppTheme.sidebarText,
                    fontSize: 16,
                    height: 1.2,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Laporan',
                  style: TextStyle(
                    color: AppTheme.sidebarText,
                    fontSize: 16,
                    height: 1.2,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              SizedBox(height: 12),
              Divider(height: 1, thickness: 1, color: AppTheme.sidebarText),
            ],
          ),
        ),
      ),
      PopupMenuItem<FinanceReportFormat>(
        value: FinanceReportFormat.xlsx,
        height: AppTheme.minTouchTarget,
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: _DownloadFormatLabel(
          icon: Icons.table_chart_outlined,
          label: 'Excel',
        ),
      ),
      PopupMenuItem<FinanceReportFormat>(
        value: FinanceReportFormat.pdf,
        height: AppTheme.minTouchTarget,
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: _DownloadFormatLabel(
          icon: Icons.picture_as_pdf_outlined,
          label: 'PDF',
        ),
      ),
    ],
  );
}

class _DownloadFormatLabel extends StatelessWidget {
  const _DownloadFormatLabel({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20, color: AppTheme.sidebarText),
      const SizedBox(width: AppTheme.menuRowPadding),
      Expanded(
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge
              ?.copyWith(color: AppTheme.sidebarText),
        ),
      ),
    ],
  );
}

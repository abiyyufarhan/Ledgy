import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../local/presentation/local_providers.dart';
import '../data/receipt_storage.dart';
import '../data/mlkit_receipt_backend.dart';
import '../domain/receipt/receipt_scan_backend.dart';
import '../domain/receipt/receipt_parser.dart';
import '../domain/receipt/receipt_recovery.dart';

final receiptStorageProvider = Provider(
  (ref) => ReceiptStorage(ref.watch(localFinanceProvider)),
);
final receiptSavePhotoProvider = FutureProvider(
  (ref) => ref.watch(receiptStorageProvider).enabled(),
);
final receiptScanBackendProvider = Provider<ReceiptScanBackend>(
  (ref) => MlKitReceiptBackend(),
);
final receiptParserProvider = Provider((ref) => const ReceiptParser());
final receiptRecoveryProvider = Provider(
  (ref) => ReceiptRecovery(ref.watch(receiptScanBackendProvider)),
);

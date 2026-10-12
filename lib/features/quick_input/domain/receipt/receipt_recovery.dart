import 'receipt_scan_backend.dart';

/// One startup recovery per app session. A new Dashboard must not replay a
/// recovered photo whose confirmation has already deleted its temporary file.
final class ReceiptRecovery {
  ReceiptRecovery(this.backend);
  final ReceiptScanBackend backend;
  bool _attempted = false;
  Future<ReceiptPhoto?> recoverOnce() async {
    if (_attempted) {
      return null;
    }
    _attempted = true;
    return backend.recover();
  }
}

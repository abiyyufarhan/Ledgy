import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'receipt_providers.dart';

final _attachmentProvider = FutureProvider.autoDispose.family<String?, String>(
  (ref, id) => ref.watch(receiptStorageProvider).photoFor(id),
);

class ReceiptAttachmentAction extends ConsumerWidget {
  const ReceiptAttachmentAction({super.key, required this.transactionId});
  final String transactionId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb || Theme.of(context).platform != TargetPlatform.android) {
      return const SizedBox.shrink();
    }
    final path = ref.watch(_attachmentProvider(transactionId)).value;
    if (path == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        icon: const Icon(Icons.receipt_long_outlined),
        label: const Text('Lihat foto struk'),
        onPressed: () => showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Lampiran struk'),
            content: SizedBox(
              height: MediaQuery.sizeOf(context).height * .65,
              width: MediaQuery.sizeOf(context).width * .8,
              child: InteractiveViewer(
                child: Image.file(
                  File(path),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Text('Lampiran tidak lagi tersedia di perangkat.'),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tutup'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/app_providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/glass_panel.dart';

class AssetSetupPage extends ConsumerStatefulWidget {
  const AssetSetupPage({super.key});
  @override
  ConsumerState<AssetSetupPage> createState() => _AssetSetupPageState();
}

class _AssetSetupPageState extends ConsumerState<AssetSetupPage> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _balance = TextEditingController(text: '0');
  bool _busy = false;
  String? _error;

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(accountActionsProvider)
          .save(name: _name.text, initialBalance: int.parse(_balance.text));
      if (mounted) context.go('/accounts');
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Aset belum dapat disimpan. Coba lagi.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Tambah aset'),
      leading: IconButton(
        tooltip: 'Kembali',
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.go('/accounts'),
      ),
    ),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.pagePadding),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppTheme.authWidth),
          child: GlassPanel(
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Tambahkan aset Anda',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppTheme.fieldSpacing),
                  const Text(
                    'Masukkan nama tempat menyimpan uang dan saldo awalnya.',
                  ),
                  const SizedBox(height: AppTheme.sectionSpacing),
                  TextFormField(
                    controller: _name,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'Nama tempat aset',
                      hintText: 'Contoh: Bank Jago',
                    ),
                    validator: (value) => (value?.trim().isEmpty ?? true)
                        ? 'Masukkan nama aset.'
                        : null,
                  ),
                  const SizedBox(height: AppTheme.fieldSpacing),
                  TextFormField(
                    controller: _balance,
                    enabled: !_busy,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Saldo awal (Rp)',
                    ),
                    validator: (value) => int.tryParse(value ?? '') == null
                        ? 'Masukkan saldo dalam rupiah bulat.'
                        : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppTheme.fieldSpacing),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppTheme.sectionSpacing),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: Text(_busy ? 'Menyimpan…' : 'Simpan aset'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _name.dispose();
    _balance.dispose();
    super.dispose();
  }
}

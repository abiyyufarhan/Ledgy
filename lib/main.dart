import 'package:flutter/widgets.dart';

import 'app/ledgy_startup.dart';
import 'core/privacy/error_reporting.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installPrivateErrorReporting();
  runApp(const LedgyStartup());
}

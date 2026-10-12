import 'package:uuid/data.dart';
import 'package:uuid/uuid.dart';

/// Recreate the same v4 UUID on every device for a single schedule occurrence.
/// The random v4 rule ID supplies the namespace entropy. A namespaced digest
/// mixes in the UTC occurrence before feeding bytes to UUID's v4 constructor.
/// This avoids duplicate income/bills when both devices catch up while offline.
String recurringOccurrenceId(String ruleId, DateTime occurrence) {
  const uuid = Uuid();
  final digest = uuid.v5(
    Namespace.url.value,
    'ledgy:occurrence:$ruleId:${occurrence.toUtc().toIso8601String()}',
  );
  final bytes = Uuid.parse(digest);
  return uuid.v4(config: V4Options(bytes, null));
}

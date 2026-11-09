import 'package:flutter_test/flutter_test.dart';
import 'package:zlibx/utils/diagnostics.dart';

void main() {
  setUp(Diagnostics.clear);

  test('records tag and exception type only, never the message', () {
    logIgnored('unit', const FormatException('cookie=SECRET'));
    final dump = Diagnostics.dump();
    expect(dump, contains('[unit] FormatException'));
    expect(dump, isNot(contains('SECRET')));
  });

  test('ring buffer is bounded and drops the oldest first', () {
    for (var i = 0; i < Diagnostics.maxEntries + 25; i++) {
      logIgnored('t$i', StateError('x'));
    }
    final snap = Diagnostics.snapshot();
    expect(snap.length, Diagnostics.maxEntries);
    expect(snap.first, contains('[t25]'));
  });
}

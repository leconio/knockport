import 'package:flutter_test/flutter_test.dart';
import 'package:knockgate_client/services/auto_refresh_service.dart';

void main() {
  test('open timeout parser supports KnockGate duration formats', () {
    expect(parseOpenTimeout('12h'), const Duration(hours: 12));
    expect(parseOpenTimeout('1d'), const Duration(days: 1));
    expect(parseOpenTimeout('0'), Duration.zero);
    expect(parseOpenTimeout('10'), const Duration(seconds: 10));
    expect(parseOpenTimeout('bad'), isNull);
  });

  test('auto refresh decision matches CLI client behavior', () {
    final service = AutoRefreshService(ipCheckUrls: const <String>[]);
    final now = DateTime.fromMillisecondsSinceEpoch(2000 * 1000);

    final ipChange = service.shouldRefresh(
      currentIP: '8.8.8.8',
      lastIP: '1.1.1.1',
      lastKnock: now,
      openTimeout: '12h',
      now: now,
    );
    expect(ipChange.shouldKnock, isTrue);
    expect(ipChange.reason, contains('public IP changed'));

    final unchanged = service.shouldRefresh(
      currentIP: '8.8.8.8',
      lastIP: '8.8.8.8',
      lastKnock: now.subtract(const Duration(hours: 1)),
      openTimeout: '12h',
      now: now,
    );
    expect(unchanged.shouldKnock, isFalse);
    expect(unchanged.nextRefreshAfter, isNotNull);

    final expired = service.shouldRefresh(
      currentIP: '8.8.8.8',
      lastIP: '8.8.8.8',
      lastKnock: now.subtract(const Duration(hours: 12)),
      openTimeout: '12h',
      now: now,
    );
    expect(expired.shouldKnock, isTrue);

    final permanent = service.shouldRefresh(
      currentIP: '8.8.8.8',
      lastIP: '8.8.8.8',
      lastKnock: now.subtract(const Duration(days: 1)),
      openTimeout: '0',
      now: now,
    );
    expect(permanent.shouldKnock, isFalse);
    expect(permanent.nextRefreshAfter, isNull);
  });
}

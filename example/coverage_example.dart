import 'package:hegeltest/hegeltest.dart';

enum UserTier { free, pro, enterprise }

void main() async {
  print('=== Distribution Coverage & Classification Example ===\n');

  final result = await runHegelTest((tc) {
    // 1. Draw inputs using weighted sampling (e.g., realistic traffic distribution)
    final UserTier tier = tc.draw(
      sampledWeighted<UserTier>([
        (70, UserTier.free),
        (25, UserTier.pro),
        (5, UserTier.enterprise),
      ]),
      label: 'user_tier',
    );

    final requestCount = tc.draw(
      integers(min: 0, max: 1000),
      label: 'requests',
    );

    // 2. Classify observations for observability into distribution quality
    tc.classify(requestCount == 0, 'idle (0 requests)', label: 'activity');
    tc.classify(
      requestCount > 0 && requestCount <= 100,
      'low traffic (1-100)',
      label: 'activity',
    );
    tc.classify(requestCount > 100, 'high traffic (>100)', label: 'activity');

    // 3. Enforce minimum coverage contracts with tc.cover()
    // Guarantees CI fails if the generator fails to exercise rare tiers or edge states.
    tc.cover(2.0, tier == UserTier.enterprise, 'enterprise tier exercised');
    tc.cover(10.0, tier == UserTier.pro, 'pro tier exercised');
    tc.cover(50.0, tier == UserTier.free, 'free tier exercised');
    tc.cover(0.5, requestCount == 0, 'idle traffic scenario exercised');

    // System logic / invariants under test
    final quota = switch (tier) {
      UserTier.free => 100,
      UserTier.pro => 500,
      UserTier.enterprise => 1000,
    };
    final isRateLimited = requestCount > quota;

    // Verify invariant: free tier is always rate limited if requests > 100
    if (tier == UserTier.free && requestCount > 100 && !isRateLimited) {
      throw StateError('Rate limiter failed for free tier');
    }
  }, testCases: 300);

  print('Status: ${result.status}');
  print('Test cases executed: ${result.testCasesRun}');
  if (result.failures.isNotEmpty) {
    for (final f in result.failures) {
      print('Failure: ${f.message}');
    }
  }
  print('\nCollected distribution statistics:');
  print(result.formatStatistics());
}

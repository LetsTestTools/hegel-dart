import 'package:hegeltest/hegeltest.dart';

void main() async {
  print('Running a passing property...');
  final passResult = await runHegelTest((tc) {
    final a = tc.draw(integers());
    final b = tc.draw(integers());
    assert(a + b == b + a);
  });

  print('Status: ${passResult.status.name}');
  print('Test cases run: ${passResult.testCasesRun}\n');

  print('Running a failing property...');
  final failResult = await runHegelTest((tc) {
    final xs = tc.draw(lists(integers()), label: 'items');
    if (xs.length > 5) {
      throw Exception('List is too long!');
    }
  });

  print('Status: ${failResult.status.name}');
  print('Test cases run: ${failResult.testCasesRun}');

  if (failResult.failures.isNotEmpty) {
    final failure = failResult.failures.first;
    print('\nFailure message:');
    print(failure.message);
    print('\nReproduction blob: ${failure.reproductionBlob}');
  }
}

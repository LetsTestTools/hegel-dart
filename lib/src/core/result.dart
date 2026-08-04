enum RunStatus {
  passed,
  failed,
  error;
  
  // From hegel_run_status_t
  // 0 => PASSED
  // 1 => FAILED
  // 2 => ERROR
}

class Failure {
  final String message;
  final String origin;
  final String reproductionBlob;

  const Failure({
    required this.message,
    required this.origin,
    required this.reproductionBlob,
  });
}

class RunResult {
  final RunStatus status;
  final String? errorMessage;
  final List<Failure> failures;
  final int testCasesRun;

  const RunResult({
    required this.status,
    required this.testCasesRun,
    this.errorMessage,
    this.failures = const [],
  });
}

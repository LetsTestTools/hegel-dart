/// Helpers for extracting failure origins.

/// Extracts a stable origin string from a stack trace.
/// This string identifies *which bug* a failure belongs to.
String extractOrigin(StackTrace stackTrace) {
  // A simple heuristic: grab the first line of the stack trace.
  // Real implementations may want to parse package:stack_trace and return
  // a "file:line" identifier for the failing assertion.
  final lines = stackTrace.toString().split('\n');
  if (lines.isNotEmpty && lines.first.trim().isNotEmpty) {
    return 'Panic at ${lines.first.trim()}';
  }
  return 'Panic at unknown location';
}

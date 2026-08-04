/// Helpers for extracting failure origins.

/// Extracts a stable origin string from a stack trace.
///
/// This identifies *which bug* a failure belongs to by finding the
/// first user-code frame (skipping test framework and hegeltest
/// internal frames).
String extractOrigin(StackTrace stackTrace) {
  final lines = stackTrace.toString().split('\n');

  // Skip frames from test framework internals and hegeltest itself.
  const skipPatterns = [
    'package:test/',
    'package:test_core/',
    'package:test_api/',
    'package:hegeltest/',
    'dart:async',
    'dart:core',
    'dart:isolate',
  ];

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;

    // Check if this frame is from user code
    final isInternal = skipPatterns.any((p) => trimmed.contains(p));
    if (!isInternal) {
      // Parse "file:line:col" pattern from the frame
      // Dart VM format: "#N      FunctionName (file:line:col)"
      // or: "#N      file:line:col"
      final match = RegExp(r'(\S+\.dart[:\s]\d+)').firstMatch(trimmed);
      if (match != null) {
        return match.group(1)!;
      }
      // Fallback: return the raw line
      return trimmed;
    }
  }

  // If every frame was internal, use the first non-empty line
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isNotEmpty) {
      return 'Panic at $trimmed';
    }
  }

  return 'Panic at unknown location';
}

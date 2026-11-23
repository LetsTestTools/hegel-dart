/// Stub implementation for platforms without `dart:ffi` (e.g., web).
library;

Never _unsupported() => throw UnsupportedError(
  'hegeltest requires dart:ffi and is not supported on web. '
  'Use hegeltest only in VM-based test environments (dart test, flutter test on mobile/desktop).',
);

/// Verifies the native `libhegel` asset; throws [UnsupportedError] on web.
void ensureHegelLibraryVerified() => _unsupported();

/// Returns the native `libhegel` version; throws [UnsupportedError] on web.
String hegelNativeVersion() => _unsupported();

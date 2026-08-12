## 0.5.0

- **Breaking**: Minimum Dart SDK bumped to `>=3.10.0` (was `>=3.4.0`)
- **New**: Native Assets integration — `hook/build.dart` registers prebuilt binaries
  automatically. No more manual path resolution.
- Simplified `library_loader.dart` (297 → 125 lines)
- Removed `crypto` dependency (SHA256 runtime verification replaced by ABI version check)
- Added `hooks` and `code_assets` dependencies
- Graceful handling of unsupported targets (returns empty asset list, no build crash)
- `HEGEL_LIBHEGEL_PATH` env override still works (runtime only)

> **Migration**: If on Dart >=3.10.0, just bump to `hegeltest: ^0.5.0`.
> If on Dart <3.10.0, stay on `hegeltest: ^0.4.0` (security fixes only).

## 0.4.0

- **New**: Stateful (model-based) testing — `hegelStatefulTest()`, `StateMachine`, `StateRule`, `StateInvariant`
- **New**: `Pool<T>` for typed value tracking across rules (reusable/consumed draws)
- **New**: Structured preconditions on rules — evaluated before engine selection, not inside rule bodies
- Engine-driven Swarm Testing automatically explores rule subsets
- Automatic shrinking of step sequences to minimal counterexamples

## 0.3.0

- **Security**: SHA256 integrity verification for all bundled native binaries
- **Supply chain**: Bundled `.sha256` checksum files alongside each binary
- Binaries are verified before loading — corrupted/tampered files throw `StateError` with actionable error message

## 0.2.2

- **Fix**: Library loader finds native binary in `flutter test` via `package_config.json` fallback

## 0.2.1

- **API**: Export `HegelRunner` and `loadHegelLibrary` for downstream packages (e.g. `hegeltest_flutter`)
- **DX**: Clean up test imports to use package exports only

## 0.2.0

- **Cross-platform**: Bundled native binaries for Linux x64, Linux arm64, Windows x64, and Windows arm64
- **Safety**: ABI version check on library load — prevents segfaults from mismatched binary versions
- **Upgrade**: Native engine updated to hegel-rust v0.32.2
- **CI**: Tests now run on macOS, Linux, and Windows

## 0.1.2

- **Web compat**: Conditional imports — web projects that import hegeltest compile cleanly (throws `UnsupportedError` at runtime)
- **DX**: `HegelTestFailure` extends `TestFailure` from `package:test_api` — cleaner test output without framework stack traces
- **Fix**: Pre-existing type errors in example and reproduce_test

## 0.1.1

- **Performance**: Cache string generator handles per context (was recompiling regex per draw)
- **Performance**: BigInt byte extraction via bit shifts (was string parsing per draw)
- **Performance**: Replace Arena malloc/free with `reuseBuffer` in all combinators + collections
- **Performance**: Cache `Generator.typeName` (was `runtimeType.toString()` per draw)
- **Performance**: Rewrite tuple generators as direct subclasses (removes double-span + Arena)
- **Fix**: Clone finalizer now frees `_bufferCache` (was leaking FFI pointers on GC)
- **Fix**: BigInt `outLen` bounds check prevents out-of-bounds read
- **Fix**: Blob replay now calls `setUpEach`/`tearDownEach` and wraps body in zone guard
- **Fix**: Late async errors logged to stderr (was silently swallowed)
- **Fix**: `FilteredGenerator` separates predicate rejection from exception in `hadError`
- **Fix**: Collection rejection sets `hadError` correctly before `HegelAssumptionViolated`
- **Fix**: `toString()` safety in counterexample formatting (catches throwing `toString`)
- **Fix**: Surrogate-safe truncation via `runes.take(200)`
- **DX**: `tearDownEach` errors now include full stack trace
- **DX**: `HegelConfig` fields have dartdocs
- **DX**: `where()` accepts `maxAttempts` parameter (default 100)
- **DX**: Reproduce blob validated for NUL bytes before FFI boundary

## 0.1.0

- Initial release
- Core `hegelTest()` integration with `package:test`
- 25+ generators: primitives, text, collections, combinators, temporal, network, bytes
- Generator composition: `map()`, `flatMap()`, `where()`, `Generator.composite()`
- `HegelConfig` for reusable test configuration
- Per-iteration isolation via `setUpEach`/`tearDownEach`
- Counterexample recording with draw log in failure messages
- Reproduction blobs for deterministic failure replay
- Buffer reuse optimization for primitive generators
- Comprehensive dartdocs on all public APIs

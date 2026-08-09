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

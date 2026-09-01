# Contributing to hegeltest

First off, thank you for considering contributing to `hegeltest`! It's people like you that make open source such a great community. We welcome contributions of all kinds, including bug reports, feature requests, documentation improvements, and code changes.

## Development Environment Setup

To set up the project locally:

1. Fork and clone the repository.
2. Run `dart pub get` to fetch dependencies.
3. Run `dart test` to execute the test suite.

### Native Binaries (libhegel)

`hegel-dart` is powered by a native Rust engine (`libhegel`). For Dart-side contributions, **you do not need a Rust toolchain**. The native binaries are bundled with the repository and automatically loaded via FFI.

If you are developing custom native binaries (from `hegeldev/hegel-rust`) and want to test them with `hegel-dart`, you can override the loaded binary by setting the `HEGEL_LIBHEGEL_PATH` environment variable:

```bash
export HEGEL_LIBHEGEL_PATH=/path/to/your/custom/libhegel.so
```

## Making Changes

1. Create a branch for your changes (`git checkout -b feature/amazing-feature`).
2. Make your changes and test them locally.
3. Write tests for any new features or bug fixes. Do not break existing tests!
4. Ensure your code follows the existing style patterns.
5. Format your code using `dart format .`
6. Run static analysis using `dart analyze` and resolve any issues.

## Commit Message Convention

We follow [Conventional Commits](https://www.conventionalcommits.org/):

* `feat:` A new feature
* `fix:` A bug fix
* `docs:` Documentation only changes
* `test:` Adding missing tests or correcting existing tests
* `ci:` Changes to our CI configuration files and scripts
* `chore:` Other changes that don't modify src or test files

Example: `feat: add support for shrinking custom generators`

## Submitting Changes

1. Push your branch to your fork (`git push origin feature/amazing-feature`).
2. Open a Pull Request against the `main` branch.
3. Fill out the PR template.
4. The CI pipeline (GitHub Actions) will automatically run tests across 3 platforms, check formatting, and verify the package can be published.
5. A maintainer will review your PR and provide feedback.

## Need Help?

If you have questions, please open a GitHub Issue or reach out on our [GitHub repository](https://github.com/LetsTestTools/hegel-dart).

Looking for something to work on? Check the issues labeled **"good first issue"**.

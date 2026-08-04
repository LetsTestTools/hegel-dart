# Changelog

## 0.1.0

- Initial release
- Property-based testing powered by libhegel native engine
- Core generators: integers, doubles, booleans, bigIntegers, text, bytes
- Collection generators: lists, sets, maps
- Combinators: oneOf, sampled, nullable, tuples, frequency
- Temporal generators: dates, times, dateTimes
- Network generators: IPv4, IPv6 addresses
- String generators: text, regex, emails, URLs, domains, UUIDs
- Async test body support
- Automatic shrinking to minimal counterexamples
- Failure replay via reproduce blobs
- Integration with package:test

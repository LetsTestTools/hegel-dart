import 'package:hegeltest/hegeltest.dart';
import 'package:hegeltest/src/ffi/span_labels.dart';
import 'package:test/test.dart';

class _CustomIntGenerator extends Generator<int> {
  const _CustomIntGenerator();

  @override
  int generate(TestCase tc) => tc.draw(integers(min: 0, max: 10));
}

class _CustomStringGenerator extends Generator<String> {
  const _CustomStringGenerator();

  @override
  String generate(TestCase tc) => 'fixed';
}

class _LazyGenerator<T> extends Generator<T> {
  late final Generator<T> target;

  @override
  int get spanLabel => target.spanLabel;

  @override
  T generate(TestCase tc) => target.generate(tc);
}

void main() {
  setUpAll(() {
    ensureHegelLibraryVerified();
  });

  group('SpanLabels', () {
    test('fromName is deterministic and distinct across names', () {
      final a1 = SpanLabels.fromName('hegeltest.test.alpha');
      final a2 = SpanLabels.fromName('hegeltest.test.alpha');
      final b = SpanLabels.fromName('hegeltest.test.beta');

      expect(a1, equals(a2));
      expect(a1, isNot(equals(b)));
    });

    test(
      'combine is deterministic, order-sensitive, and handles edge lengths',
      () {
        final a = SpanLabels.fromName('hegeltest.test.a');
        final b = SpanLabels.fromName('hegeltest.test.b');
        final c = SpanLabels.fromName('hegeltest.test.c');
        final d = SpanLabels.fromName('hegeltest.test.d');

        expect(SpanLabels.combine2(a, b), equals(SpanLabels.combine([a, b])));
        expect(
          SpanLabels.combine3(a, b, c),
          equals(SpanLabels.combine([a, b, c])),
        );

        // Order sensitivity
        expect(
          SpanLabels.combine([a, b]),
          isNot(equals(SpanLabels.combine([b, a]))),
        );
        expect(
          SpanLabels.combine([a, b, c]),
          isNot(equals(SpanLabels.combine([a, c, b]))),
        );

        // Single-label combination does not return the label unchanged
        final single = SpanLabels.combine([a]);
        expect(single, equals(SpanLabels.combine([a])));
        expect(single, isNot(equals(a)));

        // Empty label list produces a stable hash
        final empty = SpanLabels.combine([]);
        expect(empty, equals(SpanLabels.combine([])));
        expect(empty, isNot(equals(single)));

        // 4+ label combinations remain deterministic and order-sensitive
        final four1 = SpanLabels.combine([a, b, c, d]);
        final four2 = SpanLabels.combine([a, b, c, d]);
        final fourReordered = SpanLabels.combine([a, b, d, c]);
        expect(four1, equals(four2));
        expect(four1, isNot(equals(fourReordered)));
      },
    );

    test('caller list mutation does not corrupt combine cache', () {
      final a = SpanLabels.fromName('hegeltest.test.mutate_a');
      final b = SpanLabels.fromName('hegeltest.test.mutate_b');
      final c = SpanLabels.fromName('hegeltest.test.mutate_c');
      final d = SpanLabels.fromName('hegeltest.test.mutate_d');

      final mutable = [a, b, c, d];
      final original = SpanLabels.combine(mutable);

      // Mutate list after caching; a fresh call with the original elements must match,
      // while the mutated sequence must produce its own distinct label.
      mutable[3] = a;
      final mutated = SpanLabels.combine(mutable);

      expect(SpanLabels.combine([a, b, c, d]), equals(original));
      expect(mutated, isNot(equals(original)));
      expect(SpanLabels.combine([a, b, c, a]), equals(mutated));
    });
  });

  group('Generator compound spanLabels', () {
    test(
      'collections share labels for identical shapes and differ otherwise',
      () {
        expect(
          lists(integers()).spanLabel,
          equals(lists(integers(min: 0, max: 5)).spanLabel),
        );
        expect(
          lists(integers()).spanLabel,
          isNot(equals(lists(text()).spanLabel)),
        );
        expect(
          lists(lists(integers())).spanLabel,
          isNot(equals(lists(integers()).spanLabel)),
        );

        expect(
          sets(integers()).spanLabel,
          equals(sets(integers(min: 1, max: 10)).spanLabel),
        );
        expect(
          sets(integers()).spanLabel,
          isNot(equals(sets(booleans()).spanLabel)),
        );
        expect(
          lists(integers()).spanLabel,
          isNot(equals(sets(integers()).spanLabel)),
        );

        expect(
          maps(text(), integers()).spanLabel,
          equals(maps(text(maxSize: 5), integers(min: 0)).spanLabel),
        );
        expect(
          maps(text(), integers()).spanLabel,
          isNot(equals(maps(integers(), text()).spanLabel)),
        );
        expect(
          maps(text(), integers()).spanLabel,
          isNot(equals(maps(text(), booleans()).spanLabel)),
        );
      },
    );

    test(
      'tuples, oneOf, frequency, and nullable distinguish component shapes',
      () {
        expect(
          tuples2(integers(), text()).spanLabel,
          equals(tuples2(integers(min: 1), text(maxSize: 3)).spanLabel),
        );
        expect(
          tuples2(integers(), text()).spanLabel,
          isNot(equals(tuples2(text(), integers()).spanLabel)),
        );

        expect(
          tuples3(integers(), text(), booleans()).spanLabel,
          isNot(equals(tuples3(integers(), booleans(), text()).spanLabel)),
        );
        expect(
          tuples4(integers(), text(), booleans(), doubles()).spanLabel,
          isNot(
            equals(
              tuples4(integers(), text(), doubles(), booleans()).spanLabel,
            ),
          ),
        );

        expect(
          oneOf<Object>([integers(), text()]).spanLabel,
          equals(oneOf<Object>([integers(min: 0), text(maxSize: 2)]).spanLabel),
        );
        expect(
          oneOf<Object>([integers(), text()]).spanLabel,
          isNot(equals(oneOf<Object>([text(), integers()]).spanLabel)),
        );

        expect(
          frequency<Object>([(1, integers()), (3, text())]).spanLabel,
          equals(frequency<Object>([(5, integers()), (1, text())]).spanLabel),
        );
        expect(
          frequency<Object>([(1, integers()), (3, text())]).spanLabel,
          isNot(
            equals(frequency<Object>([(1, text()), (3, integers())]).spanLabel),
          ),
        );
        expect(
          frequency<Object>([(1, integers()), (1, text())]).spanLabel,
          isNot(equals(oneOf<Object>([integers(), text()]).spanLabel)),
        );

        expect(
          nullable(integers()).spanLabel,
          isNot(equals(nullable(text()).spanLabel)),
        );
      },
    );

    test('all leaf generators have distinct spanLabels', () {
      final leafLabels = [
        integers().spanLabel,
        doubles().spanLabel,
        booleans().spanLabel,
        bigIntegers().spanLabel,
        bytes().spanLabel,
        text().spanLabel,
        fromRegex('a').spanLabel,
        emails().spanLabel,
        urls().spanLabel,
        domains().spanLabel,
        uuids().spanLabel,
        dates().spanLabel,
        times().spanLabel,
        dateTimes().spanLabel,
        durations().spanLabel,
        ipv4Addresses().spanLabel,
        ipv6Addresses().spanLabel,
      ];

      expect(leafLabels.toSet().length, equals(leafLabels.length));
    });

    test(
      'where, map, flatMap, composite, sampled, and custom subclasses differ appropriately',
      () {
        expect(
          integers().where((x) => x.isEven).spanLabel,
          isNot(equals(text().where((s) => s.isNotEmpty).spanLabel)),
        );
        expect(
          integers().map((x) => x.toString()).spanLabel,
          isNot(equals(integers().map((x) => x * 2).spanLabel)),
        );
        expect(
          integers()
              .flatMap((n) => lists(integers(), maxSize: n.abs() % 5))
              .spanLabel,
          isNot(
            equals(
              integers().flatMap((n) => text(maxSize: n.abs() % 5)).spanLabel,
            ),
          ),
        );
        expect(
          Generator.composite<int>((tc) => tc.draw(integers())).spanLabel,
          isNot(
            equals(
              Generator.composite<String>((tc) => tc.draw(text())).spanLabel,
            ),
          ),
        );

        expect(
          sampled([1, 2, 3]).spanLabel,
          isNot(equals(sampled(['a', 'b']).spanLabel)),
        );
        expect(
          sampledWeighted([(1, 10), (2, 20)]).spanLabel,
          isNot(equals(sampledWeighted([(1, 'a'), (2, 'b')]).spanLabel)),
        );
        expect(
          sampled([1, 2]).spanLabel,
          isNot(equals(sampledWeighted([(1, 1), (1, 2)]).spanLabel)),
        );

        const customInt = _CustomIntGenerator();
        const customStr = _CustomStringGenerator();
        expect(customInt.spanLabel, isNot(equals(customStr.spanLabel)));
        expect(
          customInt.spanLabel,
          equals(const _CustomIntGenerator().spanLabel),
        );
      },
    );

    test(
      'heterogeneous compound generators shrink cleanly without span errors',
      () async {
        final res = await runHegelTest(
          (tc) {
            final ints = tc.draw(
              lists(integers(min: 0, max: 100), maxSize: 10),
              label: 'ints',
            );
            final words = tc.draw(
              lists(text(maxSize: 10), maxSize: 10),
              label: 'words',
            );
            final nested = tc.draw(
              maps(
                text(maxSize: 5),
                lists(integers(min: 0, max: 50), maxSize: 5),
                maxSize: 5,
              ),
              label: 'nested',
            );
            final choice = tc.draw(
              nullable(
                tuples2(
                  integers(min: 0, max: 20).where((v) => v.isEven),
                  doubles(
                    min: 0,
                    max: 10,
                    allowNan: false,
                    allowInfinity: false,
                  ),
                ),
              ),
              label: 'choice',
            );

            if (ints.length >= 2 && words.isNotEmpty && nested.isNotEmpty) {
              expect(choice, isNull); // Deliberately falsified when populated
            }
          },
          seed: 42,
          testCases: 200,
          database: false,
        );

        expect(res.status, equals(RunStatus.failed));
        expect(res.errorKind, equals(RunErrorKind.none));
        expect(res.failures, isNotEmpty);
        final messages = res.failures.map((f) => f.message).toList();
        expect(messages, anyElement(contains('Expected: null')));
        expect(
          messages,
          everyElement(
            allOf(
              isNot(contains('Failed to start span')),
              isNot(contains('Failed to stop span')),
            ),
          ),
        );
      },
    );

    test(
      'mutating caller lists after construction does not alter labels or draws',
      () async {
        final oneOfInputs = <Generator<int>>[integers(min: 1, max: 1)];
        final oneOfGen = oneOf(oneOfInputs);
        final oneOfLabel = oneOfGen.spanLabel;
        oneOfInputs[0] = integers(min: 99, max: 99);
        oneOfInputs.add(integers(min: 50, max: 50));
        expect(oneOfGen.spanLabel, equals(oneOfLabel));

        final freqInputs = <(int, Generator<int>)>[
          (1, integers(min: 2, max: 2)),
        ];
        final freqGen = frequency(freqInputs);
        final freqLabel = freqGen.spanLabel;
        freqInputs[0] = (1, integers(min: 88, max: 88));
        freqInputs.add((100, integers(min: 77, max: 77)));
        expect(freqGen.spanLabel, equals(freqLabel));

        final sampledInputs = <String>['only'];
        final sampledGen = sampled(sampledInputs);
        final sampledLabel = sampledGen.spanLabel;
        sampledInputs[0] = 'mutated';
        sampledInputs.add('extra');
        expect(sampledGen.spanLabel, equals(sampledLabel));

        final weightedInputs = <(int, String)>[(1, 'kept')];
        final weightedGen = sampledWeighted(weightedInputs);
        final weightedLabel = weightedGen.spanLabel;
        weightedInputs[0] = (1, 'changed');
        weightedInputs.add((100, 'added'));
        expect(weightedGen.spanLabel, equals(weightedLabel));

        final runRes = await runHegelTest(
          (tc) {
            expect(tc.draw(oneOfGen), equals(1));
            expect(tc.draw(freqGen), equals(2));
            expect(tc.draw(sampledGen), equals('only'));
            expect(tc.draw(weightedGen), equals('kept'));
          },
          seed: 42,
          testCases: 30,
          database: false,
        );

        expect(runRes.status, equals(RunStatus.passed));
      },
    );

    test(
      'cyclic self-referential generator graphs resolve spanLabel safely and generate values',
      () async {
        final lazyOneOf = _LazyGenerator<Object>();
        lazyOneOf.target = oneOf<Object>([
          integers(min: 0, max: 10),
          lists(lazyOneOf, maxSize: 1),
        ]);

        final lazyFreq = _LazyGenerator<Object>();
        lazyFreq.target = frequency<Object>([
          (4, integers(min: 0, max: 10)),
          (1, lists(lazyFreq, maxSize: 2)),
        ]);

        final label1 = lazyOneOf.spanLabel;
        expect(lazyOneOf.spanLabel, equals(label1));
        final freqLabel = lazyFreq.spanLabel;
        expect(lazyFreq.spanLabel, equals(freqLabel));
        expect(label1, isNot(equals(freqLabel)));

        final res = await runHegelTest(
          (tc) {
            final v1 = tc.draw(lazyOneOf, label: 'cyclicOneOf');
            final v2 = tc.draw(lazyFreq, label: 'cyclicFreq');
            expect(v1, anyOf(isA<int>(), isA<List<Object>>()));
            expect(v2, anyOf(isA<int>(), isA<List<Object>>()));
          },
          seed: 42,
          testCases: 50,
          database: false,
        );

        expect(res.status, equals(RunStatus.passed));
      },
    );
  });
}

import 'package:offline_first_sync_drift/src/changed_fields.dart';
import 'package:test/test.dart';

void main() {
  group('ChangedFieldsTracker', () {
    test('starts with no tracked fields', () {
      final tracker = ChangedFieldsTracker();
      expect(tracker.fields, isEmpty);
      expect(tracker.fieldsOrNull, isNull);
    });

    test('changed() returns the new value', () {
      final tracker = ChangedFieldsTracker();
      final result = tracker.changed<String>('title', from: 'a', to: 'b');
      expect(result, equals('b'));
    });

    test('changed() marks field when from != to', () {
      final tracker = ChangedFieldsTracker();
      tracker.changed<String>('title', from: 'a', to: 'b');
      expect(tracker.fields, equals({'title'}));
    });

    test('changed() does NOT mark field when from == to', () {
      final tracker = ChangedFieldsTracker();
      tracker.changed<String>('title', from: 'same', to: 'same');
      expect(tracker.fields, isEmpty);
    });

    test('changed() treats nulls as equal', () {
      final tracker = ChangedFieldsTracker();
      tracker.changed<String?>('title', from: null, to: null);
      expect(tracker.fields, isEmpty);
    });

    test('changed() detects null -> value transition', () {
      final tracker = ChangedFieldsTracker();
      tracker.changed<String?>('title', from: null, to: 'x');
      expect(tracker.fields, equals({'title'}));
    });

    test('markIf() marks when condition is true', () {
      final tracker = ChangedFieldsTracker();
      tracker.markIf('title', true);
      expect(tracker.fields, equals({'title'}));
    });

    test('markIf() does nothing when condition is false', () {
      final tracker = ChangedFieldsTracker();
      tracker.markIf('title', false);
      expect(tracker.fields, isEmpty);
    });

    test('mark() unconditionally adds a field', () {
      final tracker = ChangedFieldsTracker();
      tracker.mark('title');
      expect(tracker.fields, equals({'title'}));
    });

    test('mark() is idempotent (set semantics)', () {
      final tracker = ChangedFieldsTracker();
      tracker.mark('title');
      tracker.mark('title');
      expect(tracker.fields, hasLength(1));
    });

    test('fields getter returns an unmodifiable set', () {
      final tracker = ChangedFieldsTracker();
      tracker.mark('title');
      expect(() => tracker.fields.add('other'), throwsUnsupportedError);
    });

    test('fieldsOrNull returns the set when non-empty', () {
      final tracker = ChangedFieldsTracker();
      tracker.mark('title');
      expect(tracker.fieldsOrNull, equals({'title'}));
    });

    test('multiple marks accumulate distinct fields', () {
      final tracker = ChangedFieldsTracker();
      tracker.mark('a');
      tracker.changed<int>('b', from: 1, to: 2);
      tracker.markIf('c', true);
      expect(tracker.fields, equals({'a', 'b', 'c'}));
    });
  });

  group('ChangedFieldsDiff.diffMaps', () {
    test('returns empty set for identical maps', () {
      final result = ChangedFieldsDiff.diffMaps(
        {'title': 'x', 'count': 1},
        {'title': 'x', 'count': 1},
      );
      expect(result, isEmpty);
    });

    test('detects scalar value changes', () {
      final result = ChangedFieldsDiff.diffMaps(
        {'title': 'old'},
        {'title': 'new'},
      );
      expect(result, equals({'title'}));
    });

    test('detects added keys', () {
      final result = ChangedFieldsDiff.diffMaps(
        {'a': 1},
        {'a': 1, 'b': 2},
      );
      expect(result, equals({'b'}));
    });

    test('detects removed keys', () {
      final result = ChangedFieldsDiff.diffMaps(
        {'a': 1, 'b': 2},
        {'a': 1},
      );
      expect(result, equals({'b'}));
    });

    test('detects type mismatches (string vs int)', () {
      final result = ChangedFieldsDiff.diffMaps(
        {'val': '1'},
        {'val': 1},
      );
      expect(result, equals({'val'}));
    });

    test('detects null -> value transition', () {
      final result = ChangedFieldsDiff.diffMaps(
        {'val': null},
        {'val': 'x'},
      );
      expect(result, equals({'val'}));
    });

    test('treats null == null as equal', () {
      final result = ChangedFieldsDiff.diffMaps(
        {'val': null},
        {'val': null},
      );
      expect(result, isEmpty);
    });

    test('ignores default ignored fields like id, updatedAt, createdAt', () {
      final result = ChangedFieldsDiff.diffMaps(
        {'id': 'a', 'updatedAt': 't1', 'createdAt': 'c1', 'title': 'x'},
        {'id': 'b', 'updatedAt': 't2', 'createdAt': 'c2', 'title': 'x'},
      );
      expect(result, isEmpty);
    });

    test('honors a custom ignoredFields set', () {
      final result = ChangedFieldsDiff.diffMaps(
        {'title': 'a', 'extra': 'x'},
        {'title': 'b', 'extra': 'y'},
        ignoredFields: {'extra'},
      );
      expect(result, equals({'title'}));
    });

    test('handles empty maps', () {
      final result = ChangedFieldsDiff.diffMaps({}, {});
      expect(result, isEmpty);
    });

    test('treats equal nested maps as unchanged', () {
      final result = ChangedFieldsDiff.diffMaps(
        {
          'meta': {'a': 1, 'b': 2},
        },
        {
          'meta': {'a': 1, 'b': 2},
        },
      );
      expect(result, isEmpty);
    });

    test('detects nested map differences', () {
      final result = ChangedFieldsDiff.diffMaps(
        {
          'meta': {'a': 1, 'b': 2},
        },
        {
          'meta': {'a': 1, 'b': 99},
        },
      );
      expect(result, equals({'meta'}));
    });

    test('detects nested map length differences', () {
      final result = ChangedFieldsDiff.diffMaps(
        {
          'meta': {'a': 1},
        },
        {
          'meta': {'a': 1, 'b': 2},
        },
      );
      expect(result, equals({'meta'}));
    });

    test('treats equal lists as unchanged', () {
      final result = ChangedFieldsDiff.diffMaps(
        {
          'tags': [1, 2, 3],
        },
        {
          'tags': [1, 2, 3],
        },
      );
      expect(result, isEmpty);
    });

    test('detects list length difference', () {
      final result = ChangedFieldsDiff.diffMaps(
        {
          'tags': [1, 2],
        },
        {
          'tags': [1, 2, 3],
        },
      );
      expect(result, equals({'tags'}));
    });

    test('detects list order/element changes', () {
      final result = ChangedFieldsDiff.diffMaps(
        {
          'tags': [1, 2, 3],
        },
        {
          'tags': [3, 2, 1],
        },
      );
      expect(result, equals({'tags'}));
    });

    test('handles deeply nested map+list mixed structures', () {
      final result = ChangedFieldsDiff.diffMaps(
        {
          'meta': {
            'tags': [
              {'name': 'a'},
              {'name': 'b'},
            ],
          },
        },
        {
          'meta': {
            'tags': [
              {'name': 'a'},
              {'name': 'b'},
            ],
          },
        },
      );
      expect(result, isEmpty);
    });

    test('detects difference in a deeply nested leaf', () {
      final result = ChangedFieldsDiff.diffMaps(
        {
          'meta': {
            'tags': [
              {'name': 'a'},
            ],
          },
        },
        {
          'meta': {
            'tags': [
              {'name': 'B'},
            ],
          },
        },
      );
      expect(result, equals({'meta'}));
    });

    test('treats map vs list at same key as different', () {
      final result = ChangedFieldsDiff.diffMaps(
        {
          'val': {'a': 1},
        },
        {
          'val': [1],
        },
      );
      expect(result, equals({'val'}));
    });
  });

  group('ChangedFieldsDiff.diffOrNullMaps', () {
    test('returns null when there are no differences', () {
      final result = ChangedFieldsDiff.diffOrNullMaps(
        {'title': 'x'},
        {'title': 'x'},
      );
      expect(result, isNull);
    });

    test('returns the diff set when there are differences', () {
      final result = ChangedFieldsDiff.diffOrNullMaps(
        {'title': 'a'},
        {'title': 'b'},
      );
      expect(result, equals({'title'}));
    });

    test('returns null when only ignored fields change', () {
      final result = ChangedFieldsDiff.diffOrNullMaps(
        {'id': 'a', 'updatedAt': '1'},
        {'id': 'b', 'updatedAt': '2'},
      );
      expect(result, isNull);
    });
  });

  group('ChangedFieldsDiff NaN handling', () {
    test('diffMaps reports no change for two NaN doubles in the same field', () {
      // Two distinct NaN expressions; without the fix, `identical` may be
      // false and `NaN == NaN` is always false, so this would falsely
      // report a change.
      final before = <String, Object?>{'score': double.nan};
      final after = <String, Object?>{'score': double.nan + 0.0};

      expect(
        ChangedFieldsDiff.diffMaps(before, after, ignoredFields: const {}),
        isEmpty,
      );
      expect(
        ChangedFieldsDiff.diffOrNullMaps(
          before,
          after,
          ignoredFields: const {},
        ),
        isNull,
      );
    });

    test('diffMaps reports change when NaN flips to a real number', () {
      final before = <String, Object?>{'score': double.nan};
      final after = <String, Object?>{'score': 3.14};

      expect(
        ChangedFieldsDiff.diffMaps(before, after, ignoredFields: const {}),
        equals({'score'}),
      );
    });

    test('diffMaps reports change when a real number flips to NaN', () {
      final before = <String, Object?>{'score': 3.14};
      final after = <String, Object?>{'score': double.nan};

      expect(
        ChangedFieldsDiff.diffMaps(before, after, ignoredFields: const {}),
        equals({'score'}),
      );
    });

    test('NaN equality is honored inside nested maps and lists', () {
      final before = <String, Object?>{
        'nested': {
          'value': double.nan,
          'samples': [1.0, double.nan, 2.0],
        },
      };
      final after = <String, Object?>{
        'nested': {
          'value': double.nan + 0.0,
          'samples': [1.0, double.nan + 0.0, 2.0],
        },
      };

      expect(
        ChangedFieldsDiff.diffMaps(before, after, ignoredFields: const {}),
        isEmpty,
      );

      // And a change inside the nested structure is still detected.
      final afterChanged = <String, Object?>{
        'nested': {
          'value': double.nan,
          'samples': [1.0, double.nan, 9.9],
        },
      };
      expect(
        ChangedFieldsDiff.diffMaps(
          before,
          afterChanged,
          ignoredFields: const {},
        ),
        equals({'nested'}),
      );
    });
  });

  group('ChangedFieldsDiff.defaultIgnoredFields', () {
    test('contains the expected system fields', () {
      expect(
        ChangedFieldsDiff.defaultIgnoredFields,
        containsAll(<String>[
          'id',
          'ID',
          'uuid',
          'updatedAt',
          'updated_at',
          'createdAt',
          'created_at',
          'deletedAt',
          'deleted_at',
          'deletedAtLocal',
          'deleted_at_local',
        ]),
      );
    });
  });
}

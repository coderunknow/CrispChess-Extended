// Regression tests for the spaced-repetition interval schedule.
//
// The schedule is documented as 1/3/7/14/30 days. A bug in `markCorrect`
// incremented the interval index *before* using it to schedule the next
// review, so every correct answer scheduled the *next* rung's delay: the
// first correct answer jumped straight to 3 days (the 1-day rung was never
// used after a correct answer) and the whole schedule ran one step ahead.
import 'package:crispchess/chess/spaced_repetition.dart';
import 'package:flutter_test/flutter_test.dart';

/// True when [actual] lies within [expected] ± the tiny window between the
/// [before] and [after] timestamps (the `DateTime.now()` inside `markCorrect`
/// happens between them, so the result must fall in that span).
bool _isScheduledWithin(
    DateTime actual, DateTime before, DateTime after, Duration expected) {
  final lo = before.add(expected);
  final hi = after.add(expected);
  return !actual.isBefore(lo) && !actual.isAfter(hi);
}

void main() {
  group('SrItem.markCorrect schedule', () {
    test('first correct answer schedules the 1-day rung, not 3 days', () {
      final item = SrItem(
        fen: '8/8/8/8/8/8/8/4K3k w - - 0 1',
        solution: 'e1e2',
        description: 'test',
      );
      expect(item.interval, 0);

      final before = DateTime.now();
      item.markCorrect();
      final after = DateTime.now();

      expect(item.interval, 1);
      expect(item.timesCorrect, 1);
      expect(
        _isScheduledWithin(
            item.nextReview, before, after, const Duration(days: 1)),
        isTrue,
        reason:
            'the first correct answer must schedule a 1-day review, not 3 days',
      );
      // And it must be the 1-day rung, not the 3-day rung.
      expect(item.nextReview.difference(before).inDays, 1);
    });

    test('walks the full 1/3/7/14/30-day schedule', () {
      final item = SrItem(
        fen: '8/8/8/8/8/8/8/4K3k w - - 0 1',
        solution: 'e1e2',
        description: 'test',
      );
      const expectedDays = [1, 3, 7, 14, 30];

      for (var i = 0; i < expectedDays.length; i++) {
        final before = DateTime.now();
        item.markCorrect();
        final after = DateTime.now();

        // After the i-th correct answer the interval index is i+1, capped at
        // the last rung (4).
        final expectedInterval = i + 1 > expectedDays.length - 1 ? i : i + 1;
        expect(item.interval, expectedInterval);
        expect(
          _isScheduledWithin(
              item.nextReview, before, after, Duration(days: expectedDays[i])),
          isTrue,
          reason: 'the ' + (i + 1).toString() +
              'th correct answer must schedule ' +
              expectedDays[i].toString() +
              ' days',
        );
      }

      // After completing the last rung the item is learned.
      expect(item.isLearned, isTrue);
    });

    test('an incorrect answer resets to the first rung', () {
      final item = SrItem(
        fen: '8/8/8/8/8/8/8/4K3k w - - 0 1',
        solution: 'e1e2',
        description: 'test',
      );
      item.markCorrect();
      item.markCorrect();
      expect(item.interval, 2);
      expect(item.timesCorrect, 2);

      item.markIncorrect();
      expect(item.interval, 0);
      expect(item.timesCorrect, 0);
      // An incorrect answer re-schedules for 1 day.
      expect(item.nextReview.difference(DateTime.now()).inDays, 1);
    });

    test('a learned item is not due and is filtered out of getDueItems', () {
      final item = SrItem(
        fen: '8/8/8/8/8/8/8/4K3k w - - 0 1',
        solution: 'e1e2',
        description: 'test',
      );
      for (var i = 0; i < 5; i++) {
        item.markCorrect();
      }
      expect(item.isLearned, isTrue);
      expect(getDueItems([item]), isEmpty);
    });
  });
}

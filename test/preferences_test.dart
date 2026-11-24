import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crispchess/services/preferences_service.dart';
import 'package:crispchess/chess/chess_clock.dart';

void main() {
  group('PreferencesService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('returns defaults before init', () {
      final prefs = PreferencesService();
      expect(prefs.engine, 'Built-in');
      expect(prefs.variant, '5m');
      expect(prefs.strengthLevel, 10);
      expect(prefs.animationSpeed, 2);
      expect(prefs.playAsBlack, false);
      expect(prefs.pieceTheme, 'chessnut');
      expect(prefs.soundEnabled, true);
      expect(prefs.showValidMoves, true);
      expect(prefs.timeControl, TimeControl.unlimited);
      expect(prefs.lc0Backend, 'auto');
    });

    test('persists engine choice', () async {
      final prefs = PreferencesService();
      await prefs.init();
      prefs.engine = 'Stockfish';
      expect(prefs.engine, 'Stockfish');
    });

    test('persists Lc0 inference backend', () async {
      final prefs = PreferencesService();
      await prefs.init();
      prefs.lc0Backend = 'dart';
      expect(prefs.lc0Backend, 'dart');
    });

    test('persists strength level', () async {
      final prefs = PreferencesService();
      await prefs.init();
      prefs.strengthLevel = 15;
      expect(prefs.strengthLevel, 15);
    });

    test('persists play as black', () async {
      final prefs = PreferencesService();
      await prefs.init();
      prefs.playAsBlack = true;
      expect(prefs.playAsBlack, true);
    });

    test('persists time control', () async {
      final prefs = PreferencesService();
      await prefs.init();
      prefs.timeControl = TimeControl.blitz5;
      expect(prefs.timeControl, TimeControl.blitz5);
    });

    test('persists piece theme', () async {
      final prefs = PreferencesService();
      await prefs.init();
      prefs.pieceTheme = 'fantasy';
      expect(prefs.pieceTheme, 'fantasy');
    });

    test('resetToDefaults clears everything', () async {
      final prefs = PreferencesService();
      await prefs.init();
      prefs.engine = 'Stockfish';
      prefs.strengthLevel = 20;
      prefs.playAsBlack = true;

      await prefs.resetToDefaults();

      // After reset, should return defaults
      final fresh = PreferencesService();
      await fresh.init();
      expect(fresh.engine, 'Built-in');
      expect(fresh.strengthLevel, 10);
      expect(fresh.playAsBlack, false);
    });

    test('persists variant', () async {
      final prefs = PreferencesService();
      await prefs.init();
      prefs.variant = '79m';
      expect(prefs.variant, '79m');
    });

    test('persists animation speed', () async {
      final prefs = PreferencesService();
      await prefs.init();
      prefs.animationSpeed = 0;
      expect(prefs.animationSpeed, 0);
    });

    test('handles unknown time control gracefully', () async {
      SharedPreferences.setMockInitialValues({'timeControl': 'nonexistent'});
      final prefs = PreferencesService();
      await prefs.init();
      expect(prefs.timeControl, TimeControl.unlimited);
    });
  });

  group('daily login streak', () {
    String ymd(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    test('a consecutive-day login extends the streak', () async {
      final now = DateTime.now();
      SharedPreferences.setMockInitialValues({
        'lastLoginDate': ymd(DateTime(now.year, now.month, now.day - 1)),
        'dailyStreak': 3,
        'totalXp': 100,
      });
      final prefs = PreferencesService();
      await prefs.init();
      final xp = prefs.checkDailyLogin();
      expect(prefs.dailyStreak, 4, reason: 'yesterday + today is consecutive');
      expect(xp, 9, reason: '5 + min(streak, 10)');
      expect(prefs.totalXp, 109);
    });

    test('a two-day gap resets the streak', () async {
      final now = DateTime.now();
      SharedPreferences.setMockInitialValues({
        'lastLoginDate': ymd(DateTime(now.year, now.month, now.day - 2)),
        'dailyStreak': 3,
        'totalXp': 100,
      });
      final prefs = PreferencesService();
      await prefs.init();
      final xp = prefs.checkDailyLogin();
      expect(prefs.dailyStreak, 1);
      expect(xp, 5);
      expect(prefs.totalXp, 105);
    });

    test('a corrupt login date resets instead of throwing', () async {
      SharedPreferences.setMockInitialValues({
        'lastLoginDate': 'not-a-date',
        'dailyStreak': 7,
        'totalXp': 50,
      });
      final prefs = PreferencesService();
      await prefs.init();
      expect(prefs.checkDailyLogin(), 5);
      expect(prefs.dailyStreak, 1);
    });

    test('same-day login earns nothing', () async {
      final today = ymd(DateTime.now());
      SharedPreferences.setMockInitialValues({
        'lastLoginDate': today,
        'dailyStreak': 4,
        'totalXp': 10,
      });
      final prefs = PreferencesService();
      await prefs.init();
      expect(prefs.checkDailyLogin(), 0);
      expect(prefs.dailyStreak, 4);
    });

    test('consecutiveDayGap is calendar-exact, not clock-dependent', () {
      // An evening "now" is still one calendar day after the stored date —
      // the case the old UTC-midnight-vs-local difference got wrong in
      // negative offsets.
      expect(PreferencesService.consecutiveDayGap(
          '2026-11-22', DateTime(2026, 11, 23, 20, 30)), 1);
      expect(PreferencesService.consecutiveDayGap(
          '2026-11-22', DateTime(2026, 11, 23, 0, 5)), 1);
      expect(PreferencesService.consecutiveDayGap(
          '2026-11-22', DateTime(2026, 11, 24, 9)), 2);
      expect(PreferencesService.consecutiveDayGap(
          '2026-11-25', DateTime(2026, 11, 23)), -2,
          reason: 'a future stored date is not a consecutive day');
      expect(PreferencesService.consecutiveDayGap(
          'garbage', DateTime(2026, 11, 23)), isNull);
      expect(
          PreferencesService.consecutiveDayGap(null, DateTime(2026, 11, 23)),
          isNull);
    });

    test('consecutiveDayGap rejects impossible calendar dates', () {
      final now = DateTime(2026, 11, 23);

      // Valid ordinary date.
      expect(
          PreferencesService.consecutiveDayGap('2026-11-22', now), 1);
      // Valid leap-year date: not rejected, returns a negative gap.
      final leapGap = PreferencesService.consecutiveDayGap(
          '2024-02-29', DateTime(2026, 11, 23));
      expect(leapGap, isNotNull, reason: '2024-02-29 is a valid leap date');
      expect(leapGap, lessThan(0),
          reason: '2024-02-29 is before 2026-11-23');

      // Impossible dates must be rejected, not normalized into the next month.
      expect(
          PreferencesService.consecutiveDayGap('2025-02-29', now), isNull,
          reason: '2025 is not a leap year');
      expect(
          PreferencesService.consecutiveDayGap('2026-02-30', now), isNull,
          reason: 'February has no 30th');
      expect(
          PreferencesService.consecutiveDayGap('2026-04-31', now), isNull,
          reason: 'April has no 31st');
      expect(
          PreferencesService.consecutiveDayGap('2026-00-10', now), isNull,
          reason: 'month zero');
      expect(
          PreferencesService.consecutiveDayGap('2026-13-10', now), isNull,
          reason: 'month thirteen');
      expect(
          PreferencesService.consecutiveDayGap('2026-11-00', now), isNull,
          reason: 'day zero');
      expect(
          PreferencesService.consecutiveDayGap('2026-11-32', now), isNull,
          reason: 'day thirty-two');
      // Out of range year cannot construct a DateTime.
      expect(
          PreferencesService.consecutiveDayGap('0001-01-01', now)! < 0, isTrue);
    });
  });
}
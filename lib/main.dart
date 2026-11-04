import 'dart:async';

import 'package:flutter/material.dart';
import 'l10n/generated/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'engines/engine_storage.dart';
import 'screens/chess_game_screen.dart';

/// Global theme notifier — settings screen updates this, app rebuilds.
final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

/// Global locale notifier — null means system default.
final localeNotifier = ValueNotifier<Locale?>(null);

void main() {
  Logger.root.level = Level.WARNING;
  Logger.root.onRecord.listen((record) {
    debugPrint('${record.level.name}: ${record.time}: ${record.message}');
  });

  // Load saved theme and locale before app starts
  SharedPreferences.getInstance().then((prefs) {
    final theme = prefs.getString('themeMode') ?? 'system';
    themeNotifier.value = switch (theme) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };
    final lang = prefs.getString('locale');
    if (lang != null && lang != 'system') {
      localeNotifier.value = Locale(lang);
    }
  });

  // Finish an interrupted engine-storage move before anything reads the root,
  // otherwise the engines are looked up in a root that only half exists. This
  // is deliberately not awaited: a slow copy must not delay the first frame, and
  // `resumeMigration` is a no-op when there is nothing to finish.
  unawaited(_finishInterruptedStorageMigration());

  runApp(const CrispChessApp());
}

class CrispChessApp extends StatelessWidget {
  const CrispChessApp({super.key, this.fontFamily, this.fontFamilyFallback});

  final String? fontFamily;

  /// Fonts for glyphs [fontFamily] lacks (the store screenshots' font has no
  /// chess symbols). Null in the app, which uses the platform's fallbacks.
  final List<String>? fontFamilyFallback;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, themeMode, _) {
        return ValueListenableBuilder<Locale?>(
          valueListenable: localeNotifier,
          builder: (context, locale, _) {
        return MaterialApp(
          title: 'CrispChess',
          debugShowCheckedModeBanner: false,
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en'),
            Locale('de'),
          ],
          theme: ThemeData(
            colorSchemeSeed: Colors.brown,
            brightness: Brightness.light,
            useMaterial3: true,
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback,
          ),
          darkTheme: ThemeData(
            colorSchemeSeed: Colors.brown,
            brightness: Brightness.dark,
            useMaterial3: true,
            scaffoldBackgroundColor: Colors.black,
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback,
          ),
          themeMode: themeMode,
          home: const ChessGameScreen(),
        );
          },
        );
      },
    );
  }
}

/// Completes a storage move that a crash or a closed app interrupted.
///
/// Failure is logged rather than surfaced: the app is usable in either root,
/// the old tree is never deleted, and the next launch tries again.
Future<void> _finishInterruptedStorageMigration() async {
  try {
    final resumed = await EngineStorage.shared.resumeMigration();
    if (resumed != null && resumed.complete) {
      debugPrint('engine storage: finished interrupted move '
          '(${resumed.moved} copied)');
    }
  } catch (error) {
    debugPrint('engine storage: interrupted move could not be finished: $error');
  }
}

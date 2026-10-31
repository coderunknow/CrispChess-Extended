// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'CrispChess';

  @override
  String get yourTurn => 'Du bist dran';

  @override
  String get whiteToMove => 'Weiß am Zug';

  @override
  String get blackToMove => 'Schwarz am Zug';

  @override
  String get thinking => 'Denkt nach...';

  @override
  String get engineError => 'Engine-Fehler';

  @override
  String loading(Object engineName) {
    return 'Lade $engineName...';
  }

  @override
  String get downloading => 'Wird heruntergeladen...';

  @override
  String engineReady(Object engineName) {
    return '$engineName bereit';
  }

  @override
  String engineThinking(Object engineName) {
    return '$engineName denkt nach...';
  }

  @override
  String get newGame => 'Neue Partie';

  @override
  String get newGameConfirm => 'Die aktuelle Partie geht verloren.';

  @override
  String get settings => 'Einstellungen';

  @override
  String get about => 'Über';

  @override
  String get aboutCrispChess => 'Über CrispChess';

  @override
  String get puzzles => 'Aufgaben';

  @override
  String get flipBoard => 'Brett drehen';

  @override
  String get copyPgn => 'PGN kopieren';

  @override
  String get pastePgn => 'PGN einfügen';

  @override
  String get loadFen => 'FEN laden';

  @override
  String get setupPosition => 'Stellung aufbauen';

  @override
  String get pgnDatabase => 'PGN-Datenbank';

  @override
  String get offerDraw => 'Remis anbieten';

  @override
  String get resign => 'Aufgeben';

  @override
  String resignConfirm(Object engineName) {
    return '$engineName gewinnt durch Aufgabe.';
  }

  @override
  String drawDeclined(Object engineName) {
    return '$engineName lehnt das Remisangebot ab.';
  }

  @override
  String get drawAgreed => 'Remis vereinbart';

  @override
  String get youResigned => 'Du hast aufgegeben';

  @override
  String get gameResumed => 'Partie fortgesetzt';

  @override
  String get resumeGame => 'Partie fortsetzen?';

  @override
  String savedGameMoves(Object count) {
    return 'Du hast eine gespeicherte Partie ($count Züge).';
  }

  @override
  String get discard => 'Verwerfen';

  @override
  String get resume => 'Fortsetzen';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get review => 'Analyse';

  @override
  String get undo => 'Rückgängig';

  @override
  String get redo => 'Wiederholen';

  @override
  String get hint => 'Hinweis';

  @override
  String get analyze => 'Analysieren';

  @override
  String get abort => 'Abbrechen';

  @override
  String get playAsWhite => 'Weiß';

  @override
  String get playAsBlack => 'Schwarz';

  @override
  String get playAsRandom => 'Zufall';

  @override
  String get twoPlayer => 'Zwei Spieler (lokal)';

  @override
  String get passAndPlay => 'Abwechselnd spielen';

  @override
  String get playAs => 'Spielen als';

  @override
  String get chessEngine => 'Schach-Engine';

  @override
  String get opponentStrength => 'Gegnerstärke';

  @override
  String get hintDepth => 'Analysetiefe';

  @override
  String analysisDepth(Object depth) {
    return 'Analysetiefe: $depth';
  }

  @override
  String get hintEngine => 'Hinweis-Engine';

  @override
  String get sameAsOpponent => 'Wie Gegner';

  @override
  String get game => 'Partie';

  @override
  String get showValidMoves => 'Gültige Züge anzeigen';

  @override
  String get showValidMovesSubtitle =>
      'Legale Züge hervorheben bei Figurenauswahl';

  @override
  String get allowUndo => 'Rückgängig erlauben';

  @override
  String get allowUndoSubtitle => 'Für Disziplin deaktivieren';

  @override
  String get solidBlackPieces => 'Schwarze Figuren einfarbig';

  @override
  String get solidBlackPiecesSubtitle =>
      'Schwarze Figuren als reines Schwarz statt grauem Farbverlauf';

  @override
  String get animationSpeed => 'Animationsgeschwindigkeit';

  @override
  String get instant => 'Sofort';

  @override
  String get fast => 'Schnell';

  @override
  String get normal => 'Normal';

  @override
  String get slow => 'Langsam';

  @override
  String get timeControl => 'Zeitkontrolle';

  @override
  String get playAsBlackSetting => 'Als Schwarz spielen';

  @override
  String get playAsBlackSubtitle => 'Engine macht den ersten Zug';

  @override
  String get pieceStyle => 'Figurenstil';

  @override
  String get theme => 'Design';

  @override
  String get language => 'Sprache';

  @override
  String get systemDefault => 'Systemstandard';

  @override
  String get system => 'System';

  @override
  String get light => 'Hell';

  @override
  String get darkAmoled => 'Dunkel (AMOLED)';

  @override
  String get resetToDefaults => 'Auf Standard zurücksetzen';

  @override
  String get save => 'Speichern';

  @override
  String get pgnCopied => 'PGN in Zwischenablage kopiert';

  @override
  String get pgnLoaded => 'PGN geladen';

  @override
  String get invalidPgn => 'Ungültiges PGN';

  @override
  String get noPgnInClipboard => 'Kein PGN in der Zwischenablage';

  @override
  String get noMovesYet => 'Noch keine Züge';

  @override
  String get solved => 'gelöst';

  @override
  String get showSolution => 'Lösung zeigen';

  @override
  String get nextPuzzle => 'Nächste Aufgabe';

  @override
  String get skip => 'Überspringen';

  @override
  String wrongMove(Object remaining) {
    return 'Falscher Zug. Nochmal versuchen. ($remaining übrig)';
  }

  @override
  String get puzzleSolved => 'Richtig! Aufgabe gelöst.';

  @override
  String get findNextMove => 'Richtig! Finde den nächsten Zug.';

  @override
  String get gameSummary => 'Partieübersicht';

  @override
  String get yourAccuracy => 'Deine Genauigkeit';

  @override
  String get accuracy => 'Genauigkeit';

  @override
  String get good => 'Gut';

  @override
  String get mistakes => 'Fehler';

  @override
  String get myMistakes => 'Meine Fehler';

  @override
  String get blunders => 'Patzer';

  @override
  String get evaluation => 'Bewertung';

  @override
  String get yourBestMove => 'Dein bester Zug';

  @override
  String get biggestMistake => 'Größter Fehler';

  @override
  String get moves => 'Züge';

  @override
  String get tapToViewPosition => 'Tippe um Stellung zu sehen';

  @override
  String moveN(Object n) {
    return 'Zug $n';
  }

  @override
  String get welcome => 'Willkommen bei CrispChess';

  @override
  String get welcomeSubtitle =>
      'Spiele Schach gegen KI-Engines oder einen Freund.';

  @override
  String get letsPlay => 'Los geht\'s!';

  @override
  String get switchToBuiltIn => 'Zu Built-in wechseln';

  @override
  String failedToInitialize(Object engineName) {
    return '$engineName: Initialisierung fehlgeschlagen';
  }

  @override
  String get checkmate => 'Schachmatt';

  @override
  String get stalemate => 'Patt';

  @override
  String get drawThreefold => 'Remis — dreifache Stellungswiederholung';

  @override
  String get drawInsufficient => 'Remis — ungenügendes Material';

  @override
  String get drawFiftyMove => 'Remis — 50-Züge-Regel';

  @override
  String get resignation => 'Aufgabe';

  @override
  String get drawByAgreement => 'Remis durch Vereinbarung';

  @override
  String get gameOver => 'Partie beendet';

  @override
  String get boardScreenshot => 'Brett-Screenshot';

  @override
  String get clearAnnotations => 'Markierungen löschen';

  @override
  String get bookmarkPosition => 'Stellung merken';

  @override
  String get positionBookmarked => 'Stellung gespeichert';

  @override
  String get askCoach => 'Coach fragen';

  @override
  String get drills => 'Übungen';

  @override
  String get engineVsEngine => 'Engine vs Engine';

  @override
  String get stats => 'Statistik';

  @override
  String get statsAndAchievements => 'Statistik & Erfolge';

  @override
  String get achievements => 'Erfolge';

  @override
  String get games => 'Partien';

  @override
  String get wins => 'Siege';

  @override
  String get badges => 'Abzeichen';

  @override
  String get engineManager => 'Engine-Verwaltung';

  @override
  String get engineManagerSubtitle =>
      'Engine-Verwaltung — UCI-Engines hinzufügen';

  @override
  String get addEngine => 'Engine hinzufügen';

  @override
  String get addUciEngine => 'UCI-Engine hinzufügen';

  @override
  String get engineBinaryPath => 'Engine-Dateipfad';

  @override
  String get displayName => 'Anzeigename (optional)';

  @override
  String get leaveBlankAutoDetect => 'Leer lassen für Autoerkennung';

  @override
  String get add => 'Hinzufügen';

  @override
  String get remove => 'Entfernen';

  @override
  String get configure => 'Konfigurieren';

  @override
  String get probingEngine => 'Engine wird geprüft...';

  @override
  String engineAdded(Object name) {
    return 'Hinzugefügt: $name';
  }

  @override
  String engineInitFailed(Object error) {
    return 'Engine-Initialisierung fehlgeschlagen: $error';
  }

  @override
  String get loadingEngineOptions => 'Engine-Optionen werden geladen...';

  @override
  String get noCustomEngines => 'Keine eigenen Engines';

  @override
  String get noCustomEnginesSubtitle =>
      'Füge eine UCI-kompatible Schach-Engine\nüber den Dateipfad hinzu.';

  @override
  String get removeEngine => 'Engine entfernen?';

  @override
  String removeEngineConfirm(Object name) {
    return '\"$name\" aus der Engine-Liste entfernen?';
  }

  @override
  String get noConfigurableOptions => 'Keine konfigurierbaren Optionen';

  @override
  String get reset => 'Zurücksetzen';

  @override
  String get run => 'Ausführen';

  @override
  String rangeMinMax(Object min, Object max) {
    return 'Bereich: $min – $max';
  }

  @override
  String get positionEditor => 'Stellungseditor';

  @override
  String get startingPosition => 'Anfangsstellung';

  @override
  String get clearBoard => 'Brett leeren';

  @override
  String get sideToMove => 'Am Zug:';

  @override
  String get castling => 'Rochade:';

  @override
  String get copyFen => 'FEN kopieren';

  @override
  String get fenCopied => 'FEN kopiert';

  @override
  String get loadPosition => 'Stellung laden';

  @override
  String get invalidFen => 'Ungültiger FEN-String';

  @override
  String get positionLoaded => 'Stellung aus FEN geladen';

  @override
  String get customPositionLoaded => 'Eigene Stellung geladen';

  @override
  String get pawnsOnEdgeRank =>
      'Bauern können nicht auf der ersten oder letzten Reihe stehen';

  @override
  String get needOneWhiteKing => 'Weiß muss genau einen König haben';

  @override
  String get needOneBlackKing => 'Schwarz muss genau einen König haben';

  @override
  String get pasteFenHint => 'FEN-String einfügen...';

  @override
  String get pasteFromClipboard => 'Aus Zwischenablage einfügen';

  @override
  String get load => 'Laden';

  @override
  String get databaseStatistics => 'Datenbankstatistik';

  @override
  String nGames(Object count) {
    return '$count Partien';
  }

  @override
  String get results => 'Ergebnisse';

  @override
  String get whiteWins => 'Weiß gewinnt';

  @override
  String get blackWins => 'Schwarz gewinnt';

  @override
  String get draws => 'Remis';

  @override
  String get topOpenings => 'Häufigste Eröffnungen (ECO)';

  @override
  String get mostActivePlayers => 'Aktivste Spieler';

  @override
  String get close => 'Schließen';

  @override
  String get noDatabaseLoaded => 'Keine Datenbank geladen';

  @override
  String get noDatabaseSubtitle =>
      'Kopiere eine PGN-Datei mit mehreren Partien\nin die Zwischenablage, dann tippe auf Einfügen.';

  @override
  String get searchByPlayer => 'Nach Spieler suchen...';

  @override
  String get result => 'Ergebnis';

  @override
  String get all => 'Alle';

  @override
  String get draw => 'Remis';

  @override
  String get noGamesFound => 'Keine Partien im PGN gefunden';

  @override
  String get noPgnData => 'Keine PGN-Daten in der Zwischenablage';

  @override
  String get gameLoadedFromDb => 'Partie aus Datenbank geladen';

  @override
  String get match => 'Duell';

  @override
  String get tournament => 'Turnier';

  @override
  String get selectTwoDifferent => 'Wähle zwei verschiedene Engines';

  @override
  String get selectAtLeast3 => 'Mindestens 3 Engines auswählen';

  @override
  String selectEngines(Object count) {
    return 'Engines auswählen ($count gewählt, min. 3):';
  }

  @override
  String get depth => 'Tiefe';

  @override
  String get startMatch => 'Duell starten';

  @override
  String get startTournament => 'Turnier starten';

  @override
  String get stopped => 'Gestoppt';

  @override
  String get vs => 'gegen';

  @override
  String get multiEngineAnalysis => 'Multi-Engine-Analyse';

  @override
  String get multiEngine => 'Multi-Engine';

  @override
  String get stopMultiEngine => 'Multi-Engine stoppen';

  @override
  String get selectEnginesToCompare => 'Engines zum Vergleichen auswählen:';

  @override
  String get currentOpponent => '(aktueller Gegner)';

  @override
  String get start => 'Start';

  @override
  String multiEngineFailed(Object error) {
    return 'Multi-Engine fehlgeschlagen: $error';
  }

  @override
  String get reAnalyze => 'Neu analysieren';

  @override
  String get tapRefreshToAnalyze => 'Tippe auf Aktualisieren';

  @override
  String get engineLoading => 'Engine lädt...';

  @override
  String bestMove(Object move) {
    return 'Bester Zug: $move';
  }

  @override
  String get analysis => 'Analyse';

  @override
  String get engineNotReady => 'Engine nicht bereit';

  @override
  String get positionRestored => 'Stellung wiederhergestellt';

  @override
  String get resignQuestion => 'Aufgeben?';

  @override
  String dailyLogin(Object xp, Object streak) {
    return 'Täglicher Login: +$xp XP (Serie: $streak)';
  }

  @override
  String get levelUp => 'Aufstieg!';

  @override
  String youReached(Object level) {
    return 'Du hast $level erreicht!';
  }

  @override
  String get continueButton => 'Weiter';

  @override
  String get couldNotCaptureBoard => 'Brett konnte nicht erfasst werden';

  @override
  String boardCaptured(Object size) {
    return 'Brett erfasst ($size KB)';
  }

  @override
  String screenshotFailed(Object error) {
    return 'Screenshot fehlgeschlagen: $error';
  }

  @override
  String get illegalMove => 'Ungültiger Zug!';

  @override
  String premove(Object move) {
    return 'Vorzug: $move';
  }

  @override
  String get premoveIllegal => 'Vorzug ungültig — du bist dran';

  @override
  String get drillComplete => 'Übung abgeschlossen!';

  @override
  String correctOnFirstTry(Object correct, Object total) {
    return '$correct / $total beim ersten Versuch richtig';
  }

  @override
  String get done => 'Fertig';

  @override
  String stepOf(Object current, Object total) {
    return 'Schritt $current von $total';
  }

  @override
  String get next => 'Weiter';

  @override
  String get finish => 'Beenden';

  @override
  String get findBestMove => 'Finde den besten Zug.';

  @override
  String get correct => 'Richtig!';

  @override
  String get notQuiteTryAgain => 'Nicht ganz — versuche es nochmal!';

  @override
  String get aiCoach => 'KI-Coach';

  @override
  String get privacy => 'Datenschutz';

  @override
  String get privacyNotice =>
      'Dein API-Schlüssel wird nur lokal auf deinem Gerät gespeichert. Partiedaten (FEN/PGN) werden direkt an deinen KI-Anbieter gesendet. CrispChess speichert, protokolliert oder überträgt keine Daten an eigene Server. Du kannst deinen API-Schlüssel jederzeit löschen.';

  @override
  String get enterApiKey => 'Gib deinen API-Schlüssel ein:';

  @override
  String keyConfigured(Object provider) {
    return '$provider-Schlüssel konfiguriert';
  }

  @override
  String get removeKey => 'Schlüssel entfernen';

  @override
  String get noMistakesYet => 'Noch keine Fehler erfasst!';

  @override
  String get noMistakesSubtitle =>
      'Spiele Partien mit Analyse, um Patzer zu verfolgen.';

  @override
  String get clearAll => 'Alle löschen';

  @override
  String get unknownMove => 'Unbekannter Zug';

  @override
  String get serviceProvider => 'Dienstanbieter';

  @override
  String get license => 'Lizenz';

  @override
  String get chessEngines => 'Schach-Engines';

  @override
  String get privacyPolicy => 'Datenschutzrichtlinie';

  @override
  String get disclaimer => 'Haftungsausschluss';

  @override
  String get sourceCode => 'Quellcode';

  @override
  String get urlCopied => 'URL in Zwischenablage kopiert';

  @override
  String get contributionsWelcome =>
      'Beiträge willkommen. Bitte zuerst ein Issue eröffnen.';

  @override
  String get openSourceLicenses => 'Open-Source-Lizenzen';

  @override
  String get hintsAndAnalysis => 'Hinweise & Analyse';

  @override
  String get maia3Model => 'Maia3-Modell';

  @override
  String get stockfishVersion => 'Stockfish-Version';

  @override
  String get lynxBuild => 'Lynx-Variante';

  @override
  String get lynxBuildNote =>
      'Die Engine wird einmal pro Seite geladen; eine Änderung wirkt nach dem Neuladen.';

  @override
  String get maiaWeight => 'Maia-Gewicht (ELO-Stufe)';

  @override
  String get gameMode => 'Spielmodus';

  @override
  String get standard => 'Standard';

  @override
  String get kingOfTheHill => 'König des Hügels';

  @override
  String get threeCheck => 'Drei-Schach';

  @override
  String get customTimeControl => 'Benutzerdefiniert...';

  @override
  String get boardColorThemeLabel => 'Brettfarbe';

  @override
  String get notationStyleLabel => 'Notation';

  @override
  String get blindfoldMode => 'Blindfold-Modus';

  @override
  String get blindfoldModeSubtitle =>
      'Figuren ausblenden — aus dem Gedächtnis spielen';

  @override
  String get importExport => 'Import / Export';

  @override
  String get boardToolsMenu => 'Brett-Werkzeuge';

  @override
  String get learnMenu => 'Lernen';

  @override
  String get progressMenu => 'Fortschritt';

  @override
  String get openingExplorer => 'Eröffnungsexplorer';

  @override
  String get coordinateTrainer => 'Koordinatentrainer';

  @override
  String get gameHistory => 'Partieverlauf';

  @override
  String get humanLens => 'Human Lens';

  @override
  String humanLensSubtitle(Object elo) {
    return 'Wie Spieler mit $elo diese Stellung sehen';
  }

  @override
  String get humanLensLoading =>
      'Maia wird geladen (25 MB, nur beim ersten Mal)…';

  @override
  String get humanLensThinking => 'Die Spieler werden befragt…';

  @override
  String get humanLensBestMove => 'Zug der Engine';

  @override
  String humanLensFoundBy(Object percent, Object elo) {
    return '$percent % der Spieler mit $elo finden ihn';
  }

  @override
  String humanLensNaturalFrom(Object elo) {
    return 'Ab etwa $elo findet ihn die Mehrheit';
  }

  @override
  String get humanLensNeverNatural =>
      'Selbst mit 2300 übersieht ihn die Mehrheit';

  @override
  String get humanLensTrap => 'Falle';

  @override
  String humanLensTrapText(Object percent, Object elo, Object move) {
    return '$percent % der Spieler mit $elo spielen $move, und das ist ein Fehler.';
  }

  @override
  String humanLensCandidates(Object elo) {
    return 'Was Spieler mit $elo spielen';
  }

  @override
  String get humanLensByRating => 'Wer den Engine-Zug findet';

  @override
  String get humanLensUnsupported =>
      'Human Lens gibt es nur für Standardschach.';

  @override
  String get humanLensGameOver =>
      'Die Partie ist vorbei, es gibt keine Züge mehr.';

  @override
  String humanLensError(Object error) {
    return 'Human Lens fehlgeschlagen: $error';
  }

  @override
  String get findabilityObvious => 'Naheliegend';

  @override
  String get findabilityNatural => 'Natürlich';

  @override
  String get findabilityFindable => 'Auffindbar';

  @override
  String get findabilityHard => 'Schwer';

  @override
  String get findabilityVeryHard => 'Sehr schwer';

  @override
  String get humanReview => 'Menschliche Analyse';

  @override
  String get humanReviewIntro =>
      'Sieh die Partie so, wie Maia menschliche Spieler sieht: welche Fehler schwer zu vermeiden waren, welche Patzer waren und welcher Wertung deine Züge ähneln.';

  @override
  String get humanReviewStart => 'Mit Maia analysieren';

  @override
  String humanReviewProgress(Object done, Object total) {
    return 'Zug $done von $total…';
  }

  @override
  String humanReviewPlayedLike(Object elo) {
    return 'Deine Züge ähneln einem Spieler mit etwa $elo';
  }

  @override
  String get humanReviewHardMiss => 'Schwer zu finden';

  @override
  String get humanReviewSlip => 'Patzer';

  @override
  String humanReviewMissText(
      Object played, Object best, Object percent, Object elo) {
    return '$played statt $best: $percent % der Spieler mit $elo finden ihn';
  }

  @override
  String get humanReviewNoMistakes => 'Keine teuren Fehler in dieser Partie.';

  @override
  String get humanReviewRatingLabel => 'Vergleich mit Spielern mit';

  @override
  String get scanBoard => 'Brett scannen';

  @override
  String get scanBoardHint =>
      'Wähle ein Bild: einen Screenshot oder ein Buchdiagramm (Diagramm) oder ein Foto eines echten Bretts (Foto).';

  @override
  String get scanPickImage => 'Bild wählen';

  @override
  String get scanRecognizing => 'Erkenne…';

  @override
  String get scanNoBoard =>
      'Kein Schachbrett gefunden. Ziehe auf dem Bild ein Quadrat um das Brett.';

  @override
  String get scanDragHint =>
      'Falscher Bereich? Ziehe auf dem Bild ein Quadrat um das Brett.';

  @override
  String scanUncertain(Object count) {
    return '$count unsichere Felder sind markiert. Bitte prüfen.';
  }

  @override
  String scanProblems(Object problems) {
    return 'Stellung prüfen: $problems';
  }

  @override
  String get scanUsePosition => 'Stellung übernehmen';

  @override
  String scanFailed(Object error) {
    return 'Bild konnte nicht gelesen werden: $error';
  }

  @override
  String get engine => 'Engine';

  @override
  String get rating => 'Wertung';

  @override
  String get ghostTitle => 'Dein Geist';

  @override
  String get ghostDescription =>
      'Spielt deine Eröffnungen, danach wie ein Spieler deiner Wertung';

  @override
  String ghostGames(Object games, Object positions) {
    return 'Aus $games deiner Partien, $positions Eröffnungsstellungen';
  }

  @override
  String get ghostNoGames =>
      'Spiele zuerst ein paar Partien: Der Geist lernt aus deinem Partieverlauf.';

  @override
  String ghostRating(Object elo) {
    return 'Spielt wie: $elo';
  }

  @override
  String get ghostRatingUnmeasured =>
      'Wertung noch nicht gemessen (spielt wie 1500)';

  @override
  String get ghostMeasure => 'Meine Wertung messen';

  @override
  String ghostMeasuring(Object done, Object total) {
    return 'Lese deine Züge… $done von $total';
  }

  @override
  String ghostFavourite(Object moves) {
    return 'Deine liebsten ersten Züge: $moves';
  }

  @override
  String get scanModeDiagram => 'Diagramm';

  @override
  String get scanModePhoto => 'Foto';

  @override
  String get scanPhotoHint =>
      'Fotografiere das ganze Brett von der Seite eines Spielers, mit sichtbaren Linien. Am besten mit Standard-Turnierfiguren.';

  @override
  String get scanPhotoNoBoard =>
      'Kein Brett gefunden. Fotografiere das ganze Brett mit sichtbaren Linien.';

  @override
  String get scanRotate => '90° drehen';

  @override
  String get scanOrientationUnsure =>
      'Ausrichtung prüfen: drehen, bis Weiß unten steht.';

  @override
  String get voiceMove => 'Zug ansagen (V)';

  @override
  String get voiceListening =>
      'Ich höre zu — sag deinen Zug und tippe dann aufs Mikrofon';

  @override
  String get voiceRecognizing => 'Erkenne…';

  @override
  String voiceLoading(Object mb) {
    return 'Lade das Sprachmodell ($mb MB, einmalig)…';
  }

  @override
  String get voiceNoMove => 'Kein Zug erkannt — versuch es noch einmal';

  @override
  String voiceHeard(Object move) {
    return 'Verstanden: $move';
  }

  @override
  String get voiceWhichMove => 'Welchen Zug meintest du?';

  @override
  String voiceFailed(Object error) {
    return 'Spracheingabe fehlgeschlagen: $error';
  }

  @override
  String get engineLab => 'Engine-Labor';

  @override
  String get engineLabSubtitle => 'Engines benchmarken, Ergebnisse behalten und Versionen vergleichen';

  @override
  String get engineLabDashboard => 'Übersicht';

  @override
  String get engineLabBenchmark => 'Benchmark';

  @override
  String get engineLabLeaderboard => 'Rangliste';

  @override
  String get engineLabHistory => 'Verlauf';

  @override
  String get engineLabDiagnostics => 'Diagnose';

  @override
  String get benchmarkNow => 'Jetzt benchmarken';

  @override
  String get benchmarkPresets => 'Voreinstellung';

  @override
  String get presetQuick => 'Schnell';

  @override
  String get presetStandard => 'Standard';

  @override
  String get presetAccurate => 'Genau';

  @override
  String get presetCustom => 'Eigen';

  @override
  String get customConfiguration => 'Eigene Konfiguration';

  @override
  String get engineLabCustomHint => 'Jede Einstellung wird mit dem Ergebnis gespeichert, damit der Lauf wiederholbar ist';

  @override
  String get timePerMoveMs => 'Zeit pro Zug (ms)';

  @override
  String get searchDepthLabel => 'Feste Suchtiefe (0 = Zeit)';

  @override
  String get gamesPerPairing => 'Partien pro Paarung';

  @override
  String get maxGames => 'Maximale Partien (0 = kein Limit)';

  @override
  String get maxDurationMinutes => 'Maximale Dauer (Min., 0 = keine)';

  @override
  String get plyLimit => 'Halbzüge bis Abbruch';

  @override
  String get openingSuite => 'Eröffnungssammlung';

  @override
  String get randomSeed => 'Zufallswert';

  @override
  String get warmUpGames => 'Aufwärmpartien';

  @override
  String get threadsLabel => 'Threads (0 = Engine-Standard)';

  @override
  String get hashLabel => 'Hash MB (0 = Engine-Standard)';

  @override
  String get optionOverrides => 'UCI-Optionen überschreiben (Name=Wert, …)';

  @override
  String get adaptiveStopping => 'Früh stoppen, wenn das Unsicherheitsziel erreicht ist';

  @override
  String get targetStdErr => 'Ziel-Standardfehler (Elo)';

  @override
  String get engineLabRepetitions => 'Wiederholungen';

  @override
  String get estimatedWorkload => 'Geschätzter Aufwand';

  @override
  String get engineLabSelectEngines => 'Engines';

  @override
  String get engineLabSelected => 'ausgewählt';

  @override
  String get engineLabUnavailable => 'nicht verfügbar';

  @override
  String get engineLabUnavailableHint => 'Engines mit ✕ lassen sich auf dieser Plattform nicht benchmarken; der Grund erscheint beim Überfahren';

  @override
  String get selectAll => 'Alle';

  @override
  String get clearSelection => 'Keine';

  @override
  String get formatRoundRobin => 'Jeder gegen jeden';

  @override
  String get formatGauntlet => 'Gauntlet';

  @override
  String get referenceEngine => 'Referenz-Engine';

  @override
  String get engineLabGauntletNeedsReference => 'Bitte eine Referenz-Engine für das Gauntlet wählen.';

  @override
  String get startBenchmark => 'Benchmark starten';

  @override
  String get pauseBenchmark => 'Pause';

  @override
  String get resumeBenchmark => 'Fortsetzen';

  @override
  String get cancelBenchmark => 'Abbrechen';

  @override
  String get benchmarkRunning => 'Benchmark läuft';

  @override
  String get engineLabStarting => 'Engines werden gestartet…';

  @override
  String get engineLabCancelling => 'Wird abgebrochen…';

  @override
  String get engineLabFinished => 'Benchmark abgeschlossen.';

  @override
  String get engineLabFailed => 'Der Benchmark ist fehlgeschlagen';

  @override
  String get engineLabLastMove => 'Letzter Zug';

  @override
  String get engineLabConfirmTitle => 'Diesen Benchmark starten?';

  @override
  String get engineLabStart => 'Starten';

  @override
  String get engineLabEngines => 'Engines';

  @override
  String get engineLabGames => 'Partien';

  @override
  String get engineLabBudget => 'Pro Zug';

  @override
  String get engineLabEstimate => 'Geschätzte Dauer';

  @override
  String get engineLabWorstCase => 'Im schlimmsten Fall';

  @override
  String get engineLabWarnings => 'Hinweise';

  @override
  String get engineLabRuns => 'Läufe';

  @override
  String get engineLabRatedGames => 'gewertete Partien';

  @override
  String get engineLabForfeits => 'kampflos';

  @override
  String get engineLabAborted => 'abgebrochen';

  @override
  String get engineLabAdjudicated => 'abgebrochen (Halbzüge)';

  @override
  String get engineLabLastRun => 'Letzter Lauf';

  @override
  String get engineLabNever => 'nie';

  @override
  String get engineLabLatestResult => 'Letztes Ergebnis';

  @override
  String get engineLabOpenReport => 'Bericht';

  @override
  String get noBenchmarksYet => 'Noch keine Benchmarks';

  @override
  String get engineLabEmptyHint => 'Zwei oder mehr Engines wählen und einen schnellen Benchmark starten. Das Ergebnis bleibt erhalten.';

  @override
  String get engineLabLeaderboardHint => 'Die Rangliste entsteht aus den auf diesem Gerät gespeicherten Läufen.';

  @override
  String get engineLabHistoryHint => 'Jeder Lauf wird auf diesem Gerät gespeichert und lässt sich als JSON, CSV oder PGN exportieren.';

  @override
  String get engineLabNoRatings => 'Noch keine gewerteten Partien.';

  @override
  String get engineLabNoGames => 'Noch keine Partien aufgezeichnet.';

  @override
  String get engineLabChanged => 'Engines mit Änderungen';

  @override
  String get engineLabChangedSubtitle => 'Diese Builds unterscheiden sich vom letzten Benchmark';

  @override
  String get engineLabRebenchmark => 'Neu benchmarken';

  @override
  String get engineLabAutomatic => 'Automatische Benchmarks';

  @override
  String get engineLabAutomaticSubtitle => 'Automatische Läufe sind immer ein begrenzter Schnell-Benchmark';

  @override
  String get engineLabAutoAfterAdd => 'Nach dem Hinzufügen einer Engine';

  @override
  String get engineLabAutoAfterChange => 'Wenn sich eine Engine ändert';

  @override
  String get engineLabAutoBudget => 'Budget';

  @override
  String get engineLabRelativeScaleHint => 'Relatives Elo: 1500 ist der Durchschnitt der Engines in diesem Lauf, keine absolute Stärke';

  @override
  String get engineLabCompareTwo => 'Zwei Engines vergleichen';

  @override
  String get engineLabCompareHint => 'Ein Unterschied ohne seine Unsicherheit ist kein Ergebnis';

  @override
  String get engineLabPickTwo => 'Zwei Engines wählen.';

  @override
  String get relativeElo => 'Relatives Elo';

  @override
  String get calibratedElo => 'Kalibriertes Elo';

  @override
  String get calibrationUnavailable => 'Kalibriertes Elo nicht verfügbar';

  @override
  String get calibrationAnchors => 'Kalibrierungsanker';

  @override
  String get uncertainty => 'Unsicherheit';

  @override
  String get ratingQuality => 'Qualität';

  @override
  String get engineLabScore => 'Punkte';

  @override
  String get performanceMetrics => 'Leistung';

  @override
  String get engineLabPerformanceHint => 'Um jeden Zug gemessen; Werte, die die Engine nicht meldet, bleiben nicht verfügbar';

  @override
  String get nodesPerSecond => 'Knoten pro Sekunde';

  @override
  String get latencyP50 => 'Median';

  @override
  String get latencyP95 => 'p95';

  @override
  String get latencyP99 => 'p99';

  @override
  String get engineLabMax => 'Max';

  @override
  String get engineLabDepth => 'Tiefe';

  @override
  String get engineLabInitMs => 'Start';

  @override
  String get unavailableLabel => 'nicht verfügbar';

  @override
  String get engineLabMoves => 'Züge';

  @override
  String get engineLabEngine => 'Engine';

  @override
  String get engineLabCheck => 'Prüfung';

  @override
  String get engineLabPassed => 'Bestanden';

  @override
  String get engineLabMedian => 'Median';

  @override
  String get engineLabWorst => 'Schlechtester';

  @override
  String get stabilityCheck => 'Stabilitätsprüfung';

  @override
  String get stabilityPassed => 'Bestanden';

  @override
  String get stabilityFailed => 'Fehlgeschlagen';

  @override
  String get engineLabStabilityHint => 'Wiederholtes Starten, wiederholte Suchen und sauberes Beenden';

  @override
  String get engineLabRunStability => 'Prüfung starten';

  @override
  String get engineLabIdentity => 'Engine-Identität';

  @override
  String get engineLabIdentityHint => 'Was der Benchmark aufzeichnet und was entscheidet, ob zwei Läufe vergleichbar sind';

  @override
  String get engineLabIdentityEmpty => 'Eine Engine prüfen, um ID, Fingerabdruck, Backend und Konfigurations-Hash zu sehen.';

  @override
  String get engineLabInspect => 'Prüfen';

  @override
  String get engineLabEnvironment => 'Umgebung';

  @override
  String get engineLabPlatform => 'Plattform';

  @override
  String get engineLabVersion => 'Version';

  @override
  String get engineLabMetricsHint => 'CPU-Zeit und Speicherverbrauch werden vom Engine-Protokoll nicht gemeldet und daher als nicht verfügbar ausgewiesen statt geschätzt.';

  @override
  String get engineLabLicense => 'Lizenz der Sammlung';

  @override
  String get engineLabProgressionHint => 'Relatives Elo jeder Engine über die hier gespeicherten Läufe';

  @override
  String get engineLabDeleteTitle => 'Diesen Lauf löschen?';

  @override
  String get engineLabReport => 'Benchmark-Bericht';

  @override
  String get engineLabReportMissing => 'Bericht nicht verfügbar';

  @override
  String get engineLabSummary => 'Zusammenfassung';

  @override
  String get engineLabStarted => 'Gestartet';

  @override
  String get engineLabDuration => 'Dauer';

  @override
  String get engineLabTrigger => 'Auslöser';

  @override
  String get engineLabStopped => 'Beendet wegen';

  @override
  String get engineLabFormat => 'Format';

  @override
  String get engineLabConfiguration => 'Konfiguration';

  @override
  String get engineLabFailures => 'Engine-Probleme';

  @override
  String get engineLabStandings => 'Tabelle';

  @override
  String get engineLabGamesList => 'Partien';

  @override
  String get engineLabShowAll => 'Alle anzeigen';

  @override
  String get engineLabShowLess => 'Weniger anzeigen';

  @override
  String get engineLabExportReport => 'Bericht kopieren';

  @override
  String get engineLabMethod => 'Methode';

  @override
  String get engineLabMethodBody => 'Bradley-Terry-Maximum-Likelihood über jede gewertete Partie, zentriert auf den Durchschnitt der Engines im Lauf. Das 95%-Intervall ist Rating ± 1,96 × Standardfehler aus der Fisher-Information der Anpassung. Abgebrochene, annullierte und kampflos verlorene Partien werden gezählt, aber nicht gewertet: eine nicht beendete Partie ist kein Remis.';

  @override
  String get exportJson => 'JSON exportieren';

  @override
  String get exportCsv => 'CSV exportieren';

  @override
  String get exportPgn => 'PGN exportieren';

  @override
  String get importBenchmark => 'Importieren';

  @override
  String get delete => 'Löschen';

  @override
  String get copy => 'Kopieren';

  @override
  String get elo => 'Elo';

  @override
  String get refresh => 'Aktualisieren';

  @override
  String get retry => 'Erneut versuchen';

  @override
  String get engineLabAdaptiveStopping => 'Früh stoppen, sobald das Rating genau genug ist';

  @override
  String get engineLabAppVersion => 'App-Version';

  @override
  String get engineLabBackend => 'Backend';

  @override
  String get engineLabBalanceColors => 'Beide Farben pro Eröffnung';

  @override
  String get engineLabBuiltIn => 'Im Lieferumfang der App';

  @override
  String get engineLabCalibrationHint => 'Nur eine veröffentlichte Wertzahl für eine Engine im Lauf macht aus der relativen Skala eine absolute.';

  @override
  String get engineLabCalibrationUnavailable => 'Kein kalibriertes Rating für diesen Lauf:';

  @override
  String get engineLabCompare => 'Zwei Engines vergleichen';

  @override
  String get engineLabCustom => 'eigene';

  @override
  String get engineLabDeleteBody => 'Die gespeicherten Partien, Ratings und der Bericht werden von diesem Gerät entfernt. Exportierte Kopien bleiben bestehen.';

  @override
  String get engineLabFingerprint => 'Fingerabdruck';

  @override
  String get engineLabGauntletHint => 'Jeder Herausforderer spielt gegen die Referenz-Engine; die Referenz spielt nicht gegen sich selbst.';

  @override
  String get engineLabHash => 'Hash (MB)';

  @override
  String get engineLabHost => 'Host';

  @override
  String get engineLabInProgress => 'läuft';

  @override
  String get engineLabMaxGames => 'Max. Partien';

  @override
  String get engineLabMaxMinutes => 'Max. Minuten';

  @override
  String get engineLabMovesPerPairing => 'Partien pro Paarung';

  @override
  String get engineLabNoAnchors => 'Keine Referenz angegeben; Ratings bleiben relativ.';

  @override
  String get engineLabNoFingerprint => 'nicht verfügbar';

  @override
  String get engineLabNoHistory => 'Keine gespeicherten Läufe';

  @override
  String get engineLabNoHistoryHint => 'Abgeschlossene Benchmarks werden hier mit Partien, Ratings und Bericht aufbewahrt.';

  @override
  String get engineLabNoMetrics => 'keine Zugzeiten erfasst';

  @override
  String get engineLabNoRatedGames => 'Dieser Lauf hat keine wertbaren Partien ergeben.';

  @override
  String get engineLabNoRatingsHint => 'Starte einen Benchmark; die Ratings der beteiligten Engines erscheinen hier, jeweils mit Intervall.';

  @override
  String get engineLabOpeningSuite => 'Eröffnungssammlung';

  @override
  String get engineLabPerformance => 'Leistung';

  @override
  String get engineLabPlyCap => 'Halbzüge bis Abbruch';

  @override
  String get engineLabPlyCapHint => 'Eine hier gestoppte Partie wird entschieden, nicht als Remis gewertet';

  @override
  String get engineLabPreset => 'Voreinstellung';

  @override
  String get engineLabProgression => 'Verlauf';

  @override
  String get engineLabQualityHigh => 'präzise';

  @override
  String get engineLabQualityInsufficient => 'zu wenige Partien';

  @override
  String get engineLabQualityLow => 'grob';

  @override
  String get engineLabQualityModerate => 'brauchbar';

  @override
  String get engineLabRated => 'gewertet';

  @override
  String get engineLabReference => 'Referenz';

  @override
  String get engineLabRunning => 'Läuft…';

  @override
  String get engineLabSearchDepth => 'Suchtiefe';

  @override
  String get engineLabSeed => 'Startwert';

  @override
  String get engineLabStability => 'Stabilität';

  @override
  String get engineLabTargetStdErr => 'Stoppen bei ±Elo';

  @override
  String get engineLabThreads => 'Threads';

  @override
  String get engineLabTimePerMoveMs => 'Zeit pro Zug (ms)';

  @override
  String get engineLabUnchanged => 'unverändert';

  @override
  String get engineLabWarmUp => 'Einspielpartien';

  @override
  String get engineLabWebNote => 'Im Browser laufen nur die mitgelieferten Engines; eine eigene ausführbare Datei kann nicht gestartet werden.';

  @override
  String get engineLabZeroIsEngineDefault => '0 = Vorgabe der Engine';

  @override
  String get engineLabZeroIsNever => '0 = ganzen Plan spielen';

  @override
  String get engineLabZeroIsTime => '0 = Uhrzeit verwenden';

  @override
  String get engineLabZeroIsUnlimited => '0 = kein Limit';

  @override
  String get engineLabAddAnchor => 'Referenz hinzufügen';

  @override
  String get engineLabRemoveAnchor => 'Referenz entfernen';

  @override
  String get engineLabAnchorUsedHint => 'Es wird die erste Referenz verwendet, die zu einer Engine im Lauf passt; eine Referenz für eine nicht beteiligte Engine kann nichts kalibrieren.';

  @override
  String get engineLabAnchorIntro => 'Eine veröffentlichte Wertzahl ist nur brauchbar, wenn Quelle, Datum, Hardware und Zeitkontrolle erfasst sind und die Engine am Lauf teilnimmt.';

  @override
  String get engineLabAnchorRating => 'Veröffentlichte Wertzahl';

  @override
  String get engineLabAnchorScale => 'Rangliste oder Skala';

  @override
  String get engineLabAnchorSource => 'Quelle (URL oder Veröffentlichung)';

  @override
  String get engineLabAnchorDate => 'Veröffentlicht (JJJJ-MM-TT)';

  @override
  String get engineLabAnchorHardware => 'Hardware';

  @override
  String get engineLabAnchorTimeControl => 'Zeitkontrolle';

  @override
  String get engineLabAnchorBudget => 'Zeitbudget pro Zug (ms)';

  @override
  String get engineLabAnchorMissing => 'Fehlt';

  @override
  String get engineLabAnchorDateHint => 'Schreibe das Veröffentlichungsdatum als JJJJ-MM-TT.';
}

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'CrispChess';

  @override
  String get yourTurn => 'Your turn';

  @override
  String get whiteToMove => 'White to move';

  @override
  String get blackToMove => 'Black to move';

  @override
  String get thinking => 'Thinking...';

  @override
  String get engineError => 'Engine error';

  @override
  String loading(Object engineName) {
    return 'Loading $engineName...';
  }

  @override
  String get downloading => 'Downloading & initializing...';

  @override
  String engineReady(Object engineName) {
    return '$engineName ready';
  }

  @override
  String engineThinking(Object engineName) {
    return '$engineName is thinking...';
  }

  @override
  String get newGame => 'New Game';

  @override
  String get newGameConfirm => 'Current game will be lost.';

  @override
  String get settings => 'Settings';

  @override
  String get about => 'About';

  @override
  String get aboutCrispChess => 'About CrispChess';

  @override
  String get puzzles => 'Puzzles';

  @override
  String get flipBoard => 'Flip Board';

  @override
  String get copyPgn => 'Copy PGN';

  @override
  String get pastePgn => 'Paste PGN';

  @override
  String get loadFen => 'Load FEN';

  @override
  String get setupPosition => 'Setup Position';

  @override
  String get pgnDatabase => 'PGN Database';

  @override
  String get offerDraw => 'Offer Draw';

  @override
  String get resign => 'Resign';

  @override
  String resignConfirm(Object engineName) {
    return '$engineName wins by resignation.';
  }

  @override
  String drawDeclined(Object engineName) {
    return '$engineName declines the draw offer.';
  }

  @override
  String get drawAgreed => 'Draw agreed';

  @override
  String get youResigned => 'You resigned';

  @override
  String get gameResumed => 'Game resumed';

  @override
  String get resumeGame => 'Resume game?';

  @override
  String savedGameMoves(Object count) {
    return 'You have a saved game ($count moves).';
  }

  @override
  String get discard => 'Discard';

  @override
  String get resume => 'Resume';

  @override
  String get cancel => 'Cancel';

  @override
  String get review => 'Review';

  @override
  String get undo => 'Undo';

  @override
  String get redo => 'Redo';

  @override
  String get hint => 'Hint';

  @override
  String get analyze => 'Analyze';

  @override
  String get abort => 'Abort';

  @override
  String get playAsWhite => 'White';

  @override
  String get playAsBlack => 'Black';

  @override
  String get playAsRandom => 'Random';

  @override
  String get twoPlayer => 'Two Player (local)';

  @override
  String get passAndPlay => 'Pass and play';

  @override
  String get playAs => 'Play as';

  @override
  String get chessEngine => 'Chess Engine';

  @override
  String get opponentStrength => 'Opponent Strength';

  @override
  String get hintDepth => 'Hint Depth';

  @override
  String analysisDepth(Object depth) {
    return 'Analysis Depth: $depth';
  }

  @override
  String get hintEngine => 'Hint Engine';

  @override
  String get sameAsOpponent => 'Same as opponent';

  @override
  String get game => 'Game';

  @override
  String get showValidMoves => 'Show Valid Moves';

  @override
  String get showValidMovesSubtitle =>
      'Highlight legal moves when selecting a piece';

  @override
  String get allowUndo => 'Allow Undo';

  @override
  String get allowUndoSubtitle => 'Disable for discipline mode';

  @override
  String get solidBlackPieces => 'Solid Black Pieces';

  @override
  String get solidBlackPiecesSubtitle =>
      'Render black pieces as solid black instead of grey gradient';

  @override
  String get animationSpeed => 'Animation Speed';

  @override
  String get instant => 'Instant';

  @override
  String get fast => 'Fast';

  @override
  String get normal => 'Normal';

  @override
  String get slow => 'Slow';

  @override
  String get timeControl => 'Time Control';

  @override
  String get playAsBlackSetting => 'Play as Black';

  @override
  String get playAsBlackSubtitle => 'Engine makes the first move';

  @override
  String get pieceStyle => 'Piece Style';

  @override
  String get theme => 'Theme';

  @override
  String get language => 'Language';

  @override
  String get systemDefault => 'System Default';

  @override
  String get system => 'System';

  @override
  String get light => 'Light';

  @override
  String get darkAmoled => 'Dark (AMOLED)';

  @override
  String get resetToDefaults => 'Reset to defaults';

  @override
  String get save => 'Save';

  @override
  String get pgnCopied => 'PGN copied to clipboard';

  @override
  String get pgnLoaded => 'PGN loaded';

  @override
  String get invalidPgn => 'Invalid PGN';

  @override
  String get noPgnInClipboard => 'No PGN found in clipboard';

  @override
  String get noMovesYet => 'No moves yet';

  @override
  String get solved => 'solved';

  @override
  String get showSolution => 'Show Solution';

  @override
  String get nextPuzzle => 'Next Puzzle';

  @override
  String get skip => 'Skip';

  @override
  String wrongMove(Object remaining) {
    return 'Wrong move. Try again. ($remaining left)';
  }

  @override
  String get puzzleSolved => 'Correct! Puzzle solved.';

  @override
  String get findNextMove => 'Correct! Find the next move.';

  @override
  String get gameSummary => 'Game Summary';

  @override
  String get yourAccuracy => 'Your Accuracy';

  @override
  String get accuracy => 'Accuracy';

  @override
  String get good => 'Good';

  @override
  String get mistakes => 'Mistakes';

  @override
  String get myMistakes => 'My Mistakes';

  @override
  String get blunders => 'Blunders';

  @override
  String get evaluation => 'Evaluation';

  @override
  String get yourBestMove => 'Your Best Move';

  @override
  String get biggestMistake => 'Biggest Mistake';

  @override
  String get moves => 'Moves';

  @override
  String get tapToViewPosition => 'Tap to view position';

  @override
  String moveN(Object n) {
    return 'Move $n';
  }

  @override
  String get welcome => 'Welcome to CrispChess';

  @override
  String get welcomeSubtitle => 'Play chess against AI engines or a friend.';

  @override
  String get letsPlay => 'Let\'s play!';

  @override
  String get switchToBuiltIn => 'Switch to Built-in';

  @override
  String failedToInitialize(Object engineName) {
    return '$engineName: failed to initialize';
  }

  @override
  String get checkmate => 'Checkmate';

  @override
  String get stalemate => 'Stalemate';

  @override
  String get drawThreefold => 'Draw — threefold repetition';

  @override
  String get drawInsufficient => 'Draw — insufficient material';

  @override
  String get drawFiftyMove => 'Draw — fifty-move rule';

  @override
  String get resignation => 'Resignation';

  @override
  String get drawByAgreement => 'Draw by agreement';

  @override
  String get gameOver => 'Game Over';

  @override
  String get boardScreenshot => 'Board Screenshot';

  @override
  String get clearAnnotations => 'Clear Annotations';

  @override
  String get bookmarkPosition => 'Bookmark Position';

  @override
  String get positionBookmarked => 'Position bookmarked';

  @override
  String get askCoach => 'Ask Coach';

  @override
  String get drills => 'Drills';

  @override
  String get engineVsEngine => 'Engine vs Engine';

  @override
  String get stats => 'Stats';

  @override
  String get statsAndAchievements => 'Stats & Achievements';

  @override
  String get achievements => 'Achievements';

  @override
  String get games => 'Games';

  @override
  String get wins => 'Wins';

  @override
  String get badges => 'Badges';

  @override
  String get engineManager => 'Engine Manager';

  @override
  String get engineManagerSubtitle => 'Engine Manager — Add Custom UCI Engines';

  @override
  String get addEngine => 'Add Engine';

  @override
  String get addUciEngine => 'Add UCI Engine';

  @override
  String get engineBinaryPath => 'Engine binary path';

  @override
  String get displayName => 'Display name (optional)';

  @override
  String get leaveBlankAutoDetect => 'Leave blank to auto-detect';

  @override
  String get add => 'Add';

  @override
  String get remove => 'Remove';

  @override
  String get configure => 'Configure';

  @override
  String get probingEngine => 'Probing engine...';

  @override
  String engineAdded(Object name) {
    return 'Added: $name';
  }

  @override
  String engineInitFailed(Object error) {
    return 'Engine failed to initialize: $error';
  }

  @override
  String get loadingEngineOptions => 'Loading engine options...';

  @override
  String get noCustomEngines => 'No custom engines added';

  @override
  String get noCustomEnginesSubtitle =>
      'Add any UCI-compatible chess engine\nby providing the path to its binary.';

  @override
  String get removeEngine => 'Remove Engine?';

  @override
  String removeEngineConfirm(Object name) {
    return 'Remove \"$name\" from your engine list?';
  }

  @override
  String get noConfigurableOptions => 'No configurable options';

  @override
  String get reset => 'Reset';

  @override
  String get run => 'Run';

  @override
  String rangeMinMax(Object min, Object max) {
    return 'Range: $min – $max';
  }

  @override
  String get positionEditor => 'Position Editor';

  @override
  String get startingPosition => 'Starting position';

  @override
  String get clearBoard => 'Clear board';

  @override
  String get sideToMove => 'Side to move:';

  @override
  String get castling => 'Castling:';

  @override
  String get copyFen => 'Copy FEN';

  @override
  String get fenCopied => 'FEN copied';

  @override
  String get loadPosition => 'Load Position';

  @override
  String get invalidFen => 'Invalid FEN string';

  @override
  String get positionLoaded => 'Position loaded from FEN';

  @override
  String get customPositionLoaded => 'Custom position loaded';

  @override
  String get pawnsOnEdgeRank => 'Pawns cannot be on the first or last rank';

  @override
  String get needOneWhiteKing => 'White must have exactly one king';

  @override
  String get needOneBlackKing => 'Black must have exactly one king';

  @override
  String get pasteFenHint => 'Paste FEN string...';

  @override
  String get pasteFromClipboard => 'Paste from clipboard';

  @override
  String get load => 'Load';

  @override
  String get databaseStatistics => 'Database Statistics';

  @override
  String nGames(Object count) {
    return '$count games';
  }

  @override
  String get results => 'Results';

  @override
  String get whiteWins => 'White wins';

  @override
  String get blackWins => 'Black wins';

  @override
  String get draws => 'Draws';

  @override
  String get topOpenings => 'Top Openings (ECO)';

  @override
  String get mostActivePlayers => 'Most Active Players';

  @override
  String get close => 'Close';

  @override
  String get noDatabaseLoaded => 'No database loaded';

  @override
  String get noDatabaseSubtitle =>
      'Copy a PGN file with multiple games\nto your clipboard, then tap the paste icon.';

  @override
  String get searchByPlayer => 'Search by player...';

  @override
  String get result => 'Result';

  @override
  String get all => 'All';

  @override
  String get draw => 'Draw';

  @override
  String get noGamesFound => 'No games found in PGN';

  @override
  String get noPgnData => 'No PGN data in clipboard';

  @override
  String get gameLoadedFromDb => 'Game loaded from database';

  @override
  String get match => 'Match';

  @override
  String get tournament => 'Tournament';

  @override
  String get selectTwoDifferent => 'Select two different engines';

  @override
  String get selectAtLeast3 => 'Select at least 3 engines';

  @override
  String selectEngines(Object count) {
    return 'Select engines ($count selected, min 3):';
  }

  @override
  String get depth => 'Depth';

  @override
  String get startMatch => 'Start Match';

  @override
  String get startTournament => 'Start Tournament';

  @override
  String get stopped => 'Stopped';

  @override
  String get vs => 'vs';

  @override
  String get multiEngineAnalysis => 'Multi-Engine Analysis';

  @override
  String get multiEngine => 'Multi-Engine';

  @override
  String get stopMultiEngine => 'Stop multi-engine';

  @override
  String get selectEnginesToCompare => 'Select engines to compare:';

  @override
  String get currentOpponent => '(current opponent)';

  @override
  String get start => 'Start';

  @override
  String multiEngineFailed(Object error) {
    return 'Multi-engine failed: $error';
  }

  @override
  String get reAnalyze => 'Re-analyze';

  @override
  String get tapRefreshToAnalyze => 'Tap refresh to analyze';

  @override
  String get engineLoading => 'Engine loading...';

  @override
  String bestMove(Object move) {
    return 'Best: $move';
  }

  @override
  String get analysis => 'Analysis';

  @override
  String get engineNotReady => 'Engine not ready';

  @override
  String get positionRestored => 'Position restored';

  @override
  String get resignQuestion => 'Resign?';

  @override
  String dailyLogin(Object xp, Object streak) {
    return 'Daily login: +$xp XP (streak: $streak)';
  }

  @override
  String get levelUp => 'Level Up!';

  @override
  String youReached(Object level) {
    return 'You reached $level!';
  }

  @override
  String get continueButton => 'Continue';

  @override
  String get couldNotCaptureBoard => 'Could not capture board';

  @override
  String boardCaptured(Object size) {
    return 'Board captured ($size KB)';
  }

  @override
  String screenshotFailed(Object error) {
    return 'Screenshot failed: $error';
  }

  @override
  String get illegalMove => 'Illegal Move!';

  @override
  String premove(Object move) {
    return 'Premove: $move';
  }

  @override
  String get premoveIllegal => 'Premove illegal — your turn';

  @override
  String get drillComplete => 'Drill Complete!';

  @override
  String correctOnFirstTry(Object correct, Object total) {
    return '$correct / $total correct on first try';
  }

  @override
  String get done => 'Done';

  @override
  String stepOf(Object current, Object total) {
    return 'Step $current of $total';
  }

  @override
  String get next => 'Next';

  @override
  String get finish => 'Finish';

  @override
  String get findBestMove => 'Find the best move.';

  @override
  String get correct => 'Correct!';

  @override
  String get notQuiteTryAgain => 'Not quite — try again!';

  @override
  String get aiCoach => 'AI Coach';

  @override
  String get privacy => 'Privacy';

  @override
  String get privacyNotice =>
      'Your API key is stored locally on your device only. Game data (FEN/PGN) is sent directly to your chosen AI provider. CrispChess does not store, log, or transmit any data to its own servers. You can delete your API key at any time.';

  @override
  String get enterApiKey => 'Enter your API key to get started:';

  @override
  String keyConfigured(Object provider) {
    return '$provider key configured';
  }

  @override
  String get removeKey => 'Remove key';

  @override
  String get noMistakesYet => 'No mistakes tracked yet!';

  @override
  String get noMistakesSubtitle =>
      'Play games with analysis enabled to track blunders.';

  @override
  String get clearAll => 'Clear all';

  @override
  String get unknownMove => 'Unknown move';

  @override
  String get serviceProvider => 'Service Provider';

  @override
  String get license => 'License';

  @override
  String get chessEngines => 'Chess Engines';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get disclaimer => 'Disclaimer';

  @override
  String get sourceCode => 'Source Code';

  @override
  String get urlCopied => 'URL copied to clipboard';

  @override
  String get contributionsWelcome =>
      'Contributions welcome. Open an issue first for major changes.';

  @override
  String get openSourceLicenses => 'Open Source Licenses';

  @override
  String get hintsAndAnalysis => 'Hints & Analysis';

  @override
  String get maia3Model => 'Maia3 Model';

  @override
  String get stockfishVersion => 'Stockfish Version';

  @override
  String get lynxBuild => 'Lynx Build';

  @override
  String get lynxBuildNote =>
      'The engine loads once per page, so a change takes effect after a reload.';

  @override
  String get maiaWeight => 'Maia Weight (ELO level)';

  @override
  String get gameMode => 'Game Mode';

  @override
  String get standard => 'Standard';

  @override
  String get kingOfTheHill => 'King of the Hill';

  @override
  String get threeCheck => 'Three-Check';

  @override
  String get customTimeControl => 'Custom...';

  @override
  String get boardColorThemeLabel => 'Board Color';

  @override
  String get notationStyleLabel => 'Notation';

  @override
  String get blindfoldMode => 'Blindfold Mode';

  @override
  String get blindfoldModeSubtitle => 'Hide pieces — play by memory';

  @override
  String get importExport => 'Import / Export';

  @override
  String get boardToolsMenu => 'Board Tools';

  @override
  String get learnMenu => 'Learn';

  @override
  String get progressMenu => 'Progress';

  @override
  String get openingExplorer => 'Opening Explorer';

  @override
  String get coordinateTrainer => 'Coordinate Trainer';

  @override
  String get gameHistory => 'Game History';

  @override
  String get humanLens => 'Human Lens';

  @override
  String humanLensSubtitle(Object elo) {
    return 'How players rated $elo see this position';
  }

  @override
  String get humanLensLoading => 'Loading Maia (25 MB, first time only)…';

  @override
  String get humanLensThinking => 'Asking the players…';

  @override
  String get humanLensBestMove => 'Engine\'s move';

  @override
  String humanLensFoundBy(Object percent, Object elo) {
    return '$percent% of $elo players find it';
  }

  @override
  String humanLensNaturalFrom(Object elo) {
    return 'Most players find it from about $elo';
  }

  @override
  String get humanLensNeverNatural => 'Even at 2300 most players miss it';

  @override
  String get humanLensTrap => 'Trap';

  @override
  String humanLensTrapText(Object percent, Object elo, Object move) {
    return '$percent% of $elo players play $move, and it\'s a mistake.';
  }

  @override
  String humanLensCandidates(Object elo) {
    return 'What $elo players play';
  }

  @override
  String get humanLensByRating => 'Who finds the engine\'s move';

  @override
  String get humanLensUnsupported => 'Human Lens is for standard chess only.';

  @override
  String get humanLensGameOver =>
      'The game is over, so there are no moves to look at.';

  @override
  String humanLensError(Object error) {
    return 'Human Lens failed: $error';
  }

  @override
  String get findabilityObvious => 'Obvious';

  @override
  String get findabilityNatural => 'Natural';

  @override
  String get findabilityFindable => 'Findable';

  @override
  String get findabilityHard => 'Hard';

  @override
  String get findabilityVeryHard => 'Very hard';

  @override
  String get humanReview => 'Human review';

  @override
  String get humanReviewIntro =>
      'See the game the way Maia sees human players: which misses were hard to find, which were slips, and what rating your moves looked like.';

  @override
  String get humanReviewStart => 'Review with Maia';

  @override
  String humanReviewProgress(Object done, Object total) {
    return 'Move $done of $total…';
  }

  @override
  String humanReviewPlayedLike(Object elo) {
    return 'Your moves looked like a player rated about $elo';
  }

  @override
  String get humanReviewHardMiss => 'Hard to find';

  @override
  String get humanReviewSlip => 'Slip';

  @override
  String humanReviewMissText(
      Object played, Object best, Object percent, Object elo) {
    return '$played instead of $best: $percent% of $elo players find it';
  }

  @override
  String get humanReviewNoMistakes => 'No costly misses in this game.';

  @override
  String get humanReviewRatingLabel => 'Compare with players rated';

  @override
  String get scanBoard => 'Scan board';

  @override
  String get scanBoardHint =>
      'Choose an image: a screenshot or book diagram (Diagram), or a photo of a real board (Photo).';

  @override
  String get scanPickImage => 'Choose image';

  @override
  String get scanRecognizing => 'Recognizing…';

  @override
  String get scanNoBoard =>
      'No chessboard found. Drag a square around the board in the image.';

  @override
  String get scanDragHint =>
      'Wrong area? Drag a square around the board in the image.';

  @override
  String scanUncertain(Object count) {
    return '$count uncertain squares are highlighted. Check them.';
  }

  @override
  String scanProblems(Object problems) {
    return 'Check the position: $problems';
  }

  @override
  String get scanUsePosition => 'Use position';

  @override
  String scanFailed(Object error) {
    return 'Could not read the image: $error';
  }

  @override
  String get engine => 'Engine';

  @override
  String get rating => 'Rating';

  @override
  String get ghostTitle => 'Your Ghost';

  @override
  String get ghostDescription =>
      'Plays your openings, then like a player of your rating';

  @override
  String ghostGames(Object games, Object positions) {
    return 'Built from $games of your games, $positions opening positions';
  }

  @override
  String get ghostNoGames =>
      'Play a few games first: the Ghost learns from your game history.';

  @override
  String ghostRating(Object elo) {
    return 'Plays like: $elo';
  }

  @override
  String get ghostRatingUnmeasured =>
      'Rating not measured yet (plays like 1500)';

  @override
  String get ghostMeasure => 'Measure my rating';

  @override
  String ghostMeasuring(Object done, Object total) {
    return 'Reading your moves… $done of $total';
  }

  @override
  String ghostFavourite(Object moves) {
    return 'Your favourite first moves: $moves';
  }

  @override
  String get scanModeDiagram => 'Diagram';

  @override
  String get scanModePhoto => 'Photo';

  @override
  String get scanPhotoHint =>
      'Photograph the whole board from a player\'s side, grid lines visible. Works best with standard tournament-style pieces.';

  @override
  String get scanPhotoNoBoard =>
      'No board found. Photograph the whole board, with its grid visible.';

  @override
  String get scanRotate => 'Rotate 90°';

  @override
  String get scanOrientationUnsure =>
      'Check the orientation: rotate until White is at the bottom.';

  @override
  String get voiceMove => 'Speak a move (V)';

  @override
  String get voiceListening =>
      'Listening — say your move, then tap the microphone';

  @override
  String get voiceRecognizing => 'Recognising…';

  @override
  String voiceLoading(Object mb) {
    return 'Loading the speech model ($mb MB, once)…';
  }

  @override
  String get voiceNoMove => 'No move recognised — try again';

  @override
  String voiceHeard(Object move) {
    return 'Heard: $move';
  }

  @override
  String get voiceWhichMove => 'Which move did you mean?';

  @override
  String voiceFailed(Object error) {
    return 'Voice input failed: $error';
  }

  @override
  String get engineLab => 'Engine Lab';

  @override
  String get engineLabSubtitle => 'Benchmark engines, keep the results and compare versions';

  @override
  String get engineLabDashboard => 'Dashboard';

  @override
  String get engineLabBenchmark => 'Benchmark';

  @override
  String get engineLabLeaderboard => 'Leaderboard';

  @override
  String get engineLabHistory => 'History';

  @override
  String get engineLabDiagnostics => 'Diagnostics';

  @override
  String get benchmarkNow => 'Benchmark Now';

  @override
  String get benchmarkPresets => 'Preset';

  @override
  String get presetQuick => 'Quick';

  @override
  String get presetStandard => 'Standard';

  @override
  String get presetAccurate => 'Accurate';

  @override
  String get presetCustom => 'Custom';

  @override
  String get customConfiguration => 'Custom configuration';

  @override
  String get engineLabCustomHint => 'Every setting is stored with the result, so the run can be repeated';

  @override
  String get timePerMoveMs => 'Time per move (ms)';

  @override
  String get searchDepthLabel => 'Fixed search depth (0 = time)';

  @override
  String get gamesPerPairing => 'Games per pairing';

  @override
  String get maxGames => 'Maximum games (0 = no cap)';

  @override
  String get maxDurationMinutes => 'Maximum duration (min, 0 = none)';

  @override
  String get plyLimit => 'Ply limit';

  @override
  String get openingSuite => 'Opening suite';

  @override
  String get randomSeed => 'Random seed';

  @override
  String get warmUpGames => 'Warm-up games';

  @override
  String get threadsLabel => 'Threads (0 = engine default)';

  @override
  String get hashLabel => 'Hash MB (0 = engine default)';

  @override
  String get optionOverrides => 'UCI option overrides (Name=Value, …)';

  @override
  String get adaptiveStopping => 'Stop early when the uncertainty target is met';

  @override
  String get targetStdErr => 'Target standard error (Elo)';

  @override
  String get engineLabRepetitions => 'Repetitions';

  @override
  String get estimatedWorkload => 'Estimated workload';

  @override
  String get engineLabSelectEngines => 'Engines';

  @override
  String get engineLabSelected => 'selected';

  @override
  String get engineLabUnavailable => 'unavailable';

  @override
  String get engineLabUnavailableHint => 'Engines marked ✕ cannot be benchmarked on this platform; the reason appears on hover';

  @override
  String get selectAll => 'Select all';

  @override
  String get clearSelection => 'Clear';

  @override
  String get formatRoundRobin => 'Round robin';

  @override
  String get formatGauntlet => 'Gauntlet';

  @override
  String get referenceEngine => 'Reference engine';

  @override
  String get engineLabGauntletNeedsReference => 'Pick a reference engine for the gauntlet.';

  @override
  String get startBenchmark => 'Start benchmark';

  @override
  String get pauseBenchmark => 'Pause';

  @override
  String get resumeBenchmark => 'Resume';

  @override
  String get cancelBenchmark => 'Cancel';

  @override
  String get benchmarkRunning => 'Benchmark running';

  @override
  String get engineLabStarting => 'Starting engines…';

  @override
  String get engineLabCancelling => 'Cancelling…';

  @override
  String get engineLabFinished => 'Benchmark complete.';

  @override
  String get engineLabFailed => 'The benchmark failed';

  @override
  String get engineLabLastMove => 'Last move';

  @override
  String get engineLabConfirmTitle => 'Start this benchmark?';

  @override
  String get engineLabStart => 'Start';

  @override
  String get engineLabEngines => 'Engines';

  @override
  String get engineLabGames => 'Games';

  @override
  String get engineLabBudget => 'Per move';

  @override
  String get engineLabEstimate => 'Estimated time';

  @override
  String get engineLabWorstCase => 'Worst case';

  @override
  String get engineLabWarnings => 'Notes';

  @override
  String get engineLabRuns => 'runs';

  @override
  String get engineLabRatedGames => 'rated games';

  @override
  String get engineLabForfeits => 'forfeits';

  @override
  String get engineLabAborted => 'aborted';

  @override
  String get engineLabAdjudicated => 'adjudicated';

  @override
  String get engineLabLastRun => 'Last run';

  @override
  String get engineLabNever => 'never';

  @override
  String get engineLabLatestResult => 'Latest result';

  @override
  String get engineLabOpenReport => 'Report';

  @override
  String get noBenchmarksYet => 'No benchmarks yet';

  @override
  String get engineLabEmptyHint => 'Pick two or more engines and run a Quick benchmark. The result is kept.';

  @override
  String get engineLabLeaderboardHint => 'The leaderboard is built from the runs stored on this device.';

  @override
  String get engineLabHistoryHint => 'Every run is stored on this device and can be exported as JSON, CSV or PGN.';

  @override
  String get engineLabNoRatings => 'No rated games yet.';

  @override
  String get engineLabNoGames => 'No games recorded yet.';

  @override
  String get engineLabChanged => 'Engines that changed';

  @override
  String get engineLabChangedSubtitle => 'These builds differ from the last benchmark';

  @override
  String get engineLabRebenchmark => 'Re-benchmark';

  @override
  String get engineLabAutomatic => 'Automatic benchmarks';

  @override
  String get engineLabAutomaticSubtitle => 'Automatic runs are always a capped Quick benchmark';

  @override
  String get engineLabAutoAfterAdd => 'After adding an engine';

  @override
  String get engineLabAutoAfterChange => 'After an engine changes';

  @override
  String get engineLabAutoBudget => 'Budget';

  @override
  String get engineLabRelativeScaleHint => 'Relative Elo: 1500 is the average of the engines in this run, not an absolute strength';

  @override
  String get engineLabCompareTwo => 'Compare two engines';

  @override
  String get engineLabCompareHint => 'A difference without its uncertainty is not a result';

  @override
  String get engineLabPickTwo => 'Pick two engines.';

  @override
  String get relativeElo => 'Relative Elo';

  @override
  String get calibratedElo => 'Calibrated Elo';

  @override
  String get calibrationUnavailable => 'Calibrated Elo unavailable';

  @override
  String get calibrationAnchors => 'Calibration anchors';

  @override
  String get uncertainty => 'Uncertainty';

  @override
  String get ratingQuality => 'Quality';

  @override
  String get engineLabScore => 'Score';

  @override
  String get performanceMetrics => 'Performance';

  @override
  String get engineLabPerformanceHint => 'Measured around every move; counters the engine does not report stay unavailable';

  @override
  String get nodesPerSecond => 'Nodes per second';

  @override
  String get latencyP50 => 'Median';

  @override
  String get latencyP95 => 'p95';

  @override
  String get latencyP99 => 'p99';

  @override
  String get engineLabMax => 'Max';

  @override
  String get engineLabDepth => 'Depth';

  @override
  String get engineLabInitMs => 'Init';

  @override
  String get unavailableLabel => 'unavailable';

  @override
  String get engineLabMoves => 'Moves';

  @override
  String get engineLabEngine => 'Engine';

  @override
  String get engineLabCheck => 'Check';

  @override
  String get engineLabPassed => 'Passed';

  @override
  String get engineLabMedian => 'Median';

  @override
  String get engineLabWorst => 'Worst';

  @override
  String get stabilityCheck => 'Stability check';

  @override
  String get stabilityPassed => 'Passed';

  @override
  String get stabilityFailed => 'Failed';

  @override
  String get engineLabStabilityHint => 'Repeated initialisation, repeated searches and a clean shutdown';

  @override
  String get engineLabRunStability => 'Run check';

  @override
  String get engineLabIdentity => 'Engine identity';

  @override
  String get engineLabIdentityHint => 'What the benchmark records, and what decides whether two runs are comparable';

  @override
  String get engineLabIdentityEmpty => 'Inspect an engine to see its id, fingerprint, backend and configuration digest.';

  @override
  String get engineLabInspect => 'Inspect';

  @override
  String get engineLabEnvironment => 'Environment';

  @override
  String get engineLabPlatform => 'Platform';

  @override
  String get engineLabVersion => 'Version';

  @override
  String get engineLabMetricsHint => 'CPU time and memory usage are not exposed by the engine protocol, so they are reported as unavailable rather than estimated.';

  @override
  String get engineLabLicense => 'Suite license';

  @override
  String get engineLabProgressionHint => 'Relative rating of each engine over the runs stored here';

  @override
  String get engineLabDeleteTitle => 'Delete this run?';

  @override
  String get engineLabReport => 'Benchmark report';

  @override
  String get engineLabReportMissing => 'Report unavailable';

  @override
  String get engineLabSummary => 'Summary';

  @override
  String get engineLabStarted => 'Started';

  @override
  String get engineLabDuration => 'Duration';

  @override
  String get engineLabTrigger => 'Trigger';

  @override
  String get engineLabStopped => 'Stopped because';

  @override
  String get engineLabFormat => 'Format';

  @override
  String get engineLabConfiguration => 'Configuration';

  @override
  String get engineLabFailures => 'Engine problems';

  @override
  String get engineLabStandings => 'Standings';

  @override
  String get engineLabGamesList => 'Games';

  @override
  String get engineLabShowAll => 'Show all';

  @override
  String get engineLabShowLess => 'Show fewer';

  @override
  String get engineLabExportReport => 'Copy report';

  @override
  String get engineLabMethod => 'Method';

  @override
  String get engineLabMethodBody => 'Bradley–Terry maximum likelihood over every rated game, centred on the average of the engines in the run. The 95% interval is the rating ± 1.96 × standard error, from the Fisher information of the fit. Adjudicated, aborted, cancelled and forfeited games are counted but not rated: a game that did not finish is not a draw.';

  @override
  String get exportJson => 'Export JSON';

  @override
  String get exportCsv => 'Export CSV';

  @override
  String get exportPgn => 'Export PGN';

  @override
  String get importBenchmark => 'Import';

  @override
  String get delete => 'Delete';

  @override
  String get copy => 'Copy';

  @override
  String get elo => 'Elo';

  @override
  String get refresh => 'Refresh';

  @override
  String get retry => 'Try again';

  @override
  String get engineLabAdaptiveStopping => 'Stop early once the rating is precise';

  @override
  String get engineLabAppVersion => 'App version';

  @override
  String get engineLabBackend => 'Backend';

  @override
  String get engineLabBalanceColors => 'Both colours per opening';

  @override
  String get engineLabBuiltIn => 'Ships with the app';

  @override
  String get engineLabCalibrationHint => 'A published rating for an engine in the run is the only way the relative scale becomes an absolute one.';

  @override
  String get engineLabCalibrationUnavailable => 'No calibrated rating for this run:';

  @override
  String get engineLabCompare => 'Compare two engines';

  @override
  String get engineLabCustom => 'custom';

  @override
  String get engineLabDeleteBody => 'The stored games, ratings and report are removed from this device. Exported copies are not affected.';

  @override
  String get engineLabFingerprint => 'Fingerprint';

  @override
  String get engineLabGauntletHint => 'Each challenger plays the reference engine; the reference is not rated against itself.';

  @override
  String get engineLabHash => 'Hash (MB)';

  @override
  String get engineLabHost => 'Host';

  @override
  String get engineLabInProgress => 'in progress';

  @override
  String get engineLabMaxGames => 'Max games';

  @override
  String get engineLabMaxMinutes => 'Max minutes';

  @override
  String get engineLabMovesPerPairing => 'Games per pairing';

  @override
  String get engineLabNoAnchors => 'No anchor declared; ratings stay relative.';

  @override
  String get engineLabNoFingerprint => 'unavailable';

  @override
  String get engineLabNoHistory => 'No stored runs';

  @override
  String get engineLabNoHistoryHint => 'Finished benchmarks are kept here with their games, ratings and report.';

  @override
  String get engineLabNoMetrics => 'no move timing recorded';

  @override
  String get engineLabNoRatedGames => 'This run produced no rating-eligible games.';

  @override
  String get engineLabNoRatingsHint => 'Run a benchmark and the ratings for the engines that took part appear here, with the interval behind each number.';

  @override
  String get engineLabOpeningSuite => 'Opening suite';

  @override
  String get engineLabPerformance => 'Performance';

  @override
  String get engineLabPlyCap => 'Ply cap';

  @override
  String get engineLabPlyCapHint => 'A game stopped here is adjudicated, not drawn';

  @override
  String get engineLabPreset => 'Preset';

  @override
  String get engineLabProgression => 'Progression';

  @override
  String get engineLabQualityHigh => 'precise';

  @override
  String get engineLabQualityInsufficient => 'too few games';

  @override
  String get engineLabQualityLow => 'rough';

  @override
  String get engineLabQualityModerate => 'usable';

  @override
  String get engineLabRated => 'rated';

  @override
  String get engineLabReference => 'Reference';

  @override
  String get engineLabRunning => 'Running…';

  @override
  String get engineLabSearchDepth => 'Search depth';

  @override
  String get engineLabSeed => 'Seed';

  @override
  String get engineLabStability => 'Stability';

  @override
  String get engineLabTargetStdErr => 'Stop at ±Elo';

  @override
  String get engineLabThreads => 'Threads';

  @override
  String get engineLabTimePerMoveMs => 'Time per move (ms)';

  @override
  String get engineLabUnchanged => 'unchanged';

  @override
  String get engineLabWarmUp => 'Warm-up games';

  @override
  String get engineLabWebNote => 'In a browser only the engines that ship with the app can run; a user-supplied executable cannot start.';

  @override
  String get engineLabZeroIsEngineDefault => '0 = engine\'s own';

  @override
  String get engineLabZeroIsNever => '0 = run the whole plan';

  @override
  String get engineLabZeroIsTime => '0 = use the clock';

  @override
  String get engineLabZeroIsUnlimited => '0 = no limit';

  @override
  String get engineLabAddAnchor => 'Add anchor';

  @override
  String get engineLabRemoveAnchor => 'Remove anchor';

  @override
  String get engineLabAnchorUsedHint => 'The first anchor that matches an engine in the run is used; an anchor for an engine that is not in the run cannot calibrate anything.';

  @override
  String get engineLabAnchorIntro => 'A published rating is only usable if its source, date, hardware and time control are recorded, and the engine takes part in the run.';

  @override
  String get engineLabAnchorRating => 'Published rating';

  @override
  String get engineLabAnchorScale => 'Rating list or scale';

  @override
  String get engineLabAnchorSource => 'Source (URL or publication)';

  @override
  String get engineLabAnchorDate => 'Published (YYYY-MM-DD)';

  @override
  String get engineLabAnchorHardware => 'Hardware';

  @override
  String get engineLabAnchorTimeControl => 'Time control';

  @override
  String get engineLabAnchorBudget => 'Move budget (ms)';

  @override
  String get engineLabAnchorMissing => 'Missing';

  @override
  String get engineLabAnchorDateHint => 'Write the publication date as YYYY-MM-DD.';
}

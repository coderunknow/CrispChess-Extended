import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'CrispChess'**
  String get appTitle;

  /// No description provided for @yourTurn.
  ///
  /// In en, this message translates to:
  /// **'Your turn'**
  String get yourTurn;

  /// No description provided for @whiteToMove.
  ///
  /// In en, this message translates to:
  /// **'White to move'**
  String get whiteToMove;

  /// No description provided for @blackToMove.
  ///
  /// In en, this message translates to:
  /// **'Black to move'**
  String get blackToMove;

  /// No description provided for @thinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking...'**
  String get thinking;

  /// No description provided for @engineError.
  ///
  /// In en, this message translates to:
  /// **'Engine error'**
  String get engineError;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading {engineName}...'**
  String loading(Object engineName);

  /// No description provided for @downloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading & initializing...'**
  String get downloading;

  /// No description provided for @engineReady.
  ///
  /// In en, this message translates to:
  /// **'{engineName} ready'**
  String engineReady(Object engineName);

  /// No description provided for @engineThinking.
  ///
  /// In en, this message translates to:
  /// **'{engineName} is thinking...'**
  String engineThinking(Object engineName);

  /// No description provided for @newGame.
  ///
  /// In en, this message translates to:
  /// **'New Game'**
  String get newGame;

  /// No description provided for @newGameConfirm.
  ///
  /// In en, this message translates to:
  /// **'Current game will be lost.'**
  String get newGameConfirm;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @about.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get about;

  /// No description provided for @aboutCrispChess.
  ///
  /// In en, this message translates to:
  /// **'About CrispChess'**
  String get aboutCrispChess;

  /// No description provided for @puzzles.
  ///
  /// In en, this message translates to:
  /// **'Puzzles'**
  String get puzzles;

  /// No description provided for @flipBoard.
  ///
  /// In en, this message translates to:
  /// **'Flip Board'**
  String get flipBoard;

  /// No description provided for @copyPgn.
  ///
  /// In en, this message translates to:
  /// **'Copy PGN'**
  String get copyPgn;

  /// No description provided for @pastePgn.
  ///
  /// In en, this message translates to:
  /// **'Paste PGN'**
  String get pastePgn;

  /// No description provided for @loadFen.
  ///
  /// In en, this message translates to:
  /// **'Load FEN'**
  String get loadFen;

  /// No description provided for @setupPosition.
  ///
  /// In en, this message translates to:
  /// **'Setup Position'**
  String get setupPosition;

  /// No description provided for @pgnDatabase.
  ///
  /// In en, this message translates to:
  /// **'PGN Database'**
  String get pgnDatabase;

  /// No description provided for @offerDraw.
  ///
  /// In en, this message translates to:
  /// **'Offer Draw'**
  String get offerDraw;

  /// No description provided for @resign.
  ///
  /// In en, this message translates to:
  /// **'Resign'**
  String get resign;

  /// No description provided for @resignConfirm.
  ///
  /// In en, this message translates to:
  /// **'{engineName} wins by resignation.'**
  String resignConfirm(Object engineName);

  /// No description provided for @drawDeclined.
  ///
  /// In en, this message translates to:
  /// **'{engineName} declines the draw offer.'**
  String drawDeclined(Object engineName);

  /// No description provided for @drawAgreed.
  ///
  /// In en, this message translates to:
  /// **'Draw agreed'**
  String get drawAgreed;

  /// No description provided for @youResigned.
  ///
  /// In en, this message translates to:
  /// **'You resigned'**
  String get youResigned;

  /// No description provided for @gameResumed.
  ///
  /// In en, this message translates to:
  /// **'Game resumed'**
  String get gameResumed;

  /// No description provided for @resumeGame.
  ///
  /// In en, this message translates to:
  /// **'Resume game?'**
  String get resumeGame;

  /// No description provided for @savedGameMoves.
  ///
  /// In en, this message translates to:
  /// **'You have a saved game ({count} moves).'**
  String savedGameMoves(Object count);

  /// No description provided for @discard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @review.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get review;

  /// No description provided for @undo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get undo;

  /// No description provided for @redo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get redo;

  /// No description provided for @hint.
  ///
  /// In en, this message translates to:
  /// **'Hint'**
  String get hint;

  /// No description provided for @analyze.
  ///
  /// In en, this message translates to:
  /// **'Analyze'**
  String get analyze;

  /// No description provided for @abort.
  ///
  /// In en, this message translates to:
  /// **'Abort'**
  String get abort;

  /// No description provided for @playAsWhite.
  ///
  /// In en, this message translates to:
  /// **'White'**
  String get playAsWhite;

  /// No description provided for @playAsBlack.
  ///
  /// In en, this message translates to:
  /// **'Black'**
  String get playAsBlack;

  /// No description provided for @playAsRandom.
  ///
  /// In en, this message translates to:
  /// **'Random'**
  String get playAsRandom;

  /// No description provided for @twoPlayer.
  ///
  /// In en, this message translates to:
  /// **'Two Player (local)'**
  String get twoPlayer;

  /// No description provided for @passAndPlay.
  ///
  /// In en, this message translates to:
  /// **'Pass and play'**
  String get passAndPlay;

  /// No description provided for @playAs.
  ///
  /// In en, this message translates to:
  /// **'Play as'**
  String get playAs;

  /// No description provided for @chessEngine.
  ///
  /// In en, this message translates to:
  /// **'Chess Engine'**
  String get chessEngine;

  /// No description provided for @opponentStrength.
  ///
  /// In en, this message translates to:
  /// **'Opponent Strength'**
  String get opponentStrength;

  /// No description provided for @hintDepth.
  ///
  /// In en, this message translates to:
  /// **'Hint Depth'**
  String get hintDepth;

  /// No description provided for @analysisDepth.
  ///
  /// In en, this message translates to:
  /// **'Analysis Depth: {depth}'**
  String analysisDepth(Object depth);

  /// No description provided for @hintEngine.
  ///
  /// In en, this message translates to:
  /// **'Hint Engine'**
  String get hintEngine;

  /// No description provided for @sameAsOpponent.
  ///
  /// In en, this message translates to:
  /// **'Same as opponent'**
  String get sameAsOpponent;

  /// No description provided for @game.
  ///
  /// In en, this message translates to:
  /// **'Game'**
  String get game;

  /// No description provided for @showValidMoves.
  ///
  /// In en, this message translates to:
  /// **'Show Valid Moves'**
  String get showValidMoves;

  /// No description provided for @showValidMovesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Highlight legal moves when selecting a piece'**
  String get showValidMovesSubtitle;

  /// No description provided for @allowUndo.
  ///
  /// In en, this message translates to:
  /// **'Allow Undo'**
  String get allowUndo;

  /// No description provided for @allowUndoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Disable for discipline mode'**
  String get allowUndoSubtitle;

  /// No description provided for @solidBlackPieces.
  ///
  /// In en, this message translates to:
  /// **'Solid Black Pieces'**
  String get solidBlackPieces;

  /// No description provided for @solidBlackPiecesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Render black pieces as solid black instead of grey gradient'**
  String get solidBlackPiecesSubtitle;

  /// No description provided for @animationSpeed.
  ///
  /// In en, this message translates to:
  /// **'Animation Speed'**
  String get animationSpeed;

  /// No description provided for @instant.
  ///
  /// In en, this message translates to:
  /// **'Instant'**
  String get instant;

  /// No description provided for @fast.
  ///
  /// In en, this message translates to:
  /// **'Fast'**
  String get fast;

  /// No description provided for @normal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get normal;

  /// No description provided for @slow.
  ///
  /// In en, this message translates to:
  /// **'Slow'**
  String get slow;

  /// No description provided for @timeControl.
  ///
  /// In en, this message translates to:
  /// **'Time Control'**
  String get timeControl;

  /// No description provided for @playAsBlackSetting.
  ///
  /// In en, this message translates to:
  /// **'Play as Black'**
  String get playAsBlackSetting;

  /// No description provided for @playAsBlackSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Engine makes the first move'**
  String get playAsBlackSubtitle;

  /// No description provided for @pieceStyle.
  ///
  /// In en, this message translates to:
  /// **'Piece Style'**
  String get pieceStyle;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get systemDefault;

  /// No description provided for @system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get system;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @darkAmoled.
  ///
  /// In en, this message translates to:
  /// **'Dark (AMOLED)'**
  String get darkAmoled;

  /// No description provided for @resetToDefaults.
  ///
  /// In en, this message translates to:
  /// **'Reset to defaults'**
  String get resetToDefaults;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @pgnCopied.
  ///
  /// In en, this message translates to:
  /// **'PGN copied to clipboard'**
  String get pgnCopied;

  /// No description provided for @pgnLoaded.
  ///
  /// In en, this message translates to:
  /// **'PGN loaded'**
  String get pgnLoaded;

  /// No description provided for @invalidPgn.
  ///
  /// In en, this message translates to:
  /// **'Invalid PGN'**
  String get invalidPgn;

  /// No description provided for @noPgnInClipboard.
  ///
  /// In en, this message translates to:
  /// **'No PGN found in clipboard'**
  String get noPgnInClipboard;

  /// No description provided for @noMovesYet.
  ///
  /// In en, this message translates to:
  /// **'No moves yet'**
  String get noMovesYet;

  /// No description provided for @solved.
  ///
  /// In en, this message translates to:
  /// **'solved'**
  String get solved;

  /// No description provided for @showSolution.
  ///
  /// In en, this message translates to:
  /// **'Show Solution'**
  String get showSolution;

  /// No description provided for @nextPuzzle.
  ///
  /// In en, this message translates to:
  /// **'Next Puzzle'**
  String get nextPuzzle;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @wrongMove.
  ///
  /// In en, this message translates to:
  /// **'Wrong move. Try again. ({remaining} left)'**
  String wrongMove(Object remaining);

  /// No description provided for @puzzleSolved.
  ///
  /// In en, this message translates to:
  /// **'Correct! Puzzle solved.'**
  String get puzzleSolved;

  /// No description provided for @findNextMove.
  ///
  /// In en, this message translates to:
  /// **'Correct! Find the next move.'**
  String get findNextMove;

  /// No description provided for @gameSummary.
  ///
  /// In en, this message translates to:
  /// **'Game Summary'**
  String get gameSummary;

  /// No description provided for @yourAccuracy.
  ///
  /// In en, this message translates to:
  /// **'Your Accuracy'**
  String get yourAccuracy;

  /// No description provided for @accuracy.
  ///
  /// In en, this message translates to:
  /// **'Accuracy'**
  String get accuracy;

  /// No description provided for @good.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get good;

  /// No description provided for @mistakes.
  ///
  /// In en, this message translates to:
  /// **'Mistakes'**
  String get mistakes;

  /// No description provided for @myMistakes.
  ///
  /// In en, this message translates to:
  /// **'My Mistakes'**
  String get myMistakes;

  /// No description provided for @blunders.
  ///
  /// In en, this message translates to:
  /// **'Blunders'**
  String get blunders;

  /// No description provided for @evaluation.
  ///
  /// In en, this message translates to:
  /// **'Evaluation'**
  String get evaluation;

  /// No description provided for @yourBestMove.
  ///
  /// In en, this message translates to:
  /// **'Your Best Move'**
  String get yourBestMove;

  /// No description provided for @biggestMistake.
  ///
  /// In en, this message translates to:
  /// **'Biggest Mistake'**
  String get biggestMistake;

  /// No description provided for @moves.
  ///
  /// In en, this message translates to:
  /// **'Moves'**
  String get moves;

  /// No description provided for @tapToViewPosition.
  ///
  /// In en, this message translates to:
  /// **'Tap to view position'**
  String get tapToViewPosition;

  /// No description provided for @moveN.
  ///
  /// In en, this message translates to:
  /// **'Move {n}'**
  String moveN(Object n);

  /// No description provided for @welcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome to CrispChess'**
  String get welcome;

  /// No description provided for @welcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Play chess against AI engines or a friend.'**
  String get welcomeSubtitle;

  /// No description provided for @letsPlay.
  ///
  /// In en, this message translates to:
  /// **'Let\'s play!'**
  String get letsPlay;

  /// No description provided for @switchToBuiltIn.
  ///
  /// In en, this message translates to:
  /// **'Switch to Built-in'**
  String get switchToBuiltIn;

  /// No description provided for @failedToInitialize.
  ///
  /// In en, this message translates to:
  /// **'{engineName}: failed to initialize'**
  String failedToInitialize(Object engineName);

  /// No description provided for @checkmate.
  ///
  /// In en, this message translates to:
  /// **'Checkmate'**
  String get checkmate;

  /// No description provided for @stalemate.
  ///
  /// In en, this message translates to:
  /// **'Stalemate'**
  String get stalemate;

  /// No description provided for @drawThreefold.
  ///
  /// In en, this message translates to:
  /// **'Draw — threefold repetition'**
  String get drawThreefold;

  /// No description provided for @drawInsufficient.
  ///
  /// In en, this message translates to:
  /// **'Draw — insufficient material'**
  String get drawInsufficient;

  /// No description provided for @drawFiftyMove.
  ///
  /// In en, this message translates to:
  /// **'Draw — fifty-move rule'**
  String get drawFiftyMove;

  /// No description provided for @resignation.
  ///
  /// In en, this message translates to:
  /// **'Resignation'**
  String get resignation;

  /// No description provided for @drawByAgreement.
  ///
  /// In en, this message translates to:
  /// **'Draw by agreement'**
  String get drawByAgreement;

  /// No description provided for @gameOver.
  ///
  /// In en, this message translates to:
  /// **'Game Over'**
  String get gameOver;

  /// No description provided for @boardScreenshot.
  ///
  /// In en, this message translates to:
  /// **'Board Screenshot'**
  String get boardScreenshot;

  /// No description provided for @clearAnnotations.
  ///
  /// In en, this message translates to:
  /// **'Clear Annotations'**
  String get clearAnnotations;

  /// No description provided for @bookmarkPosition.
  ///
  /// In en, this message translates to:
  /// **'Bookmark Position'**
  String get bookmarkPosition;

  /// No description provided for @positionBookmarked.
  ///
  /// In en, this message translates to:
  /// **'Position bookmarked'**
  String get positionBookmarked;

  /// No description provided for @askCoach.
  ///
  /// In en, this message translates to:
  /// **'Ask Coach'**
  String get askCoach;

  /// No description provided for @drills.
  ///
  /// In en, this message translates to:
  /// **'Drills'**
  String get drills;

  /// No description provided for @engineVsEngine.
  ///
  /// In en, this message translates to:
  /// **'Engine vs Engine'**
  String get engineVsEngine;

  /// No description provided for @stats.
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get stats;

  /// No description provided for @statsAndAchievements.
  ///
  /// In en, this message translates to:
  /// **'Stats & Achievements'**
  String get statsAndAchievements;

  /// No description provided for @achievements.
  ///
  /// In en, this message translates to:
  /// **'Achievements'**
  String get achievements;

  /// No description provided for @games.
  ///
  /// In en, this message translates to:
  /// **'Games'**
  String get games;

  /// No description provided for @wins.
  ///
  /// In en, this message translates to:
  /// **'Wins'**
  String get wins;

  /// No description provided for @badges.
  ///
  /// In en, this message translates to:
  /// **'Badges'**
  String get badges;

  /// No description provided for @engineManager.
  ///
  /// In en, this message translates to:
  /// **'Engine Manager'**
  String get engineManager;

  /// No description provided for @engineManagerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Engine Manager — Add Custom UCI Engines'**
  String get engineManagerSubtitle;

  /// No description provided for @addEngine.
  ///
  /// In en, this message translates to:
  /// **'Add Engine'**
  String get addEngine;

  /// No description provided for @addUciEngine.
  ///
  /// In en, this message translates to:
  /// **'Add UCI Engine'**
  String get addUciEngine;

  /// No description provided for @engineBinaryPath.
  ///
  /// In en, this message translates to:
  /// **'Engine binary path'**
  String get engineBinaryPath;

  /// No description provided for @displayName.
  ///
  /// In en, this message translates to:
  /// **'Display name (optional)'**
  String get displayName;

  /// No description provided for @leaveBlankAutoDetect.
  ///
  /// In en, this message translates to:
  /// **'Leave blank to auto-detect'**
  String get leaveBlankAutoDetect;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @configure.
  ///
  /// In en, this message translates to:
  /// **'Configure'**
  String get configure;

  /// No description provided for @probingEngine.
  ///
  /// In en, this message translates to:
  /// **'Probing engine...'**
  String get probingEngine;

  /// No description provided for @engineAdded.
  ///
  /// In en, this message translates to:
  /// **'Added: {name}'**
  String engineAdded(Object name);

  /// No description provided for @engineInitFailed.
  ///
  /// In en, this message translates to:
  /// **'Engine failed to initialize: {error}'**
  String engineInitFailed(Object error);

  /// No description provided for @loadingEngineOptions.
  ///
  /// In en, this message translates to:
  /// **'Loading engine options...'**
  String get loadingEngineOptions;

  /// No description provided for @noCustomEngines.
  ///
  /// In en, this message translates to:
  /// **'No custom engines added'**
  String get noCustomEngines;

  /// No description provided for @noCustomEnginesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add any UCI-compatible chess engine\nby providing the path to its binary.'**
  String get noCustomEnginesSubtitle;

  /// No description provided for @removeEngine.
  ///
  /// In en, this message translates to:
  /// **'Remove Engine?'**
  String get removeEngine;

  /// No description provided for @removeEngineConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{name}\" from your engine list?'**
  String removeEngineConfirm(Object name);

  /// No description provided for @noConfigurableOptions.
  ///
  /// In en, this message translates to:
  /// **'No configurable options'**
  String get noConfigurableOptions;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @run.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get run;

  /// No description provided for @rangeMinMax.
  ///
  /// In en, this message translates to:
  /// **'Range: {min} – {max}'**
  String rangeMinMax(Object min, Object max);

  /// No description provided for @positionEditor.
  ///
  /// In en, this message translates to:
  /// **'Position Editor'**
  String get positionEditor;

  /// No description provided for @startingPosition.
  ///
  /// In en, this message translates to:
  /// **'Starting position'**
  String get startingPosition;

  /// No description provided for @clearBoard.
  ///
  /// In en, this message translates to:
  /// **'Clear board'**
  String get clearBoard;

  /// No description provided for @sideToMove.
  ///
  /// In en, this message translates to:
  /// **'Side to move:'**
  String get sideToMove;

  /// No description provided for @castling.
  ///
  /// In en, this message translates to:
  /// **'Castling:'**
  String get castling;

  /// No description provided for @copyFen.
  ///
  /// In en, this message translates to:
  /// **'Copy FEN'**
  String get copyFen;

  /// No description provided for @fenCopied.
  ///
  /// In en, this message translates to:
  /// **'FEN copied'**
  String get fenCopied;

  /// No description provided for @loadPosition.
  ///
  /// In en, this message translates to:
  /// **'Load Position'**
  String get loadPosition;

  /// No description provided for @invalidFen.
  ///
  /// In en, this message translates to:
  /// **'Invalid FEN string'**
  String get invalidFen;

  /// No description provided for @positionLoaded.
  ///
  /// In en, this message translates to:
  /// **'Position loaded from FEN'**
  String get positionLoaded;

  /// No description provided for @customPositionLoaded.
  ///
  /// In en, this message translates to:
  /// **'Custom position loaded'**
  String get customPositionLoaded;

  /// No description provided for @pawnsOnEdgeRank.
  ///
  /// In en, this message translates to:
  /// **'Pawns cannot be on the first or last rank'**
  String get pawnsOnEdgeRank;

  /// No description provided for @needOneWhiteKing.
  ///
  /// In en, this message translates to:
  /// **'White must have exactly one king'**
  String get needOneWhiteKing;

  /// No description provided for @needOneBlackKing.
  ///
  /// In en, this message translates to:
  /// **'Black must have exactly one king'**
  String get needOneBlackKing;

  /// No description provided for @pasteFenHint.
  ///
  /// In en, this message translates to:
  /// **'Paste FEN string...'**
  String get pasteFenHint;

  /// No description provided for @pasteFromClipboard.
  ///
  /// In en, this message translates to:
  /// **'Paste from clipboard'**
  String get pasteFromClipboard;

  /// No description provided for @load.
  ///
  /// In en, this message translates to:
  /// **'Load'**
  String get load;

  /// No description provided for @databaseStatistics.
  ///
  /// In en, this message translates to:
  /// **'Database Statistics'**
  String get databaseStatistics;

  /// No description provided for @nGames.
  ///
  /// In en, this message translates to:
  /// **'{count} games'**
  String nGames(Object count);

  /// No description provided for @results.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get results;

  /// No description provided for @whiteWins.
  ///
  /// In en, this message translates to:
  /// **'White wins'**
  String get whiteWins;

  /// No description provided for @blackWins.
  ///
  /// In en, this message translates to:
  /// **'Black wins'**
  String get blackWins;

  /// No description provided for @draws.
  ///
  /// In en, this message translates to:
  /// **'Draws'**
  String get draws;

  /// No description provided for @topOpenings.
  ///
  /// In en, this message translates to:
  /// **'Top Openings (ECO)'**
  String get topOpenings;

  /// No description provided for @mostActivePlayers.
  ///
  /// In en, this message translates to:
  /// **'Most Active Players'**
  String get mostActivePlayers;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @noDatabaseLoaded.
  ///
  /// In en, this message translates to:
  /// **'No database loaded'**
  String get noDatabaseLoaded;

  /// No description provided for @noDatabaseSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Copy a PGN file with multiple games\nto your clipboard, then tap the paste icon.'**
  String get noDatabaseSubtitle;

  /// No description provided for @searchByPlayer.
  ///
  /// In en, this message translates to:
  /// **'Search by player...'**
  String get searchByPlayer;

  /// No description provided for @result.
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get result;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @draw.
  ///
  /// In en, this message translates to:
  /// **'Draw'**
  String get draw;

  /// No description provided for @noGamesFound.
  ///
  /// In en, this message translates to:
  /// **'No games found in PGN'**
  String get noGamesFound;

  /// No description provided for @noPgnData.
  ///
  /// In en, this message translates to:
  /// **'No PGN data in clipboard'**
  String get noPgnData;

  /// No description provided for @gameLoadedFromDb.
  ///
  /// In en, this message translates to:
  /// **'Game loaded from database'**
  String get gameLoadedFromDb;

  /// No description provided for @match.
  ///
  /// In en, this message translates to:
  /// **'Match'**
  String get match;

  /// No description provided for @tournament.
  ///
  /// In en, this message translates to:
  /// **'Tournament'**
  String get tournament;

  /// No description provided for @selectTwoDifferent.
  ///
  /// In en, this message translates to:
  /// **'Select two different engines'**
  String get selectTwoDifferent;

  /// No description provided for @selectAtLeast3.
  ///
  /// In en, this message translates to:
  /// **'Select at least 3 engines'**
  String get selectAtLeast3;

  /// No description provided for @selectEngines.
  ///
  /// In en, this message translates to:
  /// **'Select engines ({count} selected, min 3):'**
  String selectEngines(Object count);

  /// No description provided for @depth.
  ///
  /// In en, this message translates to:
  /// **'Depth'**
  String get depth;

  /// No description provided for @startMatch.
  ///
  /// In en, this message translates to:
  /// **'Start Match'**
  String get startMatch;

  /// No description provided for @startTournament.
  ///
  /// In en, this message translates to:
  /// **'Start Tournament'**
  String get startTournament;

  /// No description provided for @stopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get stopped;

  /// No description provided for @vs.
  ///
  /// In en, this message translates to:
  /// **'vs'**
  String get vs;

  /// No description provided for @multiEngineAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Multi-Engine Analysis'**
  String get multiEngineAnalysis;

  /// No description provided for @multiEngine.
  ///
  /// In en, this message translates to:
  /// **'Multi-Engine'**
  String get multiEngine;

  /// No description provided for @stopMultiEngine.
  ///
  /// In en, this message translates to:
  /// **'Stop multi-engine'**
  String get stopMultiEngine;

  /// No description provided for @selectEnginesToCompare.
  ///
  /// In en, this message translates to:
  /// **'Select engines to compare:'**
  String get selectEnginesToCompare;

  /// No description provided for @currentOpponent.
  ///
  /// In en, this message translates to:
  /// **'(current opponent)'**
  String get currentOpponent;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @multiEngineFailed.
  ///
  /// In en, this message translates to:
  /// **'Multi-engine failed: {error}'**
  String multiEngineFailed(Object error);

  /// No description provided for @reAnalyze.
  ///
  /// In en, this message translates to:
  /// **'Re-analyze'**
  String get reAnalyze;

  /// No description provided for @tapRefreshToAnalyze.
  ///
  /// In en, this message translates to:
  /// **'Tap refresh to analyze'**
  String get tapRefreshToAnalyze;

  /// No description provided for @engineLoading.
  ///
  /// In en, this message translates to:
  /// **'Engine loading...'**
  String get engineLoading;

  /// No description provided for @bestMove.
  ///
  /// In en, this message translates to:
  /// **'Best: {move}'**
  String bestMove(Object move);

  /// No description provided for @analysis.
  ///
  /// In en, this message translates to:
  /// **'Analysis'**
  String get analysis;

  /// No description provided for @engineNotReady.
  ///
  /// In en, this message translates to:
  /// **'Engine not ready'**
  String get engineNotReady;

  /// No description provided for @positionRestored.
  ///
  /// In en, this message translates to:
  /// **'Position restored'**
  String get positionRestored;

  /// No description provided for @resignQuestion.
  ///
  /// In en, this message translates to:
  /// **'Resign?'**
  String get resignQuestion;

  /// No description provided for @dailyLogin.
  ///
  /// In en, this message translates to:
  /// **'Daily login: +{xp} XP (streak: {streak})'**
  String dailyLogin(Object xp, Object streak);

  /// No description provided for @levelUp.
  ///
  /// In en, this message translates to:
  /// **'Level Up!'**
  String get levelUp;

  /// No description provided for @youReached.
  ///
  /// In en, this message translates to:
  /// **'You reached {level}!'**
  String youReached(Object level);

  /// No description provided for @continueButton.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueButton;

  /// No description provided for @couldNotCaptureBoard.
  ///
  /// In en, this message translates to:
  /// **'Could not capture board'**
  String get couldNotCaptureBoard;

  /// No description provided for @boardCaptured.
  ///
  /// In en, this message translates to:
  /// **'Board captured ({size} KB)'**
  String boardCaptured(Object size);

  /// No description provided for @screenshotFailed.
  ///
  /// In en, this message translates to:
  /// **'Screenshot failed: {error}'**
  String screenshotFailed(Object error);

  /// No description provided for @illegalMove.
  ///
  /// In en, this message translates to:
  /// **'Illegal Move!'**
  String get illegalMove;

  /// No description provided for @premove.
  ///
  /// In en, this message translates to:
  /// **'Premove: {move}'**
  String premove(Object move);

  /// No description provided for @premoveIllegal.
  ///
  /// In en, this message translates to:
  /// **'Premove illegal — your turn'**
  String get premoveIllegal;

  /// No description provided for @drillComplete.
  ///
  /// In en, this message translates to:
  /// **'Drill Complete!'**
  String get drillComplete;

  /// No description provided for @correctOnFirstTry.
  ///
  /// In en, this message translates to:
  /// **'{correct} / {total} correct on first try'**
  String correctOnFirstTry(Object correct, Object total);

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @stepOf.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String stepOf(Object current, Object total);

  /// No description provided for @next.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// No description provided for @finish.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get finish;

  /// No description provided for @findBestMove.
  ///
  /// In en, this message translates to:
  /// **'Find the best move.'**
  String get findBestMove;

  /// No description provided for @correct.
  ///
  /// In en, this message translates to:
  /// **'Correct!'**
  String get correct;

  /// No description provided for @notQuiteTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Not quite — try again!'**
  String get notQuiteTryAgain;

  /// No description provided for @aiCoach.
  ///
  /// In en, this message translates to:
  /// **'AI Coach'**
  String get aiCoach;

  /// No description provided for @privacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacy;

  /// No description provided for @privacyNotice.
  ///
  /// In en, this message translates to:
  /// **'Your API key is stored locally on your device only. Game data (FEN/PGN) is sent directly to your chosen AI provider. CrispChess does not store, log, or transmit any data to its own servers. You can delete your API key at any time.'**
  String get privacyNotice;

  /// No description provided for @enterApiKey.
  ///
  /// In en, this message translates to:
  /// **'Enter your API key to get started:'**
  String get enterApiKey;

  /// No description provided for @keyConfigured.
  ///
  /// In en, this message translates to:
  /// **'{provider} key configured'**
  String keyConfigured(Object provider);

  /// No description provided for @removeKey.
  ///
  /// In en, this message translates to:
  /// **'Remove key'**
  String get removeKey;

  /// No description provided for @noMistakesYet.
  ///
  /// In en, this message translates to:
  /// **'No mistakes tracked yet!'**
  String get noMistakesYet;

  /// No description provided for @noMistakesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Play games with analysis enabled to track blunders.'**
  String get noMistakesSubtitle;

  /// No description provided for @clearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get clearAll;

  /// No description provided for @unknownMove.
  ///
  /// In en, this message translates to:
  /// **'Unknown move'**
  String get unknownMove;

  /// No description provided for @serviceProvider.
  ///
  /// In en, this message translates to:
  /// **'Service Provider'**
  String get serviceProvider;

  /// No description provided for @license.
  ///
  /// In en, this message translates to:
  /// **'License'**
  String get license;

  /// No description provided for @chessEngines.
  ///
  /// In en, this message translates to:
  /// **'Chess Engines'**
  String get chessEngines;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @disclaimer.
  ///
  /// In en, this message translates to:
  /// **'Disclaimer'**
  String get disclaimer;

  /// No description provided for @sourceCode.
  ///
  /// In en, this message translates to:
  /// **'Source Code'**
  String get sourceCode;

  /// No description provided for @urlCopied.
  ///
  /// In en, this message translates to:
  /// **'URL copied to clipboard'**
  String get urlCopied;

  /// No description provided for @contributionsWelcome.
  ///
  /// In en, this message translates to:
  /// **'Contributions welcome. Open an issue first for major changes.'**
  String get contributionsWelcome;

  /// No description provided for @openSourceLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open Source Licenses'**
  String get openSourceLicenses;

  /// No description provided for @hintsAndAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Hints & Analysis'**
  String get hintsAndAnalysis;

  /// No description provided for @maia3Model.
  ///
  /// In en, this message translates to:
  /// **'Maia3 Model'**
  String get maia3Model;

  /// No description provided for @stockfishVersion.
  ///
  /// In en, this message translates to:
  /// **'Stockfish Version'**
  String get stockfishVersion;

  /// Title of the Lynx WASM build picker
  ///
  /// In en, this message translates to:
  /// **'Lynx Build'**
  String get lynxBuild;

  /// Note that switching Lynx builds needs a page reload
  ///
  /// In en, this message translates to:
  /// **'The engine loads once per page, so a change takes effect after a reload.'**
  String get lynxBuildNote;

  /// No description provided for @maiaWeight.
  ///
  /// In en, this message translates to:
  /// **'Maia Weight (ELO level)'**
  String get maiaWeight;

  /// No description provided for @gameMode.
  ///
  /// In en, this message translates to:
  /// **'Game Mode'**
  String get gameMode;

  /// No description provided for @standard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get standard;

  /// No description provided for @kingOfTheHill.
  ///
  /// In en, this message translates to:
  /// **'King of the Hill'**
  String get kingOfTheHill;

  /// No description provided for @threeCheck.
  ///
  /// In en, this message translates to:
  /// **'Three-Check'**
  String get threeCheck;

  /// No description provided for @customTimeControl.
  ///
  /// In en, this message translates to:
  /// **'Custom...'**
  String get customTimeControl;

  /// No description provided for @boardColorThemeLabel.
  ///
  /// In en, this message translates to:
  /// **'Board Color'**
  String get boardColorThemeLabel;

  /// No description provided for @notationStyleLabel.
  ///
  /// In en, this message translates to:
  /// **'Notation'**
  String get notationStyleLabel;

  /// No description provided for @blindfoldMode.
  ///
  /// In en, this message translates to:
  /// **'Blindfold Mode'**
  String get blindfoldMode;

  /// No description provided for @blindfoldModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hide pieces — play by memory'**
  String get blindfoldModeSubtitle;

  /// No description provided for @importExport.
  ///
  /// In en, this message translates to:
  /// **'Import / Export'**
  String get importExport;

  /// No description provided for @boardToolsMenu.
  ///
  /// In en, this message translates to:
  /// **'Board Tools'**
  String get boardToolsMenu;

  /// No description provided for @learnMenu.
  ///
  /// In en, this message translates to:
  /// **'Learn'**
  String get learnMenu;

  /// No description provided for @progressMenu.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get progressMenu;

  /// No description provided for @openingExplorer.
  ///
  /// In en, this message translates to:
  /// **'Opening Explorer'**
  String get openingExplorer;

  /// No description provided for @coordinateTrainer.
  ///
  /// In en, this message translates to:
  /// **'Coordinate Trainer'**
  String get coordinateTrainer;

  /// No description provided for @gameHistory.
  ///
  /// In en, this message translates to:
  /// **'Game History'**
  String get gameHistory;

  /// No description provided for @humanLens.
  ///
  /// In en, this message translates to:
  /// **'Human Lens'**
  String get humanLens;

  /// No description provided for @humanLensSubtitle.
  ///
  /// In en, this message translates to:
  /// **'How players rated {elo} see this position'**
  String humanLensSubtitle(Object elo);

  /// No description provided for @humanLensLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading Maia (25 MB, first time only)…'**
  String get humanLensLoading;

  /// No description provided for @humanLensThinking.
  ///
  /// In en, this message translates to:
  /// **'Asking the players…'**
  String get humanLensThinking;

  /// No description provided for @humanLensBestMove.
  ///
  /// In en, this message translates to:
  /// **'Engine\'s move'**
  String get humanLensBestMove;

  /// No description provided for @humanLensFoundBy.
  ///
  /// In en, this message translates to:
  /// **'{percent}% of {elo} players find it'**
  String humanLensFoundBy(Object percent, Object elo);

  /// No description provided for @humanLensNaturalFrom.
  ///
  /// In en, this message translates to:
  /// **'Most players find it from about {elo}'**
  String humanLensNaturalFrom(Object elo);

  /// No description provided for @humanLensNeverNatural.
  ///
  /// In en, this message translates to:
  /// **'Even at 2300 most players miss it'**
  String get humanLensNeverNatural;

  /// No description provided for @humanLensTrap.
  ///
  /// In en, this message translates to:
  /// **'Trap'**
  String get humanLensTrap;

  /// No description provided for @humanLensTrapText.
  ///
  /// In en, this message translates to:
  /// **'{percent}% of {elo} players play {move}, and it\'s a mistake.'**
  String humanLensTrapText(Object percent, Object elo, Object move);

  /// No description provided for @humanLensCandidates.
  ///
  /// In en, this message translates to:
  /// **'What {elo} players play'**
  String humanLensCandidates(Object elo);

  /// No description provided for @humanLensByRating.
  ///
  /// In en, this message translates to:
  /// **'Who finds the engine\'s move'**
  String get humanLensByRating;

  /// No description provided for @humanLensUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Human Lens is for standard chess only.'**
  String get humanLensUnsupported;

  /// No description provided for @humanLensGameOver.
  ///
  /// In en, this message translates to:
  /// **'The game is over, so there are no moves to look at.'**
  String get humanLensGameOver;

  /// No description provided for @humanLensError.
  ///
  /// In en, this message translates to:
  /// **'Human Lens failed: {error}'**
  String humanLensError(Object error);

  /// No description provided for @findabilityObvious.
  ///
  /// In en, this message translates to:
  /// **'Obvious'**
  String get findabilityObvious;

  /// No description provided for @findabilityNatural.
  ///
  /// In en, this message translates to:
  /// **'Natural'**
  String get findabilityNatural;

  /// No description provided for @findabilityFindable.
  ///
  /// In en, this message translates to:
  /// **'Findable'**
  String get findabilityFindable;

  /// No description provided for @findabilityHard.
  ///
  /// In en, this message translates to:
  /// **'Hard'**
  String get findabilityHard;

  /// No description provided for @findabilityVeryHard.
  ///
  /// In en, this message translates to:
  /// **'Very hard'**
  String get findabilityVeryHard;

  /// No description provided for @humanReview.
  ///
  /// In en, this message translates to:
  /// **'Human review'**
  String get humanReview;

  /// No description provided for @humanReviewIntro.
  ///
  /// In en, this message translates to:
  /// **'See the game the way Maia sees human players: which misses were hard to find, which were slips, and what rating your moves looked like.'**
  String get humanReviewIntro;

  /// No description provided for @humanReviewStart.
  ///
  /// In en, this message translates to:
  /// **'Review with Maia'**
  String get humanReviewStart;

  /// No description provided for @humanReviewProgress.
  ///
  /// In en, this message translates to:
  /// **'Move {done} of {total}…'**
  String humanReviewProgress(Object done, Object total);

  /// No description provided for @humanReviewPlayedLike.
  ///
  /// In en, this message translates to:
  /// **'Your moves looked like a player rated about {elo}'**
  String humanReviewPlayedLike(Object elo);

  /// No description provided for @humanReviewHardMiss.
  ///
  /// In en, this message translates to:
  /// **'Hard to find'**
  String get humanReviewHardMiss;

  /// No description provided for @humanReviewSlip.
  ///
  /// In en, this message translates to:
  /// **'Slip'**
  String get humanReviewSlip;

  /// No description provided for @humanReviewMissText.
  ///
  /// In en, this message translates to:
  /// **'{played} instead of {best}: {percent}% of {elo} players find it'**
  String humanReviewMissText(
      Object played, Object best, Object percent, Object elo);

  /// No description provided for @humanReviewNoMistakes.
  ///
  /// In en, this message translates to:
  /// **'No costly misses in this game.'**
  String get humanReviewNoMistakes;

  /// No description provided for @humanReviewRatingLabel.
  ///
  /// In en, this message translates to:
  /// **'Compare with players rated'**
  String get humanReviewRatingLabel;

  /// No description provided for @scanBoard.
  ///
  /// In en, this message translates to:
  /// **'Scan board'**
  String get scanBoard;

  /// No description provided for @scanBoardHint.
  ///
  /// In en, this message translates to:
  /// **'Choose an image: a screenshot or book diagram (Diagram), or a photo of a real board (Photo).'**
  String get scanBoardHint;

  /// No description provided for @scanPickImage.
  ///
  /// In en, this message translates to:
  /// **'Choose image'**
  String get scanPickImage;

  /// No description provided for @scanRecognizing.
  ///
  /// In en, this message translates to:
  /// **'Recognizing…'**
  String get scanRecognizing;

  /// No description provided for @scanNoBoard.
  ///
  /// In en, this message translates to:
  /// **'No chessboard found. Drag a square around the board in the image.'**
  String get scanNoBoard;

  /// No description provided for @scanDragHint.
  ///
  /// In en, this message translates to:
  /// **'Wrong area? Drag a square around the board in the image.'**
  String get scanDragHint;

  /// No description provided for @scanUncertain.
  ///
  /// In en, this message translates to:
  /// **'{count} uncertain squares are highlighted. Check them.'**
  String scanUncertain(Object count);

  /// No description provided for @scanProblems.
  ///
  /// In en, this message translates to:
  /// **'Check the position: {problems}'**
  String scanProblems(Object problems);

  /// No description provided for @scanUsePosition.
  ///
  /// In en, this message translates to:
  /// **'Use position'**
  String get scanUsePosition;

  /// No description provided for @scanFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read the image: {error}'**
  String scanFailed(Object error);

  /// No description provided for @engine.
  ///
  /// In en, this message translates to:
  /// **'Engine'**
  String get engine;

  /// No description provided for @rating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get rating;

  /// No description provided for @ghostTitle.
  ///
  /// In en, this message translates to:
  /// **'Your Ghost'**
  String get ghostTitle;

  /// No description provided for @ghostDescription.
  ///
  /// In en, this message translates to:
  /// **'Plays your openings, then like a player of your rating'**
  String get ghostDescription;

  /// No description provided for @ghostGames.
  ///
  /// In en, this message translates to:
  /// **'Built from {games} of your games, {positions} opening positions'**
  String ghostGames(Object games, Object positions);

  /// No description provided for @ghostNoGames.
  ///
  /// In en, this message translates to:
  /// **'Play a few games first: the Ghost learns from your game history.'**
  String get ghostNoGames;

  /// No description provided for @ghostRating.
  ///
  /// In en, this message translates to:
  /// **'Plays like: {elo}'**
  String ghostRating(Object elo);

  /// No description provided for @ghostRatingUnmeasured.
  ///
  /// In en, this message translates to:
  /// **'Rating not measured yet (plays like 1500)'**
  String get ghostRatingUnmeasured;

  /// No description provided for @ghostMeasure.
  ///
  /// In en, this message translates to:
  /// **'Measure my rating'**
  String get ghostMeasure;

  /// No description provided for @ghostMeasuring.
  ///
  /// In en, this message translates to:
  /// **'Reading your moves… {done} of {total}'**
  String ghostMeasuring(Object done, Object total);

  /// No description provided for @ghostFavourite.
  ///
  /// In en, this message translates to:
  /// **'Your favourite first moves: {moves}'**
  String ghostFavourite(Object moves);

  /// No description provided for @scanModeDiagram.
  ///
  /// In en, this message translates to:
  /// **'Diagram'**
  String get scanModeDiagram;

  /// No description provided for @scanModePhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo'**
  String get scanModePhoto;

  /// No description provided for @scanPhotoHint.
  ///
  /// In en, this message translates to:
  /// **'Photograph the whole board from a player\'s side, grid lines visible. Works best with standard tournament-style pieces.'**
  String get scanPhotoHint;

  /// No description provided for @scanPhotoNoBoard.
  ///
  /// In en, this message translates to:
  /// **'No board found. Photograph the whole board, with its grid visible.'**
  String get scanPhotoNoBoard;

  /// No description provided for @scanRotate.
  ///
  /// In en, this message translates to:
  /// **'Rotate 90°'**
  String get scanRotate;

  /// No description provided for @scanOrientationUnsure.
  ///
  /// In en, this message translates to:
  /// **'Check the orientation: rotate until White is at the bottom.'**
  String get scanOrientationUnsure;

  /// No description provided for @voiceMove.
  ///
  /// In en, this message translates to:
  /// **'Speak a move (V)'**
  String get voiceMove;

  /// No description provided for @voiceListening.
  ///
  /// In en, this message translates to:
  /// **'Listening — say your move, then tap the microphone'**
  String get voiceListening;

  /// No description provided for @voiceRecognizing.
  ///
  /// In en, this message translates to:
  /// **'Recognising…'**
  String get voiceRecognizing;

  /// No description provided for @voiceLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading the speech model ({mb} MB, once)…'**
  String voiceLoading(Object mb);

  /// No description provided for @voiceNoMove.
  ///
  /// In en, this message translates to:
  /// **'No move recognised — try again'**
  String get voiceNoMove;

  /// No description provided for @voiceHeard.
  ///
  /// In en, this message translates to:
  /// **'Heard: {move}'**
  String voiceHeard(Object move);

  /// No description provided for @voiceWhichMove.
  ///
  /// In en, this message translates to:
  /// **'Which move did you mean?'**
  String get voiceWhichMove;

  /// No description provided for @voiceFailed.
  ///
  /// In en, this message translates to:
  /// **'Voice input failed: {error}'**
  String voiceFailed(Object error);
  /// No description provided for @engineLab.
  ///
  /// In en, this message translates to:
  /// **'Engine Lab'**
  String get engineLab;

  /// No description provided for @engineLabSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Benchmark engines, keep the results and compare versions'**
  String get engineLabSubtitle;

  /// No description provided for @engineLabDashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get engineLabDashboard;

  /// No description provided for @engineLabBenchmark.
  ///
  /// In en, this message translates to:
  /// **'Benchmark'**
  String get engineLabBenchmark;

  /// No description provided for @engineLabLeaderboard.
  ///
  /// In en, this message translates to:
  /// **'Leaderboard'**
  String get engineLabLeaderboard;

  /// No description provided for @engineLabHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get engineLabHistory;

  /// No description provided for @engineLabDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get engineLabDiagnostics;

  /// No description provided for @benchmarkNow.
  ///
  /// In en, this message translates to:
  /// **'Benchmark Now'**
  String get benchmarkNow;

  /// No description provided for @benchmarkPresets.
  ///
  /// In en, this message translates to:
  /// **'Preset'**
  String get benchmarkPresets;

  /// No description provided for @presetQuick.
  ///
  /// In en, this message translates to:
  /// **'Quick'**
  String get presetQuick;

  /// No description provided for @presetStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get presetStandard;

  /// No description provided for @presetAccurate.
  ///
  /// In en, this message translates to:
  /// **'Accurate'**
  String get presetAccurate;

  /// No description provided for @presetCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get presetCustom;

  /// No description provided for @customConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Custom configuration'**
  String get customConfiguration;

  /// No description provided for @engineLabCustomHint.
  ///
  /// In en, this message translates to:
  /// **'Every setting is stored with the result, so the run can be repeated'**
  String get engineLabCustomHint;

  /// No description provided for @timePerMoveMs.
  ///
  /// In en, this message translates to:
  /// **'Time per move (ms)'**
  String get timePerMoveMs;

  /// No description provided for @searchDepthLabel.
  ///
  /// In en, this message translates to:
  /// **'Fixed search depth (0 = time)'**
  String get searchDepthLabel;

  /// No description provided for @gamesPerPairing.
  ///
  /// In en, this message translates to:
  /// **'Games per pairing'**
  String get gamesPerPairing;

  /// No description provided for @maxGames.
  ///
  /// In en, this message translates to:
  /// **'Maximum games (0 = no cap)'**
  String get maxGames;

  /// No description provided for @maxDurationMinutes.
  ///
  /// In en, this message translates to:
  /// **'Maximum duration (min, 0 = none)'**
  String get maxDurationMinutes;

  /// No description provided for @plyLimit.
  ///
  /// In en, this message translates to:
  /// **'Ply limit'**
  String get plyLimit;

  /// No description provided for @openingSuite.
  ///
  /// In en, this message translates to:
  /// **'Opening suite'**
  String get openingSuite;

  /// No description provided for @randomSeed.
  ///
  /// In en, this message translates to:
  /// **'Random seed'**
  String get randomSeed;

  /// No description provided for @warmUpGames.
  ///
  /// In en, this message translates to:
  /// **'Warm-up games'**
  String get warmUpGames;

  /// No description provided for @threadsLabel.
  ///
  /// In en, this message translates to:
  /// **'Threads (0 = engine default)'**
  String get threadsLabel;

  /// No description provided for @hashLabel.
  ///
  /// In en, this message translates to:
  /// **'Hash MB (0 = engine default)'**
  String get hashLabel;

  /// No description provided for @optionOverrides.
  ///
  /// In en, this message translates to:
  /// **'UCI option overrides (Name=Value, …)'**
  String get optionOverrides;

  /// No description provided for @adaptiveStopping.
  ///
  /// In en, this message translates to:
  /// **'Stop early when the uncertainty target is met'**
  String get adaptiveStopping;

  /// No description provided for @targetStdErr.
  ///
  /// In en, this message translates to:
  /// **'Target standard error (Elo)'**
  String get targetStdErr;

  /// No description provided for @engineLabRepetitions.
  ///
  /// In en, this message translates to:
  /// **'Repetitions'**
  String get engineLabRepetitions;

  /// No description provided for @estimatedWorkload.
  ///
  /// In en, this message translates to:
  /// **'Estimated workload'**
  String get estimatedWorkload;

  /// No description provided for @engineLabSelectEngines.
  ///
  /// In en, this message translates to:
  /// **'Engines'**
  String get engineLabSelectEngines;

  /// No description provided for @engineLabSelected.
  ///
  /// In en, this message translates to:
  /// **'selected'**
  String get engineLabSelected;

  /// No description provided for @engineLabUnavailable.
  ///
  /// In en, this message translates to:
  /// **'unavailable'**
  String get engineLabUnavailable;

  /// No description provided for @engineLabUnavailableHint.
  ///
  /// In en, this message translates to:
  /// **'Engines marked ✕ cannot be benchmarked on this platform; the reason appears on hover'**
  String get engineLabUnavailableHint;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @clearSelection.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clearSelection;

  /// No description provided for @formatRoundRobin.
  ///
  /// In en, this message translates to:
  /// **'Round robin'**
  String get formatRoundRobin;

  /// No description provided for @formatGauntlet.
  ///
  /// In en, this message translates to:
  /// **'Gauntlet'**
  String get formatGauntlet;

  /// No description provided for @referenceEngine.
  ///
  /// In en, this message translates to:
  /// **'Reference engine'**
  String get referenceEngine;

  /// No description provided for @engineLabGauntletNeedsReference.
  ///
  /// In en, this message translates to:
  /// **'Pick a reference engine for the gauntlet.'**
  String get engineLabGauntletNeedsReference;

  /// No description provided for @startBenchmark.
  ///
  /// In en, this message translates to:
  /// **'Start benchmark'**
  String get startBenchmark;

  /// No description provided for @pauseBenchmark.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pauseBenchmark;

  /// No description provided for @resumeBenchmark.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resumeBenchmark;

  /// No description provided for @cancelBenchmark.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancelBenchmark;

  /// No description provided for @benchmarkRunning.
  ///
  /// In en, this message translates to:
  /// **'Benchmark running'**
  String get benchmarkRunning;

  /// No description provided for @engineLabStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting engines…'**
  String get engineLabStarting;

  /// No description provided for @engineLabCancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancelling…'**
  String get engineLabCancelling;

  /// No description provided for @engineLabFinished.
  ///
  /// In en, this message translates to:
  /// **'Benchmark complete.'**
  String get engineLabFinished;

  /// No description provided for @engineLabFailed.
  ///
  /// In en, this message translates to:
  /// **'The benchmark failed'**
  String get engineLabFailed;

  /// No description provided for @engineLabLastMove.
  ///
  /// In en, this message translates to:
  /// **'Last move'**
  String get engineLabLastMove;

  /// No description provided for @engineLabConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Start this benchmark?'**
  String get engineLabConfirmTitle;

  /// No description provided for @engineLabStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get engineLabStart;

  /// No description provided for @engineLabEngines.
  ///
  /// In en, this message translates to:
  /// **'Engines'**
  String get engineLabEngines;

  /// No description provided for @engineLabGames.
  ///
  /// In en, this message translates to:
  /// **'Games'**
  String get engineLabGames;

  /// No description provided for @engineLabBudget.
  ///
  /// In en, this message translates to:
  /// **'Per move'**
  String get engineLabBudget;

  /// No description provided for @engineLabEstimate.
  ///
  /// In en, this message translates to:
  /// **'Estimated time'**
  String get engineLabEstimate;

  /// No description provided for @engineLabWorstCase.
  ///
  /// In en, this message translates to:
  /// **'Worst case'**
  String get engineLabWorstCase;

  /// No description provided for @engineLabWarnings.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get engineLabWarnings;

  /// No description provided for @engineLabRuns.
  ///
  /// In en, this message translates to:
  /// **'runs'**
  String get engineLabRuns;

  /// No description provided for @engineLabRatedGames.
  ///
  /// In en, this message translates to:
  /// **'rated games'**
  String get engineLabRatedGames;

  /// No description provided for @engineLabForfeits.
  ///
  /// In en, this message translates to:
  /// **'forfeits'**
  String get engineLabForfeits;

  /// No description provided for @engineLabAborted.
  ///
  /// In en, this message translates to:
  /// **'aborted'**
  String get engineLabAborted;

  /// No description provided for @engineLabAdjudicated.
  ///
  /// In en, this message translates to:
  /// **'adjudicated'**
  String get engineLabAdjudicated;

  /// No description provided for @engineLabLastRun.
  ///
  /// In en, this message translates to:
  /// **'Last run'**
  String get engineLabLastRun;

  /// No description provided for @engineLabNever.
  ///
  /// In en, this message translates to:
  /// **'never'**
  String get engineLabNever;

  /// No description provided for @engineLabLatestResult.
  ///
  /// In en, this message translates to:
  /// **'Latest result'**
  String get engineLabLatestResult;

  /// No description provided for @engineLabOpenReport.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get engineLabOpenReport;

  /// No description provided for @noBenchmarksYet.
  ///
  /// In en, this message translates to:
  /// **'No benchmarks yet'**
  String get noBenchmarksYet;

  /// No description provided for @engineLabEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Pick two or more engines and run a Quick benchmark. The result is kept.'**
  String get engineLabEmptyHint;

  /// No description provided for @engineLabLeaderboardHint.
  ///
  /// In en, this message translates to:
  /// **'The leaderboard is built from the runs stored on this device.'**
  String get engineLabLeaderboardHint;

  /// No description provided for @engineLabHistoryHint.
  ///
  /// In en, this message translates to:
  /// **'Every run is stored on this device and can be exported as JSON, CSV or PGN.'**
  String get engineLabHistoryHint;

  /// No description provided for @engineLabNoRatings.
  ///
  /// In en, this message translates to:
  /// **'No rated games yet.'**
  String get engineLabNoRatings;

  /// No description provided for @engineLabNoGames.
  ///
  /// In en, this message translates to:
  /// **'No games recorded yet.'**
  String get engineLabNoGames;

  /// No description provided for @engineLabChanged.
  ///
  /// In en, this message translates to:
  /// **'Engines that changed'**
  String get engineLabChanged;

  /// No description provided for @engineLabChangedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'These builds differ from the last benchmark'**
  String get engineLabChangedSubtitle;

  /// No description provided for @engineLabRebenchmark.
  ///
  /// In en, this message translates to:
  /// **'Re-benchmark'**
  String get engineLabRebenchmark;

  /// No description provided for @engineLabAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic benchmarks'**
  String get engineLabAutomatic;

  /// No description provided for @engineLabAutomaticSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatic runs are always a capped Quick benchmark'**
  String get engineLabAutomaticSubtitle;

  /// No description provided for @engineLabAutoAfterAdd.
  ///
  /// In en, this message translates to:
  /// **'After adding an engine'**
  String get engineLabAutoAfterAdd;

  /// No description provided for @engineLabAutoAfterChange.
  ///
  /// In en, this message translates to:
  /// **'After an engine changes'**
  String get engineLabAutoAfterChange;

  /// No description provided for @engineLabAutoBudget.
  ///
  /// In en, this message translates to:
  /// **'Budget'**
  String get engineLabAutoBudget;

  /// No description provided for @engineLabRelativeScaleHint.
  ///
  /// In en, this message translates to:
  /// **'Relative Elo: 1500 is the average of the engines in this run, not an absolute strength'**
  String get engineLabRelativeScaleHint;

  /// No description provided for @engineLabCompareTwo.
  ///
  /// In en, this message translates to:
  /// **'Compare two engines'**
  String get engineLabCompareTwo;

  /// No description provided for @engineLabCompareHint.
  ///
  /// In en, this message translates to:
  /// **'A difference without its uncertainty is not a result'**
  String get engineLabCompareHint;

  /// No description provided for @engineLabPickTwo.
  ///
  /// In en, this message translates to:
  /// **'Pick two engines.'**
  String get engineLabPickTwo;

  /// No description provided for @relativeElo.
  ///
  /// In en, this message translates to:
  /// **'Relative Elo'**
  String get relativeElo;

  /// No description provided for @calibratedElo.
  ///
  /// In en, this message translates to:
  /// **'Calibrated Elo'**
  String get calibratedElo;

  /// No description provided for @calibrationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Calibrated Elo unavailable'**
  String get calibrationUnavailable;

  /// No description provided for @calibrationAnchors.
  ///
  /// In en, this message translates to:
  /// **'Calibration anchors'**
  String get calibrationAnchors;

  /// No description provided for @uncertainty.
  ///
  /// In en, this message translates to:
  /// **'Uncertainty'**
  String get uncertainty;

  /// No description provided for @ratingQuality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get ratingQuality;

  /// No description provided for @engineLabScore.
  ///
  /// In en, this message translates to:
  /// **'Score'**
  String get engineLabScore;

  /// No description provided for @performanceMetrics.
  ///
  /// In en, this message translates to:
  /// **'Performance'**
  String get performanceMetrics;

  /// No description provided for @engineLabPerformanceHint.
  ///
  /// In en, this message translates to:
  /// **'Measured around every move; counters the engine does not report stay unavailable'**
  String get engineLabPerformanceHint;

  /// No description provided for @nodesPerSecond.
  ///
  /// In en, this message translates to:
  /// **'Nodes per second'**
  String get nodesPerSecond;

  /// No description provided for @latencyP50.
  ///
  /// In en, this message translates to:
  /// **'Median'**
  String get latencyP50;

  /// No description provided for @latencyP95.
  ///
  /// In en, this message translates to:
  /// **'p95'**
  String get latencyP95;

  /// No description provided for @latencyP99.
  ///
  /// In en, this message translates to:
  /// **'p99'**
  String get latencyP99;

  /// No description provided for @engineLabMax.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get engineLabMax;

  /// No description provided for @engineLabDepth.
  ///
  /// In en, this message translates to:
  /// **'Depth'**
  String get engineLabDepth;

  /// No description provided for @engineLabInitMs.
  ///
  /// In en, this message translates to:
  /// **'Init'**
  String get engineLabInitMs;

  /// No description provided for @unavailableLabel.
  ///
  /// In en, this message translates to:
  /// **'unavailable'**
  String get unavailableLabel;

  /// No description provided for @engineLabMoves.
  ///
  /// In en, this message translates to:
  /// **'Moves'**
  String get engineLabMoves;

  /// No description provided for @engineLabEngine.
  ///
  /// In en, this message translates to:
  /// **'Engine'**
  String get engineLabEngine;

  /// No description provided for @engineLabCheck.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get engineLabCheck;

  /// No description provided for @engineLabPassed.
  ///
  /// In en, this message translates to:
  /// **'Passed'**
  String get engineLabPassed;

  /// No description provided for @engineLabMedian.
  ///
  /// In en, this message translates to:
  /// **'Median'**
  String get engineLabMedian;

  /// No description provided for @engineLabWorst.
  ///
  /// In en, this message translates to:
  /// **'Worst'**
  String get engineLabWorst;

  /// No description provided for @stabilityCheck.
  ///
  /// In en, this message translates to:
  /// **'Stability check'**
  String get stabilityCheck;

  /// No description provided for @stabilityPassed.
  ///
  /// In en, this message translates to:
  /// **'Passed'**
  String get stabilityPassed;

  /// No description provided for @stabilityFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get stabilityFailed;

  /// No description provided for @engineLabStabilityHint.
  ///
  /// In en, this message translates to:
  /// **'Repeated initialisation, repeated searches and a clean shutdown'**
  String get engineLabStabilityHint;

  /// No description provided for @engineLabRunStability.
  ///
  /// In en, this message translates to:
  /// **'Run check'**
  String get engineLabRunStability;

  /// No description provided for @engineLabIdentity.
  ///
  /// In en, this message translates to:
  /// **'Engine identity'**
  String get engineLabIdentity;

  /// No description provided for @engineLabIdentityHint.
  ///
  /// In en, this message translates to:
  /// **'What the benchmark records, and what decides whether two runs are comparable'**
  String get engineLabIdentityHint;

  /// No description provided for @engineLabIdentityEmpty.
  ///
  /// In en, this message translates to:
  /// **'Inspect an engine to see its id, fingerprint, backend and configuration digest.'**
  String get engineLabIdentityEmpty;

  /// No description provided for @engineLabInspect.
  ///
  /// In en, this message translates to:
  /// **'Inspect'**
  String get engineLabInspect;

  /// No description provided for @engineLabEnvironment.
  ///
  /// In en, this message translates to:
  /// **'Environment'**
  String get engineLabEnvironment;

  /// No description provided for @engineLabPlatform.
  ///
  /// In en, this message translates to:
  /// **'Platform'**
  String get engineLabPlatform;

  /// No description provided for @engineLabVersion.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get engineLabVersion;

  /// No description provided for @engineLabMetricsHint.
  ///
  /// In en, this message translates to:
  /// **'CPU time and memory usage are not exposed by the engine protocol, so they are reported as unavailable rather than estimated.'**
  String get engineLabMetricsHint;

  /// No description provided for @engineLabLicense.
  ///
  /// In en, this message translates to:
  /// **'Suite license'**
  String get engineLabLicense;

  /// No description provided for @engineLabProgressionHint.
  ///
  /// In en, this message translates to:
  /// **'Relative rating of each engine over the runs stored here'**
  String get engineLabProgressionHint;

  /// No description provided for @engineLabDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete this run?'**
  String get engineLabDeleteTitle;

  /// No description provided for @engineLabReport.
  ///
  /// In en, this message translates to:
  /// **'Benchmark report'**
  String get engineLabReport;

  /// No description provided for @engineLabReportMissing.
  ///
  /// In en, this message translates to:
  /// **'Report unavailable'**
  String get engineLabReportMissing;

  /// No description provided for @engineLabSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get engineLabSummary;

  /// No description provided for @engineLabStarted.
  ///
  /// In en, this message translates to:
  /// **'Started'**
  String get engineLabStarted;

  /// No description provided for @engineLabDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get engineLabDuration;

  /// No description provided for @engineLabTrigger.
  ///
  /// In en, this message translates to:
  /// **'Trigger'**
  String get engineLabTrigger;

  /// No description provided for @engineLabStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped because'**
  String get engineLabStopped;

  /// No description provided for @engineLabFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get engineLabFormat;

  /// No description provided for @engineLabConfiguration.
  ///
  /// In en, this message translates to:
  /// **'Configuration'**
  String get engineLabConfiguration;

  /// No description provided for @engineLabFailures.
  ///
  /// In en, this message translates to:
  /// **'Engine problems'**
  String get engineLabFailures;

  /// No description provided for @engineLabStandings.
  ///
  /// In en, this message translates to:
  /// **'Standings'**
  String get engineLabStandings;

  /// No description provided for @engineLabGamesList.
  ///
  /// In en, this message translates to:
  /// **'Games'**
  String get engineLabGamesList;

  /// No description provided for @engineLabShowAll.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get engineLabShowAll;

  /// No description provided for @engineLabShowLess.
  ///
  /// In en, this message translates to:
  /// **'Show fewer'**
  String get engineLabShowLess;

  /// No description provided for @engineLabExportReport.
  ///
  /// In en, this message translates to:
  /// **'Copy report'**
  String get engineLabExportReport;

  /// No description provided for @engineLabMethod.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get engineLabMethod;

  /// No description provided for @engineLabMethodBody.
  ///
  /// In en, this message translates to:
  /// **'Bradley–Terry maximum likelihood over every rated game, centred on the average of the engines in the run. The 95% interval is the rating ± 1.96 × standard error, from the Fisher information of the fit. Adjudicated, aborted, cancelled and forfeited games are counted but not rated: a game that did not finish is not a draw.'**
  String get engineLabMethodBody;

  /// No description provided for @exportJson.
  ///
  /// In en, this message translates to:
  /// **'Export JSON'**
  String get exportJson;

  /// No description provided for @exportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get exportCsv;

  /// No description provided for @exportPgn.
  ///
  /// In en, this message translates to:
  /// **'Export PGN'**
  String get exportPgn;

  /// No description provided for @importBenchmark.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importBenchmark;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @copy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get copy;


  /// `elo`.
  String get elo;

  /// `refresh`.
  String get refresh;

  /// `retry`.
  String get retry;

  /// `engineLabAdaptiveStopping`.
  String get engineLabAdaptiveStopping;

  /// `engineLabAppVersion`.
  String get engineLabAppVersion;

  /// `engineLabBackend`.
  String get engineLabBackend;

  /// `engineLabBalanceColors`.
  String get engineLabBalanceColors;

  /// `engineLabBuiltIn`.
  String get engineLabBuiltIn;

  /// `engineLabCalibrationHint`.
  String get engineLabCalibrationHint;

  /// `engineLabCalibrationUnavailable`.
  String get engineLabCalibrationUnavailable;

  /// `engineLabCompare`.
  String get engineLabCompare;

  /// `engineLabCustom`.
  String get engineLabCustom;

  /// `engineLabDeleteBody`.
  String get engineLabDeleteBody;

  /// `engineLabFingerprint`.
  String get engineLabFingerprint;

  /// `engineLabGauntletHint`.
  String get engineLabGauntletHint;

  /// `engineLabHash`.
  String get engineLabHash;

  /// `engineLabHost`.
  String get engineLabHost;

  /// `engineLabInProgress`.
  String get engineLabInProgress;

  /// `engineLabMaxGames`.
  String get engineLabMaxGames;

  /// `engineLabMaxMinutes`.
  String get engineLabMaxMinutes;

  /// `engineLabMovesPerPairing`.
  String get engineLabMovesPerPairing;

  /// `engineLabNoAnchors`.
  String get engineLabNoAnchors;

  /// `engineLabNoFingerprint`.
  String get engineLabNoFingerprint;

  /// `engineLabNoHistory`.
  String get engineLabNoHistory;

  /// `engineLabNoHistoryHint`.
  String get engineLabNoHistoryHint;

  /// `engineLabNoMetrics`.
  String get engineLabNoMetrics;

  /// `engineLabNoRatedGames`.
  String get engineLabNoRatedGames;

  /// `engineLabNoRatingsHint`.
  String get engineLabNoRatingsHint;

  /// `engineLabOpeningSuite`.
  String get engineLabOpeningSuite;

  /// `engineLabPerformance`.
  String get engineLabPerformance;

  /// `engineLabPlyCap`.
  String get engineLabPlyCap;

  /// `engineLabPlyCapHint`.
  String get engineLabPlyCapHint;

  /// `engineLabPreset`.
  String get engineLabPreset;

  /// `engineLabProgression`.
  String get engineLabProgression;

  /// `engineLabQualityHigh`.
  String get engineLabQualityHigh;

  /// `engineLabQualityInsufficient`.
  String get engineLabQualityInsufficient;

  /// `engineLabQualityLow`.
  String get engineLabQualityLow;

  /// `engineLabQualityModerate`.
  String get engineLabQualityModerate;

  /// `engineLabRated`.
  String get engineLabRated;

  /// `engineLabReference`.
  String get engineLabReference;

  /// `engineLabRunning`.
  String get engineLabRunning;

  /// `engineLabSearchDepth`.
  String get engineLabSearchDepth;

  /// `engineLabSeed`.
  String get engineLabSeed;

  /// `engineLabStability`.
  String get engineLabStability;

  /// `engineLabTargetStdErr`.
  String get engineLabTargetStdErr;

  /// `engineLabThreads`.
  String get engineLabThreads;

  /// `engineLabTimePerMoveMs`.
  String get engineLabTimePerMoveMs;

  /// `engineLabUnchanged`.
  String get engineLabUnchanged;

  /// `engineLabWarmUp`.
  String get engineLabWarmUp;

  /// `engineLabWebNote`.
  String get engineLabWebNote;

  /// `engineLabZeroIsEngineDefault`.
  String get engineLabZeroIsEngineDefault;

  /// `engineLabZeroIsNever`.
  String get engineLabZeroIsNever;

  /// `engineLabZeroIsTime`.
  String get engineLabZeroIsTime;

  /// `engineLabZeroIsUnlimited`.
  String get engineLabZeroIsUnlimited;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}

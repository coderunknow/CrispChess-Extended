import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../chess/chess_clock.dart';
import '../chess/board_theme.dart';
import '../chess/game_state.dart' show ChessVariant;
import '../engines/lynx_build.dart';
import '../engines/chess_engine.dart' show thinkTimeForLevel;
import '../engines/chess_lm_engine.dart';
import '../engines/ghost_engine.dart' show ghostEngineName;
import '../engines/searchless_engine.dart';
import '../engines/engine_registry.dart';
import '../engines/generic_uci_engine_stub.dart' show EngineProfile;
import '../services/engine_profile_store.dart';
import '../widgets/ghost_profile_card.dart';
import 'engine_manager_screen.dart';

class SettingsScreen extends StatefulWidget {
  final int strengthLevel;
  final int hintDepth;
  final String currentEngine;

  /// The selected engine's stable id (see `engine_registry.dart`).
  ///
  /// [currentEngine] remains for backward compatibility and for display; when
  /// this is null the id is derived from [currentEngine].
  final String? currentEngineId;
  final bool playAsBlack;
  final String maia3Variant;
  final int animationSpeed;
  final String pieceTheme;
  final String hintEngine;
  final TimeControl timeControl;
  final ChessVariant chessVariant;
  final String lc0Backend;

  const SettingsScreen({
    Key? key,
    required this.strengthLevel,
    required this.hintDepth,
    this.currentEngine = 'Built-in',
    this.currentEngineId,
    this.playAsBlack = false,
    this.maia3Variant = '5m',
    this.animationSpeed = 2,
    this.pieceTheme = 'chessnut',
    this.hintEngine = 'same',
    this.timeControl = TimeControl.unlimited,
    this.chessVariant = ChessVariant.standard,
    this.lc0Backend = 'auto',
  }) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _strengthLevel;
  late int _hintDepth;
  /// Id of the selected engine (built-in or user-added). Display names are not
  /// unique and not stable, so the selection is held by id.
  late String _selectedEngineId;
  final _profileStore = EngineProfileStore();
  List<EngineProfile> _customProfiles = const [];
  bool _resolvedInitialSelection = false;
  late String _maia3Variant;
  bool _showValidMoves = true;
  bool _allowUndo = true;
  String _hintEngine = 'same';
  int _animationSpeed = 2;
  late TimeControl _timeControl;
  late ChessVariant _chessVariant;
  late String _lc0Backend;
  int _customBaseMinutes = 10;
  int _customIncrementSeconds = 0;
  int _engineHashMb = 64;
  int _engineThreads = 1;
  String _boardTheme = 'brown';
  String _notationStyle = 'algebraic';
  bool _blindfold = false;
  String _themeMode = 'system';
  String _language = 'system';
  bool _solidBlackPieces = false;
  bool _playAsBlack = false;
  String _pieceTheme = 'chessnut';

  static const _pieceThemes = [
    ('chessnut', 'Chessnut', 'MIT'),
    ('rhosgfx', 'Rhosgfx', 'CC0'),
    ('fantasy', 'Fantasy', 'MIT'),
    ('spatial', 'Spatial', 'MIT'),
    ('celtic', 'Celtic', 'MIT'),
    ('kiwen-suwi', 'Kiwen Suwi', 'CC-BY 4.0'),
    ('totoy', 'Totoy', 'CC-BY 4.0'),
    ('papercut', 'Papercut', 'CC-BY 4.0'),
  ];

  static const _maia3Variants = [
    ('5m', 'Maia3 5M', '~25MB', '~1800 ELO'),
    ('23m', 'Maia3 23M', '~92MB', '~2200 ELO'),
    ('79m', 'Maia3 79M', '~313MB', '~2500 ELO'),
  ];

  @override
  void initState() {
    super.initState();
    _strengthLevel = widget.strengthLevel;
    _hintDepth = widget.hintDepth;
    _selectedEngineId = widget.currentEngineId ??
        builtInEngineId(widget.currentEngine);
    _playAsBlack = widget.playAsBlack;
    _maia3Variant = widget.maia3Variant;
    _animationSpeed = widget.animationSpeed;
    _pieceTheme = widget.pieceTheme;
    _hintEngine = widget.hintEngine;
    _timeControl = widget.timeControl;
    _chessVariant = widget.chessVariant;
    _lc0Backend = widget.lc0Backend;
    _loadSavedPrefs();
    _loadProfiles();
  }

  /// Loads user-added engines so they appear in the selector.
  ///
  /// The selector used to be a hand-written list that knew nothing about the
  /// Engine Manager, so an engine could be added successfully and still be
  /// impossible to select. Called again after returning from the Engine
  /// Manager, so a newly added engine shows up without restarting the app.
  Future<void> _loadProfiles() async {
    List<EngineProfile> profiles;
    try {
      profiles = await _profileStore.load();
    } catch (e) {
      // Storage being unavailable must not take the whole settings screen
      // down; the built-in engines still work without it.
      debugPrint('[Settings] could not load engine profiles: $e');
      return;
    }
    if (!mounted) return;
    setState(() {
      _customProfiles = profiles;
      if (!_resolvedInitialSelection) {
        _resolvedInitialSelection = true;
        if (widget.currentEngineId == null) {
          _selectedEngineId = resolveSelectedEngineId(
            savedName: widget.currentEngine,
            profiles: profiles,
          );
        } else {
          _selectedEngineId = resolveSelectedEngineId(
            savedId: widget.currentEngineId,
            savedName: widget.currentEngine,
            profiles: profiles,
          );
        }
      } else {
        // The selected engine may have just been deleted in the manager.
        _selectedEngineId = resolveSelectedEngineId(
          savedId: _selectedEngineId,
          profiles: profiles,
        );
      }
    });
  }

  Future<void> _loadSavedPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final lang = prefs.getString('locale') ?? 'system';
    final solid = prefs.getBool('solidBlackPieces') ?? false;
    final customBase = prefs.getInt('customBaseMinutes') ?? 10;
    final customInc = prefs.getInt('customIncrementSeconds') ?? 0;
    final hashMb = prefs.getInt('engineHashMb') ?? 64;
    final threads = prefs.getInt('engineThreads') ?? 1;
    if (mounted) setState(() {
      _language = lang;
      _solidBlackPieces = solid;
      _customBaseMinutes = customBase;
      _customIncrementSeconds = customInc;
      _engineHashMb = hashMb;
      _engineThreads = threads;
      _boardTheme = prefs.getString('boardTheme') ?? 'brown';
      _notationStyle = prefs.getString('notationStyle') ?? 'algebraic';
      _blindfold = prefs.getBool('blindfold') ?? false;
    });
  }

  /// Snap hash slider to powers of 2: 16, 32, 64, 128, 256, 512, 1024, 2048.
  static int _snapHashValue(double v) {
    const snaps = [16, 32, 64, 128, 256, 512, 1024, 2048];
    var closest = snaps[0];
    for (final s in snaps) {
      if ((s - v).abs() < (closest - v).abs()) closest = s;
    }
    return closest;
  }

  void _showCustomTimeDialog() {
    var baseMin = _customBaseMinutes;
    var incSec = _customIncrementSeconds;
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            title: const Text('Custom Time Control'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text('Base: '),
                    Expanded(
                      child: Slider(
                        value: baseMin.toDouble(),
                        min: 1,
                        max: 180,
                        divisions: 179,
                        label: '$baseMin min',
                        onChanged: (v) => setDialogState(() => baseMin = v.round()),
                      ),
                    ),
                    SizedBox(width: 40, child: Text('$baseMin m', textAlign: TextAlign.right)),
                  ],
                ),
                Row(
                  children: [
                    const Text('Inc: '),
                    Expanded(
                      child: Slider(
                        value: incSec.toDouble(),
                        min: 0,
                        max: 60,
                        divisions: 60,
                        label: '$incSec sec',
                        onChanged: (v) => setDialogState(() => incSec = v.round()),
                      ),
                    ),
                    SizedBox(width: 40, child: Text('${incSec}s', textAlign: TextAlign.right)),
                  ],
                ),
                const SizedBox(height: 8),
                Text('$baseMin+$incSec', style: Theme.of(ctx).textTheme.titleMedium),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _customBaseMinutes = baseMin;
                    _customIncrementSeconds = incSec;
                    _timeControl = TimeControl.custom;
                  });
                },
                child: const Text('OK'),
              ),
            ],
          );
        });
      },
    );
  }

  /// Engines available as the hint engine: 'same' plus every engine the
  /// main selector offers, custom ones included.
  ///
  /// The values are engine ids, not display names. Names are neither unique nor
  /// stable — the list used to be keyed by them, so two user-added engines
  /// sharing a name produced two identical `DropdownButton` values, which
  /// asserts, and a custom engine called "Stockfish" collided with the real one.
  List<(String, String)> get _hintEngineChoices {
    final engines = _availableEngines;
    final labels = disambiguateLabels([for (final engine in engines) engine.name]);
    return [
      ('same', AppLocalizations.of(context)?.sameAsOpponent ?? 'Same as opponent'),
      for (var i = 0; i < engines.length; i++) (engines[i].id, labels[i]),
    ];
  }

  /// The hint engine as an id, migrating a display name saved by an older
  /// build. Null-unsafe values ('same', a removed engine) fall back to the
  /// opponent's engine, which is what the dropdown shows.
  String get _effectiveHintEngine {
    final saved = _hintEngine;
    if (saved == 'same') return 'same';
    final resolved = looksLikeEngineId(saved)
        ? saved
        : resolveSelectedEngineId(savedName: saved, profiles: _customProfiles);
    return _hintEngineChoices.any((choice) => choice.$1 == resolved)
        ? resolved
        : 'same';
  }

  /// Label for [id] in the hint-engine row.
  String _hintEngineLabel(String id) {
    for (final (value, label) in _hintEngineChoices) {
      if (value == id) return label;
    }
    return id;
  }

  /// Canonical built-in name behind the selection, or null for a custom engine.
  String? get _selectedBuiltInName => builtInNameFromId(_selectedEngineId);

  bool get _isMaiaEngine => _selectedBuiltInName == 'Maia3 Dart';
  bool get _isStockfish => _selectedBuiltInName == 'Stockfish';
  bool get _isLc0 => _selectedBuiltInName == 'Lc0';
  bool get _isLynx => _selectedBuiltInName == 'Lynx';

  List<_EngineOption> get _availableEngines {
    final engines = <_EngineOption>[
      _EngineOption(
        id: builtInEngineId('Built-in'),
        name: 'Built-in',
        description: 'Alpha-beta + TT, pure Dart',
        elo: '~1800',
        license: 'MIT',
        available: true,
      ),
    ];

    // Your Ghost — your openings, then Maia at your measured rating
    engines.add(_EngineOption(
      id: builtInEngineId(ghostEngineName),
      name: ghostEngineName,
      description: AppLocalizations.of(context)?.ghostDescription ??
          'Plays your openings, then like a player of your rating',
      elo: 'you',
      license: 'MIT',
      available: true,
    ));

    // Maia3 Dart — pure Dart port, works everywhere
    engines.add(_EngineOption(
      id: builtInEngineId('Maia3 Dart'),
      name: 'Maia3 Dart',
      description: 'Neural net — human-like play (pure Dart + ONNX)',
      elo: '~1500–2500',
      license: 'MIT',
      available: true,
      hasVariants: true,
    ));

    // ChessMamba — MIT state-space net that reads the game as a move sequence
    engines.add(_EngineOption(
      id: builtInEngineId('ChessMamba'),
      name: 'ChessMamba',
      description: 'Mamba state-space net + its own search (downloads 67 MB)',
      elo: '~800',
      license: 'MIT',
      available: true,
    ));

    // DeepMind's searchless transformers: one look per legal move, no search.
    for (final s in availableSearchlessSizes) {
      engines.add(_EngineOption(
        id: builtInEngineId(s.engineName),
        name: s.engineName,
        description: 'DeepMind transformer, no search (downloads ${s.downloadMb} MB)',
        elo: switch (s) {
          SearchlessSize.m270 => '~2900 (paper)',
          _ => 'strong',
        },
        license: 'Apache-2.0 / CC BY 4.0',
        available: true,
      ));
    }

    // The language-model bot zoo — tiny chess LMs from the Hub.
    for (final lm in chessLmZoo.where(chessLmAvailable)) {
      engines.add(_EngineOption(
        id: builtInEngineId(lm.name),
        name: lm.name,
        description: '${lm.description} (by ${lm.author}, ${lm.downloadMb} MB)',
        elo: '~400',
        license: lm.license,
        available: true,
      ));
    }

    // Frozenight — MIT, available on all platforms
    engines.add(_EngineOption(
      id: builtInEngineId('Frozenight'),
      name: 'Frozenight',
      description: kIsWeb
          ? 'NNUE engine (Rust→WASM)'
          : 'NNUE engine (Rust FFI — needs native lib)',
      elo: '~3226',
      license: 'MIT/Apache-2.0',
      available: true, // Web WASM + native FFI (if lib present)
    ));

    // Lynx — MIT, native binary or WASM on web
    engines.add(_EngineOption(
      id: builtInEngineId('Lynx'),
      name: 'Lynx',
      description: kIsWeb ? 'Classical HCE (WASM)' : 'Classical HCE, downloaded from GitHub',
      elo: '~3350',
      license: 'MIT',
      available: true,
    ));

    // Stockfish — downloaded at runtime, never linked into app
    if (kIsWeb) {
      engines.add(_EngineOption(
        id: builtInEngineId('Stockfish'),
        name: 'Stockfish',
        description: 'Optional download (Web Worker)',
        elo: '~3200',
        license: 'GPL-3.0',
        available: true,
        gplNotice: true,
      ));
    } else {
      final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
      // iOS downloads stockfish.js at runtime and runs it inside WebKit
      // (App Store-sanctioned; no GPL code in the app binary). Desktop/Android
      // use a native binary. See NOTICE.md and StockfishJSBridge.swift.
      engines.add(_EngineOption(
        id: builtInEngineId('Stockfish'),
        name: 'Stockfish',
        description: isIOS
            ? 'Optional download (runs in WebKit)'
            : 'Optional — install stockfish separately',
        elo: isIOS ? '~3200' : '~3600',
        license: 'GPL-3.0',
        available: true,
        gplNotice: true,
      ));
    }

    // Lc0 — downloaded at runtime, GPL-3.0
    engines.add(_EngineOption(
      id: builtInEngineId('Lc0'),
      name: 'Lc0',
      description: kIsWeb
          ? 'MCTS + Maia neural net (ONNX Runtime Web)'
          : 'MCTS + neural net (downloaded separately)',
      elo: '~1100–1900',
      license: 'GPL-3.0',
      available: true, // Web ONNX + native
      gplNotice: true,
    ));

    // Engines the user added through the Engine Manager. Appended here so the
    // selector and the factory cannot disagree about what exists.
    if (customEnginesSupported) {
      for (final profile in _customProfiles) {
        final author = profile.detectedAuthor;
        engines.add(_EngineOption(
          id: customEngineId(profile),
          name: profile.displayName,
          description: author == null || author.isEmpty
              ? 'Custom UCI engine · ${profile.path}'
              : 'Custom UCI engine by $author · ${profile.path}',
          elo: 'custom',
          license: 'as installed',
          available: true,
          isCustom: true,
        ));
      }
    }

    return engines;
  }

  String _getStrengthDescription(int level) {
    if (level <= 3) return 'Beginner';
    if (level <= 6) return 'Novice';
    if (level <= 10) return 'Intermediate';
    if (level <= 14) return 'Advanced';
    if (level <= 17) return 'Expert';
    return 'Master+';
  }

  String _getStrengthInfo(int level) {
    final selected = _selectedBuiltInName;
    if (selected == null) {
      // A user-added engine brings its own strength controls (Hash, Threads,
      // Skill Level, ...) in the Engine Manager; the app's level slider does
      // not drive it.
      return 'Custom UCI engine · strength and search are controlled by its '
          'own options (Engine Manager)';
    }
    switch (selected) {
      case 'Built-in':
        return 'ELO ~${800 + level * 80}  ·  Depth ${3 + level}';
      case 'Maia3 Dart':
        final elo = 800 + (level * 60);
        return 'Target ELO ~$elo (model adapts to play at this level)';
      case 'Lc0':
        return 'MCTS nodes: ${50 + level * level * 2} (more = stronger)';
      case 'Stockfish':
        return 'Skill Level $level  ·  Depth ${5 + level ~/ 4}';
      case 'Frozenight':
        return 'Depth ${2 + level ~/ 2} (search time ~${level}s)';
      case final n when searchlessSizeNamed(n) != null:
        final t = SearchlessEngine.temperatureFor(level);
        return t == null
            ? 'Always its best move'
            : 'Softmax temperature ${t.toStringAsFixed(3)} over win probabilities';
      case final n when chessLmSpecNamed(n) != null:
        return 'Sampling temperature ${ChessLmEngine.temperatureFor(level).toStringAsFixed(2)} '
            '(lower plays its favourite move more often)';
      case 'ChessMamba':
        return level <= 3
            ? 'Network instinct only (no search)'
            : 'Policy-guided search, ~${thinkTimeForLevel(level).inMilliseconds} ms a move';
      default:
        return 'Level $level';
    }
  }

  static String _animationSpeedLabel(int speed) {
    switch (speed) {
      case 0: return 'Instant';
      case 1: return 'Fast';
      case 2: return 'Normal';
      case 3: return 'Slow';
      default: return 'Normal';
    }
  }

  Color _getColorForStrength(int level) {
    if (level <= 6) return Colors.green;
    if (level <= 10) return Colors.blue;
    if (level <= 14) return Colors.orange;
    if (level <= 17) return Colors.red;
    return Colors.purple;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l?.settings ?? 'Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Engine selector
          Text(l?.chessEngine ?? 'Chess Engine', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: _availableEngines.map((engine) {
                final selected = _selectedEngineId == engine.id;
                return RadioListTile<String>(
                  key: ValueKey(engine.id),
                  value: engine.id,
                  groupValue: _selectedEngineId,
                  onChanged: engine.available
                      ? (value) =>
                          setState(() => _selectedEngineId = value!)
                      : null,
                  title: Row(
                    children: [
                      Text(engine.name,
                          style: TextStyle(
                              fontWeight:
                                  selected ? FontWeight.bold : FontWeight.normal)),
                      const SizedBox(width: 8),
                      Chip(
                        label: Text(engine.elo,
                            style: const TextStyle(fontSize: 11)),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${engine.description} (${engine.license})'
                        '${engine.available ? '' : ' — not available'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (engine.gplNotice)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'GPL-3.0 engine — downloaded separately, '
                            'not compiled into this app.',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade600,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

          // Custom engines (native only)
          if (!kIsWeb)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.memory, size: 18),
                label: Text(l?.engineManagerSubtitle ?? 'Engine Manager — Add Custom UCI Engines'),
                onPressed: () async {
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const EngineManagerScreen()));
                  // A newly added engine must appear in the selector; one
                  // deleted here must not stay selected.
                  await _loadProfiles();
                },
              ),
            ),

          if (_selectedBuiltInName == ghostEngineName) ...[
            const SizedBox(height: 16),
            const GhostProfileCard(),
          ],

          // Maia3 variant selector (shown when a Maia engine is selected)
          if (_isMaiaEngine) ...[
            const SizedBox(height: 16),
            Text(l?.maia3Model ?? 'Maia3 Model',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: _maia3Variants.map((v) {
                  final (id, name, size, elo) = v;
                  return RadioListTile<String>(
                    value: id,
                    groupValue: _maia3Variant,
                    onChanged: (value) =>
                        setState(() => _maia3Variant = value!),
                    title: Text(name, style: const TextStyle(fontSize: 14)),
                    subtitle: Text('$size — $elo',
                        style: const TextStyle(fontSize: 12)),
                    dense: true,
                  );
                }).toList(),
              ),
            ),
          ],

          if (_isLc0) ...[
            const SizedBox(height: 16),
            Text('Inference backend',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: const [
                  ('auto', 'Automatic', 'Use native when available'),
                  ('native', 'Native ONNX Runtime', 'Fastest; native platforms only'),
                  ('dart', 'Pure Dart', 'Portable runtime for comparison and fallback'),
                ].map((option) {
                  final (id, title, subtitle) = option;
                  return RadioListTile<String>(
                    value: id,
                    groupValue: _lc0Backend,
                    onChanged: kIsWeb
                        ? null
                        : (value) => setState(() => _lc0Backend = value!),
                    title: Text(title, style: const TextStyle(fontSize: 14)),
                    subtitle: Text(subtitle,
                        style: const TextStyle(fontSize: 12)),
                    dense: true,
                  );
                }).toList(),
              ),
            ),
          ],

          // Stockfish version selector
          if (_isStockfish && kIsWeb) ...[
            const SizedBox(height: 16),
            Text(l?.stockfishVersion ?? 'Stockfish Version',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  ('sf10', 'Stockfish 10', '~1MB', '~2800 ELO'),
                  ('sf18asm', 'Stockfish 18 (NNUE)', '~10MB', '~3400 ELO'),
                ].map((v) {
                  final (id, name, size, elo) = v;
                  return RadioListTile<String>(
                    value: id,
                    groupValue: _maia3Variant, // reuse variant field
                    onChanged: (value) =>
                        setState(() => _maia3Variant = value!),
                    title: Text(name, style: const TextStyle(fontSize: 14)),
                    subtitle: Text('$size — $elo',
                        style: const TextStyle(fontSize: 12)),
                    dense: true,
                  );
                }).toList(),
              ),
            ),
          ],

          // Lynx WASM build selector — web only; the native build downloads a
          // single binary and has nothing to choose.
          if (_isLynx && kIsWeb) ...[
            const SizedBox(height: 16),
            Text(l?.lynxBuild ?? 'Lynx Build',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (final b in LynxBuild.values)
                    RadioListTile<String>(
                      value: b.id,
                      groupValue: LynxBuild.fromId(_maia3Variant).id,
                      onChanged: (value) =>
                          setState(() => _maia3Variant = value!),
                      title: Text(b.label,
                          style: const TextStyle(fontSize: 14)),
                      subtitle: Text('${b.downloadSize} — ${b.description}',
                          style: const TextStyle(fontSize: 12)),
                      dense: true,
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
              child: Text(
                l?.lynxBuildNote ??
                    'The engine loads once per page, so a change takes effect '
                        'after a reload.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).hintColor),
              ),
            ),
          ],

          // Lc0 Maia weight selector
          if (_isLc0) ...[
            const SizedBox(height: 16),
            Text(l?.maiaWeight ?? 'Maia Weight (ELO level)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  ('1100', 'Maia 1100', '~3.5MB', 'Beginner'),
                  ('1300', 'Maia 1300', '~3.5MB', 'Casual'),
                  ('1500', 'Maia 1500', '~3.5MB', 'Intermediate'),
                  ('1700', 'Maia 1700', '~3.5MB', 'Advanced'),
                  ('1900', 'Maia 1900', '~3.5MB', 'Expert'),
                ].map((v) {
                  final (id, name, size, level) = v;
                  return RadioListTile<String>(
                    value: id,
                    groupValue: _maia3Variant, // reuse variant field
                    onChanged: (value) =>
                        setState(() => _maia3Variant = value!),
                    title: Text(name, style: const TextStyle(fontSize: 14)),
                    subtitle: Text('$size — $level',
                        style: const TextStyle(fontSize: 12)),
                    dense: true,
                  );
                }).toList(),
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Strength slider
          Text(l?.opponentStrength ?? 'Opponent Strength',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Level $_strengthLevel',
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.bold)),
                      Chip(
                        label: Text(_getStrengthDescription(_strengthLevel),
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                        backgroundColor: _getColorForStrength(_strengthLevel),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Slider(
                    value: _strengthLevel.toDouble(),
                    min: 0,
                    max: 20,
                    divisions: 20,
                    label: _strengthLevel.toString(),
                    onChanged: (value) =>
                        setState(() => _strengthLevel = value.round()),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _getStrengthInfo(_strengthLevel),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Hints & Analysis
          Text(l?.hintsAndAnalysis ?? 'Hints & Analysis', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l?.analysisDepth('$_hintDepth') ?? 'Analysis Depth: $_hintDepth',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  Slider(
                    value: _hintDepth.toDouble(),
                    min: 8,
                    max: 22,
                    divisions: 14,
                    label: _hintDepth.toString(),
                    onChanged: (value) =>
                        setState(() => _hintDepth = value.round()),
                  ),
                  const Divider(),
                  ListTile(
                    title: Text(l?.hintEngine ?? 'Hint Engine'),
                    subtitle: Text(
                        _hintEngineLabel(_effectiveHintEngine),
                        style: const TextStyle(fontSize: 12)),
                    contentPadding: EdgeInsets.zero,
                    trailing: DropdownButton<String>(
                      // A saved hint engine that no longer exists (a removed
                      // custom engine, or a renamed one) is not among the
                      // items, and DropdownButton asserts on a value it cannot
                      // find. Show "same as opponent" instead.
                      value: _effectiveHintEngine,
                      underline: const SizedBox.shrink(),
                      onChanged: (v) => setState(() => _hintEngine = v!),
                      items: [
                        for (final (value, label) in _hintEngineChoices)
                          DropdownMenuItem(
                              value: value,
                              child: Text(label,
                                  style: const TextStyle(fontSize: 13))),
                      ],
                    ),
                  ),
                  const Divider(),
                  Text('Hash: $_engineHashMb MB',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  Slider(
                    value: _engineHashMb.toDouble(),
                    min: 16,
                    max: 2048,
                    divisions: 7,
                    label: '$_engineHashMb MB',
                    onChanged: (v) => setState(() => _engineHashMb = _snapHashValue(v)),
                  ),
                  Text('Threads: $_engineThreads',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  Slider(
                    value: _engineThreads.toDouble(),
                    min: 1,
                    max: 16,
                    divisions: 15,
                    label: '$_engineThreads',
                    onChanged: (v) => setState(() => _engineThreads = v.round()),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Game settings
          Text(l?.game ?? 'Game', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: Text(l?.playAsBlackSetting ?? 'Play as Black'),
                  subtitle: Text(l?.playAsBlackSubtitle ?? 'Engine makes the first move'),
                  value: _playAsBlack,
                  onChanged: (value) =>
                      setState(() => _playAsBlack = value),
                ),
                const Divider(height: 1),
                ListTile(
                  title: Text(l?.timeControl ?? 'Time Control'),
                  trailing: DropdownButton<TimeControl>(
                    value: _timeControl,
                    underline: const SizedBox.shrink(),
                    onChanged: (value) {
                      if (value == TimeControl.custom) {
                        _showCustomTimeDialog();
                      } else {
                        setState(() => _timeControl = value!);
                      }
                    },
                    items: TimeControl.values.map((tc) {
                      final label = tc == TimeControl.custom
                          ? (_timeControl == TimeControl.custom
                              ? 'Custom ${_customBaseMinutes}+$_customIncrementSeconds'
                              : l?.customTimeControl ?? 'Custom...')
                          : tc.label;
                      return DropdownMenuItem(
                        value: tc,
                        child: Text(label, style: const TextStyle(fontSize: 13)),
                      );
                    }).toList(),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: Text(l?.gameMode ?? 'Game Mode'),
                  trailing: DropdownButton<ChessVariant>(
                    value: _chessVariant,
                    underline: const SizedBox.shrink(),
                    onChanged: (value) =>
                        setState(() => _chessVariant = value!),
                    items: ChessVariant.values.map((v) {
                      final label = switch (v) {
                        ChessVariant.standard => l?.standard ?? 'Standard',
                        ChessVariant.chess960 => 'Chess960',
                        ChessVariant.kingOfTheHill => l?.kingOfTheHill ?? 'King of the Hill',
                        ChessVariant.threeCheck => l?.threeCheck ?? 'Three-Check',
                      };
                      return DropdownMenuItem(
                        value: v,
                        child: Text(label, style: const TextStyle(fontSize: 13)),
                      );
                    }).toList(),
                  ),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: Text(l?.showValidMoves ?? 'Show Valid Moves'),
                  subtitle:
                      Text(l?.showValidMovesSubtitle ?? 'Highlight legal moves when selecting a piece'),
                  value: _showValidMoves,
                  onChanged: (value) =>
                      setState(() => _showValidMoves = value),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: Text(l?.allowUndo ?? 'Allow Undo'),
                  subtitle: Text(l?.allowUndoSubtitle ?? 'Disable for discipline mode'),
                  value: _allowUndo,
                  onChanged: (value) =>
                      setState(() => _allowUndo = value),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: Text(l?.blindfoldMode ?? 'Blindfold Mode'),
                  subtitle: Text(l?.blindfoldModeSubtitle ?? 'Hide pieces — play by memory'),
                  value: _blindfold,
                  onChanged: (value) =>
                      setState(() => _blindfold = value),
                ),
                const Divider(height: 1),
                SwitchListTile(
                  title: Text(l?.solidBlackPieces ?? 'Solid Black Pieces'),
                  subtitle: Text(l?.solidBlackPiecesSubtitle ?? 'Render black pieces as solid black instead of grey gradient'),
                  value: _solidBlackPieces,
                  onChanged: (value) =>
                      setState(() => _solidBlackPieces = value),
                ),
                const Divider(height: 1),
                ListTile(
                  title: Text(l?.animationSpeed ?? 'Animation Speed'),
                  subtitle: Slider(
                    value: _animationSpeed.toDouble(),
                    min: 0,
                    max: 3,
                    divisions: 3,
                    label: _animationSpeedLabel(_animationSpeed),
                    onChanged: (value) =>
                        setState(() => _animationSpeed = value.round()),
                  ),
                  trailing: Text(
                    _animationSpeedLabel(_animationSpeed),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: Text(l?.notationStyleLabel ?? 'Notation'),
                  trailing: DropdownButton<String>(
                    value: _notationStyle,
                    underline: const SizedBox.shrink(),
                    onChanged: (v) => setState(() => _notationStyle = v!),
                    items: const [
                      DropdownMenuItem(value: 'algebraic', child: Text('Nf3 (Algebraic)', style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(value: 'figurine', child: Text('\u2658f3 (Figurine)', style: TextStyle(fontSize: 13))),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Board color theme
          Text(l?.boardColorThemeLabel ?? 'Board Color', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: boardColorThemes.map((t) {
                  final isSelected = t.id == _boardTheme;
                  return GestureDetector(
                    onTap: () => setState(() => _boardTheme = t.id),
                    child: Container(
                      width: 64,
                      height: 48,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Column(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(child: Container(color: t.lightSquare)),
                                  Expanded(child: Container(color: t.darkSquare)),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(child: Container(color: t.darkSquare)),
                                  Expanded(child: Container(color: t.lightSquare)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Piece theme
          Text(l?.pieceStyle ?? 'Piece Style', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: _pieceThemes.map((t) {
                final (id, name, license) = t;
                return RadioListTile<String>(
                  value: id,
                  groupValue: _pieceTheme,
                  onChanged: (v) => setState(() => _pieceTheme = v!),
                  title: Text(name, style: const TextStyle(fontSize: 14)),
                  subtitle: Text(license, style: const TextStyle(fontSize: 11)),
                  dense: true,
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 24),

          // About
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 20, color: Theme.of(context).colorScheme.onSurface),
                      const SizedBox(width: 8),
                      Text(l?.aboutCrispChess ?? 'About CrispChess',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'MIT licensed chess app with pluggable engines.\n'
                    'Built-in: Pure Dart alpha-beta engine.\n'
                    'Maia3 Dart: Neural net, human-like play (MIT).\n'
                    'Frozenight: Rust NNUE engine (MIT/Apache-2.0).\n'
                    'Lynx: C# classical HCE engine (MIT).\n'
                    'Stockfish/Lc0: GPL-3.0, downloaded separately.',
                    style: TextStyle(fontSize: 11, height: 1.5),
                  ),
                ],
              ),
            ),
          ),

          // Theme
          Text(l?.theme ?? 'Theme', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                for (final (value, label, icon) in [
                  ('system', 'System', Icons.brightness_auto),
                  ('light', 'Light', Icons.light_mode),
                  ('dark', 'Dark (AMOLED)', Icons.dark_mode),
                ])
                  RadioListTile<String>(
                    value: value,
                    groupValue: _themeMode,
                    onChanged: (v) => setState(() => _themeMode = v!),
                    title: Text(label, style: const TextStyle(fontSize: 14)),
                    secondary: Icon(icon, size: 20),
                    dense: true,
                  ),
              ],
            ),
          ),

          // Language
          const SizedBox(height: 24),
          Text(l?.language ?? 'Language', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                for (final (value, label) in [
                  ('system', l?.systemDefault ?? 'System Default'),
                  ('en', 'English'),
                  ('de', 'Deutsch'),
                ])
                  RadioListTile<String>(
                    value: value,
                    groupValue: _language,
                    onChanged: (v) => setState(() => _language = v!),
                    title: Text(label, style: const TextStyle(fontSize: 14)),
                    dense: true,
                  ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.restore, size: 18),
              label: Text(l?.resetToDefaults ?? 'Reset to defaults'),
              onPressed: () {
                setState(() {
                  _strengthLevel = 10;
                  _hintDepth = 15;
                  _selectedEngineId = fallbackEngineId;
                  _maia3Variant = '5m';
                  _animationSpeed = 2;
                  _timeControl = TimeControl.unlimited;
                  _chessVariant = ChessVariant.standard;
                  _engineHashMb = 64;
                  _engineThreads = 1;
                  _boardTheme = 'brown';
                  _notationStyle = 'algebraic';
                  _showValidMoves = true;
                  _playAsBlack = false;
                  _pieceTheme = 'chessnut';
                });
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.pop(context, {
            'strengthLevel': _strengthLevel,
            'hintDepth': _hintDepth,
            'showValidMoves': _showValidMoves,
            'allowUndo': _allowUndo,
            'animationSpeed': _animationSpeed,
            // Migrated to an id even if the user did not touch the row.
            'hintEngine': _effectiveHintEngine,
            'playAsBlack': _playAsBlack,
            'pieceTheme': _pieceTheme,
            'engineId': _selectedEngineId,
            'engine': engineLabelForId(_selectedEngineId, _customProfiles),
            'maia3Variant': _maia3Variant,
            'lc0Backend': _lc0Backend,
            'timeControl': _timeControl,
            'chessVariant': _chessVariant,
            'customBaseMinutes': _customBaseMinutes,
            'customIncrementSeconds': _customIncrementSeconds,
            'engineHashMb': _engineHashMb,
            'engineThreads': _engineThreads,
            'boardTheme': _boardTheme,
            'notationStyle': _notationStyle,
            'blindfold': _blindfold,
            'themeMode': _themeMode,
            'language': _language,
            'solidBlackPieces': _solidBlackPieces,
          });
        },
        icon: const Icon(Icons.check),
        label: Text(l?.save ?? 'Save'),
      ),
    );
  }
}

class _EngineOption {
  /// Stable id (see `engine_registry.dart`). This, not [name], is what the
  /// selection stores and what `createEngineForId` resolves.
  final String id;
  final String name;
  final String description;
  final String elo;
  final String license;
  final bool available;
  final bool gplNotice;
  final bool hasVariants;
  final bool isCustom;

  _EngineOption({
    required this.id,
    required this.name,
    required this.description,
    required this.elo,
    required this.license,
    required this.available,
    this.gplNotice = false,
    this.hasVariants = false,
    this.isCustom = false,
  });
}

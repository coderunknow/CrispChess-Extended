import 'package:flutter/material.dart';
import '../l10n/generated/app_localizations.dart';
import '../engines/generic_uci_engine.dart'
    if (dart.library.js_interop) '../engines/generic_uci_engine_web.dart';
import '../engines/uci_option.dart';
import '../services/engine_profile_store.dart';

/// Screen for managing user-added UCI engine profiles.
///
/// Allows adding engines by path, configuring UCI options,
/// and removing engines. Only available on desktop/mobile (not web).
class EngineManagerScreen extends StatefulWidget {
  const EngineManagerScreen({super.key});

  @override
  State<EngineManagerScreen> createState() => _EngineManagerScreenState();
}

class _EngineManagerScreenState extends State<EngineManagerScreen> {
  final _store = EngineProfileStore();
  List<EngineProfile> _profiles = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  Future<void> _loadProfiles() async {
    await _store.init();
    // Reading the store is asynchronous (shared_preferences), so the screen can
    // be gone by the time it answers — which threw "setState() called after
    // dispose" whenever it was popped quickly.
    if (!mounted) return;
    setState(() {
      _profiles = _store.profiles;
      _loading = false;
    });
  }

  Future<void> _addEngine() async {
    final l = AppLocalizations.of(context);
    final controller = TextEditingController();
    final nameController = TextEditingController();

    final result = await showDialog<EngineProfile>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l?.addUciEngine ?? 'Add UCI Engine'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: l?.engineBinaryPath ?? 'Engine binary path',
                hintText: '/usr/local/bin/stockfish',
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: l?.displayName ?? 'Display name (optional)',
                hintText: l?.leaveBlankAutoDetect ?? 'Leave blank to auto-detect',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l?.cancel ?? 'Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final path = controller.text.trim();
              if (path.isEmpty) return;
              Navigator.pop(ctx, EngineProfile(
                name: nameController.text.trim(),
                path: path,
              ));
            },
            child: Text(l?.add ?? 'Add'),
          ),
        ],
      ),
    );

    if (result == null) return;

    // Probe the engine to detect its name and options
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l?.probingEngine ?? 'Probing engine...')),
      );
    }

    final engine = GenericUciEngine(result);
    var disposed = false;
    try {
      // initialize() throws when the binary cannot be started or does not
      // answer `uci`. It used to swallow that and return normally, so a broken
      // path was still saved as an engine and only surfaced on the first move.
      await engine.initialize();
      engine.dispose();
      disposed = true;

      await _store.add(result);
      await _loadProfiles();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l?.engineAdded(result.displayName) ??
                'Added: ${result.displayName}'
                    ' (${result.optionCount} UCI options)'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l?.engineInitFailed('$e') ??
                'Engine failed to initialize: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (!disposed) engine.dispose();
    }
  }

  Future<void> _configureEngine(EngineProfile profile) async {
    final engine = GenericUciEngine(profile);

    // Show loading
    if (mounted) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l?.loadingEngineOptions ?? 'Loading engine options...'), duration: const Duration(seconds: 1)),
      );
    }

    try {
      await engine.initialize();
      if (!mounted) { engine.dispose(); return; }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => _UciOptionsScreen(
            engine: engine,
            profile: profile,
            onSave: (overrides) async {
              profile.optionOverrides
                ..clear()
                ..addAll(overrides);
              // By id, not by position: the list can be reordered by a delete
              // while this screen is open, and the old index would then have
              // written the options over a different engine.
              await _store.update(profile);
              await _loadProfiles();
            },
          ),
        ),
      );

      engine.dispose();
    } catch (e) {
      engine.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load engine: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _removeEngine(EngineProfile profile) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l?.removeEngine ?? 'Remove Engine?'),
        content: Text(l?.removeEngineConfirm(profile.name) ?? 'Remove "${profile.name}" from your engine list?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l?.cancel ?? 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l?.remove ?? 'Remove')),
        ],
      ),
    );

    if (confirmed == true) {
      await _store.remove(profile.id);
      await _loadProfiles();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l?.engineManager ?? 'Engine Manager')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _profiles.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.memory, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(l?.noCustomEngines ?? 'No custom engines added'),
                      const SizedBox(height: 8),
                      Text(
                        l?.noCustomEnginesSubtitle ?? 'Add any UCI-compatible chess engine\nby providing the path to its binary.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _profiles.length,
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (context, index) {
                    final profile = _profiles[index];
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.memory),
                        title: Text(profile.displayName),
                        subtitle: Text(
                          profile.detectedName != null &&
                                  profile.detectedName != profile.displayName
                              ? '${profile.detectedName} · ${profile.path}'
                              : profile.path,
                          style: const TextStyle(fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.settings, size: 20),
                              tooltip: l?.configure ?? 'Configure',
                              onPressed: () => _configureEngine(profile),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete, size: 20, color: Colors.red.shade300),
                              tooltip: l?.remove ?? 'Remove',
                              onPressed: () => _removeEngine(profile),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addEngine,
        icon: const Icon(Icons.add),
        label: Text(l?.addEngine ?? 'Add Engine'),
      ),
    );
  }
}

/// Screen that displays auto-generated UCI option controls for an engine.
class _UciOptionsScreen extends StatefulWidget {
  final GenericUciEngine engine;
  final EngineProfile profile;
  final Future<void> Function(Map<String, String> overrides) onSave;

  const _UciOptionsScreen({
    required this.engine,
    required this.profile,
    required this.onSave,
  });

  @override
  State<_UciOptionsScreen> createState() => _UciOptionsScreenState();
}

class _UciOptionsScreenState extends State<_UciOptionsScreen> {
  late Map<String, String> _overrides;

  /// One controller per option, created once.
  ///
  /// These used to be built inside `build`, so every `setState` — that is,
  /// every keystroke that mattered and every slider tick — replaced the
  /// controller under the field, resetting the caret to the start and
  /// dropping whatever the user was in the middle of typing.
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _overrides = Map.of(widget.profile.optionOverrides);
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String name, String initial) =>
      _controllers.putIfAbsent(
          name, () => TextEditingController(text: initial));

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final options = widget.engine.options;
    // Filter out internal/debug options that most users don't need
    final userOptions = options.where((o) =>
      o.name != 'UCI_Chess960' &&
      o.name != 'UCI_ShowWDL' &&
      o.name != 'Debug Log File'
    ).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.engine.name),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _overrides.clear());
            },
            child: Text(l?.reset ?? 'Reset'),
          ),
        ],
      ),
      body: userOptions.isEmpty
          ? Center(child: Text(l?.noConfigurableOptions ?? 'No configurable options'))
          : ListView.builder(
              itemCount: userOptions.length,
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, index) {
                final opt = userOptions[index];
                return _buildOptionWidget(opt);
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await widget.onSave(_overrides);
          if (mounted) Navigator.pop(context);
        },
        icon: const Icon(Icons.save),
        label: Text(l?.save ?? 'Save'),
      ),
    );
  }

  Widget _buildOptionWidget(UciOption opt) {
    final currentValue = _overrides[opt.name] ?? opt.value ?? opt.defaultValue ?? '';

    switch (opt.type) {
      case UciOptionType.check:
        return SwitchListTile(
          title: Text(opt.name),
          value: currentValue.toLowerCase() == 'true',
          onChanged: (val) {
            setState(() => _overrides[opt.name] = val.toString());
          },
        );

      case UciOptionType.spin:
        final intVal = int.tryParse(currentValue) ?? opt.min ?? 0;
        final min = opt.min ?? 0;
        final max = opt.max ?? 100;
        // Use slider for reasonable ranges, text field for large ranges
        if (max - min <= 100) {
          return ListTile(
            title: Text('${opt.name}: $intVal'),
            subtitle: Slider(
              value: intVal.clamp(min, max).toDouble(),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: max - min > 0 ? max - min : 1,
              label: intVal.toString(),
              onChanged: (val) {
                setState(() => _overrides[opt.name] = val.round().toString());
              },
            ),
          );
        }
        // Large range — show text field
        return ListTile(
          title: Text(opt.name),
          subtitle: Text(AppLocalizations.of(context)?.rangeMinMax('$min', '$max') ?? 'Range: $min – $max', style: const TextStyle(fontSize: 11)),
          trailing: SizedBox(
            width: 80,
            child: TextField(
              controller: _controllerFor(opt.name, intVal.toString()),
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (val) {
                final parsed = int.tryParse(val);
                if (parsed != null) {
                  setState(() => _overrides[opt.name] = parsed.clamp(min, max).toString());
                }
              },
            ),
          ),
        );

      case UciOptionType.combo:
        // A saved override that the engine no longer advertises (it was
        // reconfigured, or the value came from a different build) is not one of
        // the dropdown's items, and DropdownButton asserts on that in debug and
        // renders nothing in release. Fall back to no selection instead.
        final comboValue = (opt.comboValues ?? const <String>[])
                .contains(currentValue)
            ? currentValue
            : null;
        return ListTile(
          title: Text(opt.name),
          trailing: DropdownButton<String>(
            value: comboValue,
            underline: const SizedBox.shrink(),
            onChanged: (val) {
              if (val != null) setState(() => _overrides[opt.name] = val);
            },
            items: (opt.comboValues ?? []).map((v) {
              return DropdownMenuItem(value: v, child: Text(v, style: const TextStyle(fontSize: 13)));
            }).toList(),
          ),
        );

      case UciOptionType.string:
        return ListTile(
          title: Text(opt.name),
          trailing: SizedBox(
            width: 200,
            child: TextField(
              controller: _controllerFor(opt.name, currentValue),
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (val) {
                setState(() => _overrides[opt.name] = val);
              },
            ),
          ),
        );

      case UciOptionType.button:
        return ListTile(
          title: Text(opt.name),
          trailing: OutlinedButton(
            onPressed: () => widget.engine.pressButton(opt.name),
            child: Text(AppLocalizations.of(context)?.run ?? 'Run'),
          ),
        );
    }
  }
}

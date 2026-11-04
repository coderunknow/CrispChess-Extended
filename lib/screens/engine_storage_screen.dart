/// Engine Manager: one storage root, the published artifact catalog, and
/// verified download state for every downloadable engine and model.
///
/// The screen never says "installed" for bytes it has not verified. When an
/// upstream publishes no checksum, the row says so instead of implying
/// authenticity it cannot prove. Platform limitations (Android executables in
/// app-private storage, iOS sandbox, browser-managed persistence on the web) are
/// stated next to the controls that would otherwise promise more.
library;

import 'package:flutter/material.dart';

import '../engines/download_manager.dart';
import '../engines/engine_artifacts.dart';
import '../engines/engine_registry.dart';
import '../engines/engine_storage.dart';
import '../l10n/generated/app_localizations.dart';
import '../widgets/engine_lab/lab_widgets.dart';

class EngineStorageScreen extends StatefulWidget {
  const EngineStorageScreen({
    super.key,
    this.storage,
    this.pickDirectory,
  });

  /// Test seam: an injected storage implementation.
  final EngineStorage? storage;

  /// Test seam for the native directory chooser.
  final Future<String?> Function()? pickDirectory;

  @override
  State<EngineStorageScreen> createState() => _EngineStorageScreenState();
}

class _EngineStorageScreenState extends State<EngineStorageScreen> {
  /// One storage instance per screen: the injected one in tests, otherwise the
  /// real root from Settings. The manager is created lazily and disposed once.
  late final EngineStorage _storage =
      widget.storage ?? EngineStorage.shared;
  late final EngineDownloadManager _downloads =
      EngineDownloadManager(storage: _storage);
  final TextEditingController _pathController = TextEditingController();
  EngineStorageLocation? _location;
  Map<String, List<ArtifactStatus>> _statuses = {};
  String? _pathDraft;
  String? _message;
  bool _busy = false;
  String? _downloadingId;
  DownloadProgress? _progress;
  List<EngineArtifact> _catalog = const [];

  @override
  void initState() {
    super.initState();
    _downloads.progress.listen((event) {
      if (!mounted) return;
      setState(() => _progress = event);
    });
    _load();
  }

  @override
  void dispose() {
    _downloads.dispose();
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final location = await _storage.location(refresh: true);
    final catalog = engineArtifactCatalog();
    final statuses = <String, List<ArtifactStatus>>{};
    for (final artifact in catalog) {
      statuses.putIfAbsent(artifact.engineId, () => []).add(
          await inspectArtifact(artifact, _downloads));
    }
    if (!mounted) return;
    setState(() {
      _location = location;
      _catalog = catalog;
      _statuses = statuses;
      _pathDraft ??= location.isBrowserManaged ? '' : location.rootPath;
      if (!location.isBrowserManaged && _pathController.text.isEmpty) {
        _pathController.text = location.rootPath;
      }
    });
  }

  Future<void> _changeRoot() async {
    final l = AppLocalizations.of(context);
    if (_location?.isBrowserManaged ?? true) {
      setState(() => _message = l?.storageBrowserManaged ??
          'A browser cannot choose a filesystem directory. Downloads use '
              'browser-managed Cache Storage, which the browser may evict; '
              'report exports are the durable record.');
      return;
    }
    String? path = _pathDraft;
    final picker = widget.pickDirectory;
    if (picker != null) {
      path = await picker();
    } else if (mounted) {
      final controller = TextEditingController(text: _pathDraft ?? '');
      path = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l?.engineStorage ?? 'Engine storage'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l?.engineStoragePath ?? 'Absolute directory path',
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l?.cancel ?? 'Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(l?.save ?? 'Save'),
            ),
          ],
        ),
      );
    }
    if (path == null || path.isEmpty) return;
    // Both branches above awaited something the user controls (a picker, or a
    // dialog), and the widget can be gone by now: `setState` on a disposed
    // State throws outside the try below.
    if (!mounted) return;
    setState(() => _busy = true,);
    try {
      final result = await _storage.setRoot(path);
      await _load();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _pathDraft = path;
        _message = result.summary;
      });
    } on EngineStorageError catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = error.message;
      });
    } catch (error) {
      // `setRoot` is documented to throw EngineStorageError for the cases it
      // anticipates, but the document store or the filesystem can throw
      // anything. Without this the screen stayed busy forever: the spinner ran
      // and every control stayed disabled until the app was restarted.
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'The storage root could not be changed: $error';
      });
    }
  }

  Future<void> _download(EngineArtifact artifact) async {
    setState(() {
      _downloadingId = artifact.engineId;
      _message = null;
    });
    String message;
    try {
      final result = await _downloads.download(artifact);
      await _load();
      message = '${artifact.label}: ${result.message}';
    } catch (error) {
      // `download` is documented to return a failed result rather than throw,
      // but `_load` can still throw (a filesystem or hashing error while
      // re-inspecting the artifact). Without this, `_downloadingId` stayed set
      // and every Download button on the screen stayed disabled, with the
      // spinner running, until the app was restarted.
      message = '${artifact.label}: $error';
      try {
        await _load();
      } catch (_) {
        // Nothing further to report; the message below is the real failure.
      }
    }
    if (!mounted) return;
    setState(() {
      _downloadingId = null;
      _progress = null;
      _message = message;
    });
  }

  String _statusLabel(EngineArtifact artifact, ArtifactStatus status) {
    if (artifact.sources.isEmpty) return 'Not available for this platform';
    if (status.installed && status.verified) {
      return status.upstreamAuthenticated
          ? 'Installed · upstream checksum verified'
          : 'Installed · local hash only (upstream publishes none)';
    }
    if (status.installed) return 'Installed · hash not verified';
    return 'Not installed';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final location = _location;
    return Scaffold(
      appBar: AppBar(title: Text(l?.engineManager ?? 'Engine Manager')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          LabSection(
            title: l?.engineStorage ?? 'Engine storage',
            subtitle: location == null ? null : location.layoutSummary,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (location != null)
                LabInfoRow(
                  label: l?.engineStorageLocation ?? 'Location',
                  value: location.isBrowserManaged
                      ? 'Browser-managed Cache Storage'
                      : redactStoragePath(location.rootPath),
                ),
              if (location != null && location.mode == EngineStorageMode.userDirectoryAndroid)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l?.engineStorageAndroidNote ??
                        'Android cannot execute files from shared storage: '
                            'models and archives use this folder, executables '
                            'are installed in app-private storage.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (location != null && location.mode == EngineStorageMode.appSandbox)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l?.engineStorageIosNote ??
                        'iOS apps may only write inside their sandbox and cannot '
                            'execute downloaded native binaries. Script/model '
                            'engines remain available.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 12),
              if (widget.pickDirectory != null || !(location?.isBrowserManaged ?? true))
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _pathController,
                      onChanged: (value) => _pathDraft = value,
                      decoration: InputDecoration(
                        labelText: l?.engineStoragePath ?? 'Absolute directory path',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _changeRoot,
                    child: Text(l?.changeStorage ?? 'Change'),
                  ),
                ]),
              if (_busy) const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_message!, style: Theme.of(context).textTheme.bodySmall),
                ),
            ]),
          ),
          const SizedBox(height: 16),
          LabSection(
            title: l?.downloadableEngines ?? 'Engines and models',
            subtitle: l?.downloadableEnginesSubtitle ??
                'Only the dependencies an approved benchmark schedule needs are '
                    'downloaded. Every artifact comes from its official source.',
            child: Column(children: [
              for (final artifact in _catalog)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text('${artifact.label} ${artifact.version}',
                              style: Theme.of(context).textTheme.titleSmall),
                        ),
                        if (_downloadingId == artifact.engineId)
                          const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2))
                        else
                          FilledButton.tonal(
                            onPressed: artifact.sources.isEmpty || _downloadingId != null
                                ? null
                                : () => _download(artifact),
                            child: Text(l?.download ?? 'Download'),
                          ),
                      ]),
                      const SizedBox(height: 6),
                      for (final status in _statuses[artifact.engineId] ?? const <ArtifactStatus>[])
                        Text(_statusLabel(artifact, status),
                            style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 4),
                      for (final source in artifact.sources) ...[
                        LabInfoRow(label: 'Source', value: source.url),
                        LabInfoRow(label: 'Licence', value: '${source.license} · ${source.licenseUrl}'),
                        LabInfoRow(label: 'Integrity', value: source.integrityLabel),
                        if (source.bytes != null)
                          LabInfoRow(label: 'Size', value: '${source.bytes} bytes'),
                      ],
                      if (artifact.sources.isEmpty)
                        Text(l?.notAvailableOnPlatform ??
                            'No official artifact is distributed for this platform.',
                            style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                ),
              if (_progress != null && _downloadingId != null)
                LinearProgressIndicator(value: _progress!.fraction),
            ]),
          ),
          const SizedBox(height: 16),
          LabSection(
            title: l?.customEngines ?? 'Custom UCI engines',
            child: Text(customEnginesSupported
                ? (l?.customEnginesSupportedNote ??
                    'Add a UCI engine from Engine Lab; it joins the opponent '
                        'candidate pool for intelligent benchmarks.')
                : (l?.customEnginesUnsupportedNote ??
                    'Custom engine processes are not available on this platform. '
                        'On the web no process can be spawned; on iOS a '
                        'downloaded binary cannot be executed inside the app.'),
                style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

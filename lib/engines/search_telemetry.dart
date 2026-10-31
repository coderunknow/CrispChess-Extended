/// Search telemetry published by engines that actually report it.
///
/// A benchmark that shows "nodes per second: 0" for an engine that never
/// reported a node count is worse than one that says the number is
/// unavailable, and adding a `nodes` getter to [ChessEngine] would break every
/// implementer — `implements` inherits no default implementation, so each
/// engine would have to be edited for a number most of them cannot produce.
///
/// This is therefore an optional interface: the Engine Lab asks
/// `engine is SearchTelemetry` and reports "unavailable" when it is not.
library;

/// Counters from the last completed search.
class SearchStatistics {
  /// Nodes visited, when the engine reports `nodes`.
  final int? nodes;

  /// Nodes per second as reported (`nps`), otherwise derived from [nodes] and
  /// the reported search time.
  final int? nps;

  /// Last reported `info depth`.
  final int? depth;

  /// Last reported `info time` in milliseconds.
  final int? timeMs;

  /// Hash table fill in permille, when reported (`hashfull`).
  final int? hashFullPerMille;

  /// Tablebase hits, when reported (`tbhits`).
  final int? tablebaseHits;

  const SearchStatistics({
    this.nodes,
    this.nps,
    this.depth,
    this.timeMs,
    this.hashFullPerMille,
    this.tablebaseHits,
  });

  /// No numbers were available.
  static const SearchStatistics none = SearchStatistics();

  bool get hasAnySearchData =>
      nodes != null || nps != null || depth != null || timeMs != null;

  SearchStatistics merge(SearchStatistics later) => SearchStatistics(
        nodes: later.nodes ?? nodes,
        nps: later.nps ?? nps,
        depth: later.depth ?? depth,
        timeMs: later.timeMs ?? timeMs,
        hashFullPerMille: later.hashFullPerMille ?? hashFullPerMille,
        tablebaseHits: later.tablebaseHits ?? tablebaseHits,
      );

  Map<String, dynamic> toJson() => {
        if (nodes != null) 'nodes': nodes,
        if (nps != null) 'nps': nps,
        if (depth != null) 'depth': depth,
        if (timeMs != null) 'timeMs': timeMs,
        if (hashFullPerMille != null) 'hashFull': hashFullPerMille,
        if (tablebaseHits != null) 'tbhits': tablebaseHits,
      };

  /// Reads a saved record; unknown or mistyped fields are dropped rather than
  /// thrown on, because a report is worth more than its worst field.
  factory SearchStatistics.fromJson(Map<String, dynamic> json) {
    int? read(String key) {
      final value = json[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    return SearchStatistics(
      nodes: read('nodes'),
      nps: read('nps'),
      depth: read('depth'),
      timeMs: read('timeMs'),
      hashFullPerMille: read('hashFull'),
      tablebaseHits: read('tbhits'),
    );
  }

  @override
  String toString() =>
      'SearchStatistics(nodes: $nodes, nps: $nps, depth: $depth, time: $timeMs)';
}

/// Implemented by engines whose protocol exposes search counters.
abstract interface class SearchTelemetry {
  /// Counters from the most recent search, or [SearchStatistics.none].
  SearchStatistics get lastSearchStatistics;

  /// Clears the counters, so one search's numbers are not attributed to the
  /// next one.
  void resetSearchStatistics();
}

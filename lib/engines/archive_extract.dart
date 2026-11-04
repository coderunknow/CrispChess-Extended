/// Picks the archive extractor for the running platform.
///
/// The Engine Manager downloads archives (Lynx ships as a `.zip`) and the
/// engine adapter launches an extracted binary. Two code paths with their own
/// extractors disagreed about where the result went: the Manager saved a
/// verified `.zip` and reported it installed while the engine looked for the
/// binary somewhere else and downloaded the archive again. One extractor and
/// one destination layout is what keeps them in agreement.
///
/// This file is the platform switch, so it must stay free of `dart:io`: it is
/// imported by code that also builds for the web.
library;

export 'archive_extract_io.dart'
    if (dart.library.js_interop) 'archive_extract_web.dart';

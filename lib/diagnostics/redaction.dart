/// Export-time redaction for diagnostic bundles.
///
/// Applied when a report is built, never when logs are written: locally the
/// user sees the full truth, while a shared bundle must not carry usernames,
/// personal directory paths, tokens or passwords. Technical information —
/// exception types, error codes, operation stages, timings — is preserved.
library;

/// Matches GitHub personal access tokens of the classic and fine-grained
/// forms, in case an engine path or a pasted command ever carried one.
final RegExp _githubToken = RegExp(
    r'\b(?:ghp|gho|ghu|ghs|ghr|github_pat)_[A-Za-z0-9_]{16,}\b');

/// Authorization headers with a bearer or basic scheme. Raw triple-quoted
/// because the pattern contains both quote characters; Dart's RegExp has no
/// inline flags, so case-insensitivity is set on the RegExp itself.
final RegExp _authorizationHeader = RegExp(
    r'''(authorization|proxy-authorization)("|')?\s*[:=]\s*("|')?(bearer|basic)\s+[A-Za-z0-9._\-+/=]+''',
    caseSensitive: false);

/// Key/value pairs whose key names a secret. The value runs until whitespace
/// or a quote, which covers `password=...`, `"apiKey": "..."` and
/// `token: ...` in log text.
final RegExp _secretKeyValues = RegExp(
    r'''(api[_-]?key|apikey|secret|password|passwd|pwd|token|access[_-]?token|refresh[_-]?token|client[_-]?secret)("|')?\s*[:=]\s*("|')?[^\s"',;}]+''',
    caseSensitive: false);

/// Personal home directories on Windows, Linux and macOS. `<>` are excluded
/// from the username run so the redaction *output* (`C:\Users\<user>`) does
/// not itself read as sensitive: the detector is used to prove that an
/// export is clean, and a real username cannot contain those characters.
final RegExp _windowsHome =
    RegExp(r'''C:\\Users\\[^\\:\s"',;<>]+''', caseSensitive: false);
final RegExp _posixHome = RegExp(r'''/(?:home|Users)/[^/\s"',;<>]+''');

/// Email addresses, which occasionally appear in engine author strings or
/// error messages copied from elsewhere.
final RegExp _email =
    RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b');

/// Removes personal information from [input], keeping the technical content.
String redactText(String input) {
  var output = input;
  output = output.replaceAllMapped(_githubToken, (_) => '<redacted-token>');
  output = output.replaceAllMapped(_authorizationHeader,
      (match) => '${match.group(1)}: <redacted-credentials>');
  output = output.replaceAllMapped(_secretKeyValues,
      (match) => '${match.group(1)}=<redacted>');
  output = output.replaceAllMapped(_windowsHome, (_) => 'C:\\Users\\<user>');
  output = output.replaceAllMapped(_posixHome, (_) => '/home/<user>');
  output = output.replaceAllMapped(_email, (_) => '<email>');
  return output;
}

/// Redacts every value of a string map (log record fields, metadata).
Map<String, String> redactFields(Map<String, String> fields) => {
      for (final entry in fields.entries)
        entry.key: redactText(entry.value),
    };

/// True when [text] still contains something the redaction rules cover.
/// Used by tests and by the export preview to prove the pass ran.
bool containsSensitiveText(String text) {
  return _githubToken.hasMatch(text) ||
      _authorizationHeader.hasMatch(text) ||
      _secretKeyValues.hasMatch(text) ||
      _windowsHome.hasMatch(text) ||
      _posixHome.hasMatch(text) ||
      _email.hasMatch(text);
}

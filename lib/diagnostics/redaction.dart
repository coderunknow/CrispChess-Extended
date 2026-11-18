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

/// Bare bearer/basic credentials in stringified exceptions, where no
/// header name precedes them (`Failed: Bearer abc.def.ghi`). The credential
/// run must be long enough that prose like "bearer of good tidings" never
/// matches. Raw triple-quoted: the pattern holds both quote characters.
final RegExp _bareCredentials = RegExp(
    r'''\b(bearer|basic)\s+[A-Za-z0-9._\-+/=]{16,}''',
    caseSensitive: false);

/// Authorization headers with a bearer or basic scheme. Raw triple-quoted
/// because the pattern contains both quote characters; Dart's RegExp has no
/// inline flags, so case-insensitivity is set on the RegExp itself.
final RegExp _authorizationHeader = RegExp(
    r'''(authorization|proxy-authorization)("|')?\s*[:=]\s*("|')?(bearer|basic)\s+[A-Za-z0-9._\-+/=]+''',
    caseSensitive: false);

/// Key names that mark a value as a secret. Used for structured record
/// fields, where the key alone decides: a field called `password` carries a
/// password whatever its value looks like.
/// Credential *aliases* count too: a structured field called `authToken`,
/// `oauthSecret` or `userPassword` carries a credential whatever its value.
/// Matching is normalization-based (lower-cased, separators stripped,
/// substring check) so camelCase and separators cannot hide a secret.
bool _isSecretKey(String key) {
  final normalized = key.toLowerCase().replaceAll(RegExp(r'[_\-\s]'), '');
  return _secretKeyFragments.any(normalized.contains);
}

const List<String> _secretKeyFragments = [
  'token',
  'secret',
  'password',
  'passwd',
  'pwd',
  'apikey',
  'credential',
  'authorization',
];

/// Key/value pairs whose value is a *complete quoted string* — matched
/// before the whitespace-delimited form, so a quoted value containing spaces
/// (`password="correct horse battery staple"`) is redacted whole. The
/// closing quote is required; an unclosed quote falls through to the
/// unquoted pattern below. Raw triple-quoted: the pattern holds both quote
/// characters, and Dart's RegExp has no inline flags.
final RegExp _secretQuotedValues = RegExp(
    r'''(api[_-]?key|apikey|secret|password|passwd|pwd|token|access[_-]?token|refresh[_-]?token|client[_-]?secret)("|')?\s*[:=]\s*(?:"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')''',
    caseSensitive: false);

/// Key/value pairs whose key names a secret, with an unquoted value running
/// to whitespace or a quote. Covers `password=...`, `token: ...` in log text.
// The negative lookahead keeps the detector honest about redaction output:
// `password=<redacted>` must not read as an unredacted secret.
final RegExp _secretKeyValues = RegExp(
    r'''(api[_-]?key|apikey|secret|password|passwd|pwd|token|access[_-]?token|refresh[_-]?token|client[_-]?secret)("|')?\s*[:=]\s*(?!<redacted>)[^\s"',;}]+''',
    caseSensitive: false);

/// Personal home directories on Windows, Linux and macOS. The username is
/// exactly one path segment — the match runs to the next separator, quote or
/// line end — so a profile directory containing spaces (`C:\Users\Alice
/// Smith\...`) is redacted as one segment instead of leaking "Smith" after
/// the placeholder. `<>` are excluded so the redaction *output* does not
/// read as sensitive, and a real Windows username cannot contain them.
final RegExp _windowsHome = RegExp(
    r'''[A-Za-z]:\\Users\\[^\\:\r\n"',;<>]+''',
    caseSensitive: false);
final RegExp _posixHome =
    RegExp(r'''/(?:home|Users)/[^/:\r\n"',;<>]+''');

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
  output = output.replaceAllMapped(
      _bareCredentials, (_) => '<redacted-credentials>');
  // Quoted secret values first (they may contain spaces), then the
  // whitespace-delimited form for everything the quoted pass did not close.
  output = output.replaceAllMapped(
      _secretQuotedValues, (match) => '${match.group(1)}=<redacted>');
  output = output.replaceAllMapped(
      _secretKeyValues, (match) => '${match.group(1)}=<redacted>');
  output = output.replaceAllMapped(_windowsHome, (_) => 'C:\\Users\\<user>');
  output = output.replaceAllMapped(_posixHome, (_) => '/home/<user>');
  output = output.replaceAllMapped(_email, (_) => '<email>');
  return output;
}

/// True when a field *key* names a secret, in which case the whole value is
/// replaced regardless of its content.
bool isSecretFieldName(String key) => _isSecretKey(key);

/// Redacts a string map (log record fields, metadata): a key that names a
/// secret loses its whole value, every other value passes through the text
/// redaction. Structured fields must not rely on the value text alone —
/// `{'password': 'private-value'}` must not survive because the flattened
/// line happened to be sanitized.
Map<String, String> redactFields(Map<String, String> fields) => {
      for (final entry in fields.entries)
        entry.key: _isSecretKey(entry.key)
            ? '<redacted>'
            : redactText(entry.value),
    };

/// True when [text] still contains something the redaction rules cover.
/// Used by tests and by the export preview to prove the pass ran.
bool containsSensitiveText(String text) {
  return _githubToken.hasMatch(text) ||
      _authorizationHeader.hasMatch(text) ||
      _bareCredentials.hasMatch(text) ||
      _secretQuotedValues.hasMatch(text) ||
      _secretKeyValues.hasMatch(text) ||
      _windowsHome.hasMatch(text) ||
      _posixHome.hasMatch(text) ||
      _email.hasMatch(text);
}

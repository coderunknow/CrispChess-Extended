import 'package:flutter_test/flutter_test.dart';

import 'package:crispchess/diagnostics/redaction.dart';

void main() {
  test('GitHub tokens are removed in both classic and fine-grained form',
      () {
    // Synthetic fixtures only: both are shorter than the repository's
    // no-secrets scanner threshold but long enough to exercise the redaction
    // rules (16+ characters after the prefix).
    final text = 'clone url https://x:ghp_0123456789abcdefghijklmnop@host '
        'and github_pat_0123456789abcdefghij';
    final redacted = redactText(text);
    expect(redacted, isNot(contains('ghp_0123')));
    expect(redacted, isNot(contains('github_pat_')));
    expect(redacted, contains('<redacted-token>'));
  });

  test('authorization headers are removed but the header name stays', () {
    final text = 'request sent with Authorization: Bearer abc.def.ghi-jwt '
        "and {'proxy-authorization': 'Basic dXNlcjpwYXNz'}";
    final redacted = redactText(text);
    expect(redacted, isNot(contains('abc.def')));
    expect(redacted, isNot(contains('dXNlcjpwYXNz')));
    expect(redacted, contains('<redacted-credentials>'));
  });

  test('secret-looking key/value pairs are redacted', () {
    final text = 'password=hunter2 apiKey: "sk-live-123" '
        '"refreshToken":"r1" client_secret=abc123 normal_token_ok=1';
    final redacted = redactText(text);
    expect(redacted, isNot(contains('hunter2')));
    expect(redacted, isNot(contains('sk-live-123')));
    expect(redacted, isNot(contains('r1"')));
    expect(redacted, isNot(contains('abc123')));
    expect(redacted, contains('<redacted>'));
  });

  test('personal home directories are replaced on all three platforms', () {
    final text = r'failed to load C:\Users\alice\engines\stockfish.exe '
        'and /home/bob/bin/frozenight and /Users/carol/engines/lc0';
    final redacted = redactText(text);
    expect(redacted, isNot(contains('alice')));
    expect(redacted, isNot(contains('bob')));
    expect(redacted, isNot(contains('carol')));
    expect(redacted, contains(r'C:\Users\<user>\engines\stockfish.exe'));
    expect(redacted, contains('/home/<user>/bin/frozenight'));
    expect(redacted, contains('/home/<user>/engines/lc0'));
  });

  test('email addresses are replaced', () {
    final text = 'author John Doe <john.doe@example.com> reported';
    final redacted = redactText(text);
    expect(redacted, isNot(contains('john.doe@example.com')));
    expect(redacted, contains('<email>'));
  });

  test('technical content survives: paths, codes, timings', () {
    final text = 'exit code 1 after 250ms in stage handshake '
        'path /usr/local/bin/stockfish EngineProcessDiedException';
    final redacted = redactText(text);
    expect(redacted, contains('exit code 1'));
    expect(redacted, contains('250ms'));
    expect(redacted, contains('handshake'));
    expect(redacted, contains('/usr/local/bin/stockfish'));
    expect(redacted, contains('EngineProcessDiedException'));
  });

  test('fields maps are redacted value by value', () {
    final redacted = redactFields({
      'path': r'C:\Users\dave\engine.exe',
      'command': 'uci',
      'auth': 'token=secret-value',
    });
    expect(redacted['path'], isNot(contains('dave')));
    expect(redacted['command'], 'uci');
    expect(redacted['auth'], isNot(contains('secret-value')));
  });

  test('containsSensitiveText detects what the redaction covers', () {
    expect(containsSensitiveText('ghp_0123456789abcdefghijklmnop'), isTrue);
    expect(containsSensitiveText('/home/someone/x'), isTrue);
    expect(containsSensitiveText('contact a@b.io'), isTrue);
    expect(containsSensitiveText('plain technical text, exit 1, 250ms'),
        isFalse);
  });

  test('quoted secret values are redacted whole, spaces included', () {
    // Regression (dev6 review): the unquoted value matcher stopped at the
    // first space, leaving most of a quoted passphrase in the export.
    final text = 'password="correct horse battery staple" and api_key: "sk live 123"';
    final redacted = redactText(text);
    expect(redacted, isNot(contains('horse battery')));
    expect(redacted, isNot(contains('sk live 123')));
    expect(redacted, contains('<redacted>'));
  });

  test('Windows profile paths containing spaces are redacted as one segment',
      () {
    final text = r'failed at C:\Users\Alice Smith\engines\stockfish.exe '
        'and /home/Bob Smith/bin/x';
    final redacted = redactText(text);
    expect(redacted, isNot(contains('Alice Smith')));
    expect(redacted, isNot(contains('Bob Smith')));
    expect(redacted, contains(r'C:\Users\<user>\engines\stockfish.exe'));
    expect(redacted, contains('/home/<user>/bin/x'));
  });

  test('a field whose key names a secret loses its whole value', () {
    // Regression (dev6 review): structured fields were only redacted by
    // value text, so {'password': 'private-value'} survived unchanged.
    final redacted = redactFields({
      'password': 'private-value',
      'authorization': 'Bearer abc.def',
      'enginePath': '/home/someone/x',
      'command': 'uci',
    });
    expect(redacted['password'], '<redacted>');
    expect(redacted['authorization'], '<redacted>');
    expect(redacted['enginePath'], isNot(contains('someone')));
    expect(redacted['command'], 'uci');
  });

  test('profile paths on any drive letter are redacted', () {
    // Regression (CodeRabbit dev6 review): only C:\Users matched, so a
    // missing binary on D: kept the username in the export.
    final redacted = redactText(r'D:\Users\Alice\engine.exe');
    expect(redacted, isNot(contains('Alice')));
  });

  test('bare bearer credentials in exception text are redacted', () {
    // Regression (CodeRabbit dev6 review): a stringified error can carry a
    // credential without an Authorization header name.
    final redacted = redactText('request failed: Bearer abcdef1234567890abcdef');
    expect(redacted, isNot(contains('abcdef1234567890')));
    expect(redacted, contains('<redacted-credentials>'));
  });

  test('credential aliases are recognized as secret field names', () {
    // Regression (CodeRabbit dev6 review): an authToken field carries a
    // credential even though its value has no recognizable markers.
    final redacted = redactFields({
      'authToken': 'opaque-credential-value',
      'oauthClientSecret': 'also-secret',
      'command': 'uci',
    });
    expect(redacted['authToken'], '<redacted>');
    expect(redacted['oauthClientSecret'], '<redacted>');
    expect(redacted['command'], 'uci');
  });

  test('the redacted output itself is not detected as sensitive', () {
    // Regression: the detector once flagged its own placeholder
    // `C:\Users\<user>` as sensitive, because the username run in the
    // pattern did not exclude the angle brackets of the placeholder.
    final redacted =
        redactText(r'load C:\Users\alice\engines\stockfish.exe and /home/bob/x');
    expect(containsSensitiveText(redacted), isFalse,
        reason: 'a clean export must pass the sensitivity check');
  });
}

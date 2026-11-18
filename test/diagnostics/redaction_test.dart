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

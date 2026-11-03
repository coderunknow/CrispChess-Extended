import 'dart:io';

String? platformPathRedactionHome() =>
    Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];

String? platformPathRedactionUser() =>
    Platform.environment['USER'] ?? Platform.environment['USERNAME'];

/// `windows`, `linux`, `macos`, `android` or `ios`.
String currentHostPlatform() {
  if (Platform.isWindows) return 'windows';
  if (Platform.isLinux) return 'linux';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  return 'unknown';
}

String currentHostArch() {
  final abi = Abi.current().toString();
  if (abi.contains('arm64') || abi.contains('aarch64')) return 'arm64';
  if (abi.contains('ia32')) return 'ia32';
  if (abi.contains('arm')) return 'arm';
  return 'x64';
}

String fallbackHomeDirectory() =>
    Platform.environment['HOME'] ??
    Platform.environment['APPDATA'] ??
    Directory.systemTemp.path;

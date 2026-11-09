/* MANGACA fp.dart — device fingerprint for account binding.
   Same contract as the web client: a stable sha-256 hex of device traits.
   The raw traits never leave this module — only the hash and the small
   non-sensitive trait bundle the server may store next to it. */

import 'dart:io';
import 'dart:ui' as ui;
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

String _stableStringify(Map<String, String> obj) {
  final keys = obj.keys.toList()..sort();
  return keys.map((k) => '$k=${obj[k]}').join('|');
}

String? _cached;

Future<String> deviceFingerprint() async {
  if (_cached != null) return _cached!;
  final prefs = await SharedPreferences.getInstance();
  var installId = prefs.getString('mangaca.install');
  if (installId == null) {
    installId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    await prefs.setString('mangaca.install', installId);
  }
  var screen = '0x0';
  try {
    final views = ui.PlatformDispatcher.instance.views;
    if (views.isNotEmpty) {
      screen =
          '${views.first.physicalSize.width.round()}x${views.first.physicalSize.height.round()}';
    }
  } catch (_) {}
  final traits = {
    'ua': 'MANGACA/0.0.1 (Android)',
    'lang': Platform.localeName,
    'platform': 'android',
    'cores': Platform.numberOfProcessors.toString(),
    'screen': screen,
    'tz': DateTime.now().timeZoneName,
    'touch': '5',
    'install': installId,
    'webgl': '',
    'canvas': '',
  };
  final input = _stableStringify(traits);
  _cached = sha256.convert(utf8.encode(input)).toString();
  return _cached!;
}

Map<String, String> deviceTraits() {
  var screen = '0x0';
  try {
    final views = ui.PlatformDispatcher.instance.views;
    if (views.isNotEmpty) {
      screen =
          '${views.first.physicalSize.width.round()}x${views.first.physicalSize.height.round()}';
    }
  } catch (_) {}
  return {
    'platform': 'android',
    'tz': DateTime.now().timeZoneName.substring(0, 60),
    'lang': Platform.localeName.substring(0, 60),
    'screen': screen,
    'ua': 'MANGACA/0.0.1 (Android)',
  };
}

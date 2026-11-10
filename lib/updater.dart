/* MANGACA updater.dart — delta app updates, Settings-owned.
   Protocol (identical to the production Orubus updater):
   • release/updates.json lists the latest build {version, code, url, sha256,
     size} plus OPTIONAL bsdiff deltas keyed by the version code they upgrade.
   • A device behind latest downloads JUST its delta (few MB), rebuilds the
     installed APK on device, byte-verifies sha256, and hands the result to
     the system PackageInstaller. Any failure falls back to the full APK —
     the updater can never brick an install.
   • Every download is idempotent: re-running "check for updates" recomputes
     the diff, a killed download leaves nothing half-applied.
   The native half lives in android-overlay (Updater.kt + Bspatch.kt). */

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class UpdaterLatest {
  final int code;
  final String name;
  final String url;
  final String sha256;
  final int size;
  final String notes;
  UpdaterLatest({
    required this.code,
    required this.name,
    required this.url,
    required this.sha256,
    required this.size,
    required this.notes,
  });

  factory UpdaterLatest.from(Map<dynamic, dynamic> j) => UpdaterLatest(
        code: (j['code'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? '?').toString(),
        url: (j['url'] ?? '').toString(),
        sha256: (j['sha256'] ?? '').toString(),
        size: (j['size'] as num?)?.toInt() ?? 0,
        notes: (j['notes'] ?? '').toString(),
      );
}

class UpdaterDelta {
  final int from;
  final int to;
  final String url;
  final int size;
  UpdaterDelta({required this.from, required this.to, required this.url, required this.size});

  factory UpdaterDelta.from(Map<dynamic, dynamic> j) => UpdaterDelta(
        from: (j['from'] as num?)?.toInt() ?? 0,
        to: (j['to'] as num?)?.toInt() ?? 0,
        url: (j['url'] ?? '').toString(),
        size: (j['size'] as num?)?.toInt() ?? 0,
      );
}

/* the state the Settings page renders */
class UpdateState {
  String stage = 'idle'; // idle|checking|uptodate|available|downloading|patching|verifying|installing|done|error
  double progress = 0;
  int received = 0;
  int total = 0;
  String message = '';
  UpdaterLatest? latest;
  UpdaterDelta? delta;
}

class UpdaterService with ChangeNotifier {
  static const _channel = MethodChannel('app.orubus.mangaca/updater');

  final UpdateState state = UpdateState();
  bool _busy = false;

  UpdaterService() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'progress') {
        final j = (call.arguments as Map?) ?? {};
        _apply(
          stage: (j['stage'] ?? '').toString(),
          progress: (j['progress'] as num?)?.toDouble() ?? state.progress,
          received: (j['received'] as num?)?.toInt() ?? state.received,
          total: (j['total'] as num?)?.toInt() ?? state.total,
          message: (j['message'] ?? state.message).toString(),
        );
      }
      return null;
    });
  }

  void _apply({String? stage, double? progress, int? received, int? total, String? message}) {
    if (stage != null && stage.isNotEmpty) state.stage = stage;
    if (progress != null) state.progress = progress;
    if (received != null) state.received = received;
    if (total != null) state.total = total;
    if (message != null) state.message = message;
    notifyListeners();
  }

  Future<Map<String, dynamic>> installedInfo() async {
    try {
      final r = await _channel.invokeMethod('installedVersion');
      return (r as Map?)?.cast<String, dynamic>() ?? {'code': 0, 'name': '?'};
    } catch (_) {
      return {'code': 0, 'name': '?'};
    }
  }

  /* Settings row tap — always talks. Returns the final stage. */
  Future<String> checkForUpdates() async {
    if (_busy) return state.stage;
    _busy = true;
    _apply(stage: 'checking', message: 'checking for updates…', progress: 0);
    try {
      final r = await _channel.invokeMethod('check');
      final j = (r as Map?)?.cast<String, dynamic>() ?? {};
      final ok = j['ok'] == true;
      final latest = j['latest'] is Map ? UpdaterLatest.from((j['latest'] as Map).cast<dynamic, dynamic>()) : null;
      final delta = j['delta'] is Map ? UpdaterDelta.from((j['delta'] as Map).cast<dynamic, dynamic>()) : null;
      if (!ok || latest == null || latest.code <= 0) {
        _apply(stage: 'error', message: (j['reason'] ?? "couldn't reach the update server").toString());
        return state.stage;
      }
      final curCode = (j['installedCode'] as num?)?.toInt() ?? 0;
      if (latest.code <= curCode) {
        state.latest = latest;
        state.delta = null;
        _apply(stage: 'uptodate', message: 'you are on the latest — v${latest.name}');
        return state.stage;
      }
      state.latest = latest;
      state.delta = delta;
      _apply(stage: 'available', message: delta != null ? 'delta ready — rebuilds on device' : 'full download ready');
      return state.stage;
    } catch (_) {
      _apply(stage: 'error', message: "couldn't check — the update engine didn't answer");
      return state.stage;
    } finally {
      _busy = false;
    }
  }

  /* Begin download/patch/verify/install. Progress streams in via the
     'progress' channel calls; the Settings UI just renders state.stage. */
  Future<void> startUpdate() async {
    final latest = state.latest;
    if (latest == null) return;
    _apply(stage: 'downloading', progress: 0, received: 0, total: latest.size, message: 'starting…');
    try {
      await _channel.invokeMethod('start', {
        'latest': {
          'code': latest.code,
          'name': latest.name,
          'url': latest.url,
          'sha256': latest.sha256,
          'size': latest.size,
          'notes': latest.notes,
        },
        'delta': state.delta == null
            ? null
            : {'from': state.delta!.from, 'to': state.delta!.to, 'url': state.delta!.url, 'size': state.delta!.size},
      });
    } catch (e) {
      _apply(stage: 'error', message: 'update failed — ${e.toString().split('\n').first}');
    }
  }
}

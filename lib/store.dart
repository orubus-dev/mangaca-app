/* MANGACA store.dart — on-device state, same shapes and keys as the web app.
   Guests keep everything local; signed-in readers additionally sync progress
   to the runtime. */

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'models.dart';

class TvPrefs {
  int seekSeconds;
  num holdSpeed;
  num speed;
  TvPrefs({this.seekSeconds = 10, this.holdSpeed = 2, this.speed = 1});

  Map<String, dynamic> toJson() => {'seekSeconds': seekSeconds, 'holdSpeed': holdSpeed, 'speed': speed};
  factory TvPrefs.fromJson(dynamic j) => TvPrefs(
        seekSeconds: (j is Map && j['seekSeconds'] != null) ? (j['seekSeconds'] as num).toInt() : 10,
        holdSpeed: (j is Map && j['holdSpeed'] != null) ? j['holdSpeed'] : 2,
        speed: (j is Map && j['speed'] != null) ? j['speed'] : 1,
      );
}

/* read-aloud prefs — rate 1.0 = normal speed, pitch 1.0 = natural tone */
class TtsPrefs {
  double rate;
  double pitch;
  double volume;
  TtsPrefs({this.rate = 1.0, this.pitch = 1.0, this.volume = 1.0});

  Map<String, dynamic> toJson() => {'rate': rate, 'pitch': pitch, 'volume': volume};
  factory TtsPrefs.fromJson(dynamic j) => TtsPrefs(
        rate: (j is Map && j['rate'] is num) ? (j['rate'] as num).toDouble() : 1.0,
        pitch: (j is Map && j['pitch'] is num) ? (j['pitch'] as num).toDouble() : 1.0,
        volume: (j is Map && j['volume'] is num) ? (j['volume'] as num).toDouble() : 1.0,
      );
}

class AppSettings {
  String theme; // auto | dark | light
  String readerMode; // webtoon | paged-ltr | paged-rtl
  String textTheme; // paper | sepia | night | black
  int textSize;
  TvPrefs tv;
  TtsPrefs tts;
  String cookieMode; // essential | all | not set
  AppSettings({
    this.theme = 'auto',
    this.readerMode = 'webtoon',
    this.textTheme = 'night',
    this.textSize = 18,
    TvPrefs? tv,
    TtsPrefs? tts,
    this.cookieMode = 'not set',
  })  : tv = tv ?? TvPrefs(),
        tts = tts ?? TtsPrefs();

  Map<String, dynamic> toJson() => {
        'theme': theme,
        'readerMode': readerMode,
        'textTheme': textTheme,
        'textSize': textSize,
        'tv': tv.toJson(),
        'tts': tts.toJson(),
        'cookieMode': cookieMode,
      };
  factory AppSettings.fromJson(dynamic j) {
    final m = (j is Map) ? j : <String, dynamic>{};
    return AppSettings(
      theme: m['theme'] ?? 'auto',
      readerMode: m['readerMode'] ?? 'webtoon',
      textTheme: m['textTheme'] ?? 'night',
      textSize: (m['textSize'] ?? 18) is int ? m['textSize'] : 18,
      tv: TvPrefs.fromJson(m['tv']),
      tts: TtsPrefs.fromJson(m['tts']),
      cookieMode: m['cookieMode'] ?? 'not set',
    );
  }
}

class HistoryEntry {
  final String sid, bid, title, cover, cid, ctitle;
  final int at;
  HistoryEntry({
    required this.sid,
    required this.bid,
    required this.title,
    this.cover = '',
    this.cid = '',
    this.ctitle = '',
    this.at = 0,
  });

  Map<String, dynamic> toJson() => {
        'sid': sid, 'bid': bid, 'title': title, 'cover': cover,
        'cid': cid, 'ctitle': ctitle, 'at': at,
      };
  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        sid: j['sid'] ?? '', bid: j['bid'] ?? '', title: j['title'] ?? '',
        cover: j['cover'] ?? '', cid: j['cid'] ?? '', ctitle: j['ctitle'] ?? '',
        at: (j['at'] ?? 0) is int ? j['at'] : 0,
      );
}

class ProgressEntry {
  final String cid, ctitle;
  final int page, total, at;
  ProgressEntry({required this.cid, this.ctitle = '', this.page = 0, this.total = 0, this.at = 0});

  Map<String, dynamic> toJson() => {'cid': cid, 'ctitle': ctitle, 'page': page, 'total': total, 'at': at};
  factory ProgressEntry.fromJson(Map<String, dynamic> j) => ProgressEntry(
        cid: j['cid'] ?? '', ctitle: j['ctitle'] ?? '',
        page: (j['page'] ?? 0) is int ? j['page'] : 0,
        total: (j['total'] ?? 0) is int ? j['total'] : 0,
        at: (j['at'] ?? 0) is int ? j['at'] : 0,
      );
}

class Store {
  static MUser? user;
  static String? sessionToken;

  static AppSettings settings = AppSettings();
  static List<Map<String, dynamic>> library = [];
  static List<HistoryEntry> history = [];
  static Map<String, ProgressEntry> progress = {};
  static Map<String, List<String>> read = {};

  static const _ns = 'mangaca.v2.';
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final p = _prefs!;
    settings = AppSettings.fromJson(_load(p, 'settings', null));
    library = List<Map<String, dynamic>>.from(_load(p, 'library', []) ?? []);
    history = ((_load(p, 'history', []) ?? []) as List)
        .whereType<Map<String, dynamic>>()
        .map((m) => HistoryEntry.fromJson(m))
        .toList();
    progress = ((_load(p, 'progress', {}) ?? {}) as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, ProgressEntry.fromJson(Map<String, dynamic>.from(v ?? {}))));
    read = ((_load(p, 'read', {}) ?? {}) as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, List<String>.from((v as List?) ?? [])));
    final cachedUser = _load(p, 'user.cache', null);
    if (cachedUser is Map<String, dynamic> && cachedUser['username'] != null) {
      user = MUser(
        username: cachedUser['username'],
        display: cachedUser['display'] ?? cachedUser['username'],
        sub: cachedUser['sub'] ?? '',
      );
    }
    sessionToken = p.getString('${_ns}session');
  }

  static dynamic _load(SharedPreferences p, String key, dynamic fallback) {
    final raw = p.getString('$_ns$key');
    if (raw == null) return fallback;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return fallback;
    }
  }

  static void _save(String key, dynamic value) {
    _prefs?.setString('$_ns$key', jsonEncode(value));
  }

  static void setSessionToken(String? token) {
    sessionToken = token;
    if (token == null) {
      _prefs?.remove('${_ns}session');
    } else {
      _prefs?.setString('${_ns}session', token);
    }
  }

  static void saveSettings() => _save('settings', settings.toJson());

  static String bookKey(String sid, String bid) => '$sid:$bid';

  static bool inLibrary(String sid, String bid) =>
      library.any((b) => b['sid'] == sid && b['bid'] == bid);

  static void addLibrary(BookItem book) {
    if (inLibrary(book.sid, book.bid)) return;
    library.insert(0, {
      ...book.toMini(),
      'addedAt': DateTime.now().millisecondsSinceEpoch,
    });
    _save('library', library);
  }

  static void removeLibrary(String sid, String bid) {
    library.removeWhere((b) => b['sid'] == sid && b['bid'] == bid);
    _save('library', library);
  }

  static void pushHistory(HistoryEntry entry) {
    history.removeWhere((h) => h.sid == entry.sid && h.bid == entry.bid && h.cid == entry.cid);
    history.insert(0, entry);
    if (history.length > 200) history = history.sublist(0, 200);
    _save('history', history.map((h) => h.toJson()).toList());
  }

  static void setProgress(String sid, String bid, ProgressEntry data) {
    final key = bookKey(sid, bid);
    final prev = progress[key];
    if (prev != null && prev.cid == data.cid && data.page <= prev.page && data.total == prev.total) {
      return;
    }
    progress[key] = data;
    _save('progress', progress.map((k, v) => MapEntry(k, v.toJson())));
  }

  static ProgressEntry? getProgress(String sid, String bid) => progress[bookKey(sid, bid)];

  static void markRead(String sid, String bid, String cid) {
    final key = bookKey(sid, bid);
    final list = read[key] ?? [];
    if (!list.contains(cid)) {
      list.add(cid);
      read[key] = list;
      _save('read', read);
    }
  }

  static bool isRead(String sid, String bid, String cid) =>
      (read[bookKey(sid, bid)] ?? []).contains(cid);

  static void mergeServerProgress(List<dynamic> items) {
    for (final row in items) {
      if (row is! Map<String, dynamic>) continue;
      final mangaId = (row['manga_id'] ?? '') as String;
      if (mangaId.isEmpty) continue;
      final at = DateTime.tryParse((row['updated_at'] ?? '') as String)
              ?.millisecondsSinceEpoch ??
          0;
      final cur = progress[mangaId];
      if (cur == null || at >= cur.at) {
        progress[mangaId] = ProgressEntry(
          cid: (row['chapter_id'] ?? '') as String,
          ctitle: '',
          page: ((row['page'] ?? 0) as num).toInt(),
          total: ((row['total_pages'] ?? 0) as num).toInt(),
          at: at,
        );
      }
    }
    _save('progress', progress.map((k, v) => MapEntry(k, v.toJson())));
  }

  static void setUser(MUser? u) {
    user = u;
    _save('user.cache', u == null ? null : {
      'username': u.username,
      'display': u.display,
      'sub': u.sub,
    });
  }
}

/* MANGACA api.dart — client for the production runtime (mangaca.pages.dev/api/*).
   Same contracts as the web client. The session token (mg_session) returned
   by sign-in is stored on-device and attached as a cookie on every call —
   the server treats the app exactly like another browser. */

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'fp.dart';
import 'models.dart';
import 'store.dart';

const String BASE = 'https://mangaca.pages.dev';

/// absolutize a runtime-relative URL (posters, streams, originals pages)
String abs(String u) {
  if (u.startsWith('/')) return BASE + u;
  if (u.startsWith('assets/')) return '$BASE/$u';
  return u;
}

String px(String u) => '$BASE/api/proxy?u=${Uri.encodeComponent(u)}';
String imgx(String u) => '$BASE/api/img?u=${Uri.encodeComponent(u)}';

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

Map<String, String> _headers({bool json = false}) {
  final h = <String, String>{
    'User-Agent': 'MANGACA/0.0.1 (Android)',
  };
  final token = Store.sessionToken;
  if (token != null && token.isNotEmpty) h['Cookie'] = 'mg_session=$token';
  if (json) h['Content-Type'] = 'application/json';
  return h;
}

Future<dynamic> _decode(http.Response r) async {
  try {
    return jsonDecode(utf8.decode(r.bodyBytes));
  } catch (_) {
    return <String, dynamic>{};
  }
}

void _captureSession(http.Response r) {
  final sc = r.headers['set-cookie'];
  if (sc == null) return;
  final m = RegExp('mg_session=([^;]+)').firstMatch(sc);
  if (m != null) {
    Store.setSessionToken(m.group(1)!);
  }
}

Future<Map<String, dynamic>> get(String path) async {
  final r = await http
      .get(Uri.parse(path.startsWith('http') ? path : BASE + path), headers: _headers())
      .timeout(const Duration(seconds: 30));
  final j = await _decode(r);
  if (j is Map<String, dynamic>) {
    j['_status'] = r.statusCode;
    j['ok'] = r.statusCode >= 200 && r.statusCode < 300 && j['ok'] != false;
    return j;
  }
  return {'ok': r.statusCode >= 200 && r.statusCode < 300, '_status': r.statusCode};
}

Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
  final r = await http
      .post(Uri.parse(BASE + path), headers: _headers(json: true), body: jsonEncode(body))
      .timeout(const Duration(seconds: 30));
  final j = await _decode(r);
  final out = j is Map<String, dynamic> ? j : <String, dynamic>{};
  out['_status'] = r.statusCode;
  out['ok'] = r.statusCode >= 200 && r.statusCode < 300 && out['ok'] != false;
  return out;
}

/* ---------------- health ---------------- */
Future<Map<String, dynamic>> health() => get('/api/health');

/* ---------------- genjutsu auth (passwordless) ---------------- */
Future<Map<String, dynamic>> authCodeClaim(String code) async {
  final fp = await deviceFingerprint();
  final r = await http
      .post(Uri.parse('$BASE/api/auth/genjutsu-code'),
          headers: _headers(json: true),
          body: jsonEncode({'code': code, 'fp': fp, ...deviceTraits()}))
      .timeout(const Duration(seconds: 30));
  final j = await _decode(r);
  final out = j is Map<String, dynamic> ? j : <String, dynamic>{};
  out['_status'] = r.statusCode;
  out['ok'] = r.statusCode >= 200 && r.statusCode < 300 && out['ok'] != false;
  if (out['ok'] == true) _captureSession(r);
  return out;
}

Future<Map<String, dynamic>> authMe() => get('/api/auth/me');
Future<Map<String, dynamic>> authLogout() async {
  final r = await post('/api/auth/logout', {});
  Store.setSessionToken(null);
  return r;
}

Future<Map<String, dynamic>> authProfile(String username, String role) =>
    post('/api/auth/profile', {'username': username, 'role': role});

/* ---------------- social ---------------- */
Future<Map<String, dynamic>> socialState(String book) =>
    get('/api/social/state?book=${Uri.encodeComponent(book)}');
Future<Map<String, dynamic>> socialLike(String book) => post('/api/social/like', {'book': book});
Future<Map<String, dynamic>> socialFavorite(String book) =>
    post('/api/social/favorite', {'book': book});
Future<Map<String, dynamic>> socialComment(String book, String body, {String chapter = ''}) =>
    post('/api/social/comment', {'book': book, 'body': body, 'chapter': chapter});
Future<Map<String, dynamic>> librarySet(String book, String? status, {bool remove = false}) =>
    post('/api/social/library', {'book': book, 'status': status, 'remove': remove});

/* ---------------- progress ---------------- */
Future<Map<String, dynamic>> progressList() => get('/api/progress/list');
Future<Map<String, dynamic>> progressSave(String book, String chapter, int page, int total) =>
    post('/api/progress/save', {'book': book, 'chapter': chapter, 'page': page, 'total': total});

/* ---------------- catalog (server extension layer) ---------------- */
Future<Map<String, dynamic>> catalogBrowse(String kind, String tab, int page) =>
    get('/api/catalog/browse?kind=$kind&tab=$tab&page=$page');
Future<Map<String, dynamic>> catalogSearch(String q, String kind, int page) =>
    get('/api/catalog/search?q=${Uri.encodeComponent(q)}&kind=$kind&page=$page');
Future<Map<String, dynamic>> catalogDetails(String src, String id, {String cover = ''}) =>
    get('/api/catalog/details?src=${Uri.encodeComponent(src)}&id=${Uri.encodeComponent(id)}${cover.isNotEmpty ? '&cover=${Uri.encodeComponent(cover)}' : ''}');
Future<Map<String, dynamic>> catalogChapters(String src, String id) =>
    get('/api/catalog/chapters?src=${Uri.encodeComponent(src)}&id=${Uri.encodeComponent(id)}');
Future<Map<String, dynamic>> catalogPages(String src, String id) =>
    get('/api/catalog/pages?src=${Uri.encodeComponent(src)}&id=${Uri.encodeComponent(id)}');
Future<Map<String, dynamic>> catalogContent(String src, String id) =>
    get('/api/catalog/content?src=${Uri.encodeComponent(src)}&id=${Uri.encodeComponent(id)}');

/* ---------------- TV (catalog rows + playback) ---------------- */
Future<List<TvItem>> tvRow(String rowId, {int page = 1}) async {
  final r = await get('/api/tv/row?row=${Uri.encodeComponent(rowId)}&page=$page');
  final items = (r['items'] as List?) ?? const [];
  return items
      .whereType<Map<String, dynamic>>()
      .map((m) => TvItem(
            id: m['id'] ?? '',
            title: m['title'] ?? '',
            poster: abs(m['poster'] ?? ''),
            tagline: m['tagline'] ?? '',
            kind: m['kind'] ?? '',
            provider: m['provider'] ?? '',
            description: m['description'] ?? '',
          ))
      .toList();
}

Future<List<TvItem>> tvSearchAll(String q) async {
  final r = await get('/api/tv/search?q=${Uri.encodeComponent(q)}');
  final items = (r['items'] as List?) ?? const [];
  return items
      .whereType<Map<String, dynamic>>()
      .map((m) => TvItem(
            id: m['id'] ?? '',
            title: m['title'] ?? '',
            poster: abs(m['poster'] ?? ''),
            tagline: m['tagline'] ?? '',
            kind: m['kind'] ?? '',
            provider: m['provider'] ?? '',
            description: m['description'] ?? '',
          ))
      .toList();
}

Future<TvShow?> tvShow(String id) async {
  final r = await get('/api/tv/show?id=${Uri.encodeComponent(id)}');
  if (r['ok'] != true) return null;
  final s = r['show'];
  if (s is! Map<String, dynamic>) return null;
  final eps = (s['episodes'] as List?) ?? const [];
  return TvShow(
    id: s['id'] ?? id,
    title: s['title'] ?? 'Untitled',
    poster: abs(s['poster'] ?? ''),
    tagline: s['tagline'] ?? '',
    description: s['description'] ?? '',
    kind: s['kind'] ?? 'series',
    provider: s['provider'] ?? '',
    episodes: eps
        .whereType<Map<String, dynamic>>()
        .map((e) => Episode(
              id: e['id'] ?? '',
              title: e['title'] ?? '',
              duration: e['duration'] ?? '',
              quality: e['quality'] ?? '',
              overview: e['overview'] ?? '',
            ))
        .toList(),
  );
}

class TvPlay {
  final List<Quality> qualities;
  final List<SubtitleTrack> subtitles;
  final bool embed;
  final List<Mirror> mirrors;
  TvPlay({required this.qualities, required this.subtitles, required this.embed, required this.mirrors});
}

Future<TvPlay?> tvQualities(String epId) async {
  final r = await get('/api/tv/qualities?ep=${Uri.encodeComponent(epId)}');
  if (r['ok'] != true) return null;
  final qs = ((r['qualities'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map((q) => Quality(label: q['label'] ?? '', m3u8: q['m3u8'] ?? ''))
      .toList();
  final subs = ((r['subtitles'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map((s) => SubtitleTrack(lang: s['lang'] ?? '', url: abs(s['url'] ?? '')))
      .toList();
  final mirrors = ((r['mirrors'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map((m) => Mirror(label: m['label'] ?? '', url: m['url'] ?? ''))
      .toList();
  return TvPlay(
    qualities: qs,
    subtitles: subs,
    embed: r['embed'] == true,
    mirrors: mirrors,
  );
}

String tvStreamUrl(String epId, [String? quality]) {
  final q = (quality != null && quality.isNotEmpty) ? '&q=${Uri.encodeComponent(quality)}' : '';
  return '$BASE/api/tv/stream?ep=${Uri.encodeComponent(epId)}$q';
}

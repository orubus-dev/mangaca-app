/* MANGACA sources.dart — the hidden extension layer, ported 1:1 from the web.
   Two lanes:
   • SERVER sources run on our edge (Mihon/LNReader-style adapters behind the
     merged /api/catalog): WeebCentral, MangaPill, Chikari, NovelBuddy, Gutenberg.
   • CLIENT sources run device-direct from the user's own connection:
     MangaDex (public API), plus MANGACA Originals from our own repo.
   Users never see source names — cards carry neutral kind labels only. */

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api.dart' as api;
import 'api.dart' show ApiException;
import 'models.dart';

class Source {
  final String id, kind, label;
  final bool server;
  final Future<List<BookItem>> Function(int page) popular;
  final Future<List<BookItem>> Function(int page) latest;
  final Future<List<BookItem>> Function(String q, int page) search;
  final Future<BookItem> Function(String bid, String fallbackCover) details;
  final Future<List<Chapter>> Function(String bid) chapters;
  final Future<List<String>> Function(String bid, String cid) pages;
  final Future<String> Function(String bid)? text;

  Source({
    required this.id,
    required this.kind,
    required this.label,
    required this.server,
    required this.popular,
    required this.latest,
    required this.search,
    required this.details,
    required this.chapters,
    required this.pages,
    this.text,
  });
}

/* ---------- server-backed source adapter ---------- */

class ServerDef {
  final String id, kind, label;
  const ServerDef(this.id, this.kind, this.label);
}

const serverDefs = [
  ServerDef('weebcentral', 'manga', 'MANGA'),
  ServerDef('mangapill', 'manga', 'MANGA'),
  ServerDef('chikari', 'novel', 'NOVELS'),
  ServerDef('novelbuddy', 'novel', 'NOVELS'),
  ServerDef('gutenberg', 'novel', 'CLASSICS'),
];

Future<List<BookItem>> _serverList(ServerDef def, String tab, int page) async {
  final r = await api.catalogBrowse(def.kind, tab, page).timeout(const Duration(seconds: 20));
  if (r['ok'] != true) return [];
  final items = (r['items'] as List?) ?? const [];
  return items
      .whereType<Map<String, dynamic>>()
      .where((it) => it['src'] == def.id)
      .map((it) => BookItem(
            sid: def.id,
            bid: (it['id'] ?? '').toString(),
            title: it['title'] ?? '',
            cover: it['cover'] != null && (it['cover'] as String).isNotEmpty
                ? api.bookCover(it['cover'])
                : '',
            src: def.label,
            kind: def.kind,
          ))
      .toList();
}

Future<List<BookItem>> _serverSearch(ServerDef def, String q, int page) async {
  final r = await api.catalogSearch(q, def.kind, page).timeout(const Duration(seconds: 20));
  if (r['ok'] != true) return [];
  final items = (r['items'] as List?) ?? const [];
  return items
      .whereType<Map<String, dynamic>>()
      .where((it) => it['src'] == def.id)
      .map((it) => BookItem(
            sid: def.id,
            bid: (it['id'] ?? '').toString(),
            title: it['title'] ?? '',
            cover: it['cover'] != null && (it['cover'] as String).isNotEmpty
                ? api.bookCover(it['cover'])
                : '',
            src: def.label,
            kind: def.kind,
          ))
      .toList();
}

Source serverSource(ServerDef def) => Source(
      id: def.id,
      kind: def.kind,
      label: def.label,
      server: true,
      popular: (p) => _serverList(def, 'popular', p),
      latest: (p) => _serverList(def, 'latest', p),
      search: (q, p) => _serverSearch(def, q, p),
      details: (bid, fallbackCover) async {
        final r = await api.catalogDetails(def.id, bid, cover: fallbackCover);
        if (r['ok'] != true) throw ApiException(r['message'] ?? 'details failed');
        return BookItem(
          sid: def.id,
          bid: bid,
          title: r['title'] ?? 'Untitled',
          author: r['author'] ?? '',
          cover: (r['cover'] ?? '') is String && (r['cover'] as String).isNotEmpty
              ? api.bookCover(r['cover'])
              : '',
          src: def.label,
          status: r['status'] ?? 'unknown',
          synopsis: r['description'] ?? '',
          kind: def.kind,
        );
      },
      chapters: (bid) async {
        final r = await api.catalogChapters(def.id, bid);
        if (r['ok'] != true) throw ApiException(r['message'] ?? 'chapters failed');
        final list = (r['chapters'] as List?) ?? const [];
        var i = 0;
        return list.whereType<Map<String, dynamic>>().map((c) {
          i += 1;
          return Chapter(
            cid: (c['id'] ?? '').toString(),
            title: (c['name'] ?? '') is String && (c['name'] as String).isNotEmpty
                ? c['name']
                : 'Chapter $i',
            number: i,
            date: ((c['date'] ?? '') as String).split('').length >= 10
                ? (c['date'] as String).substring(0, 10)
                : (c['date'] ?? ''),
          );
        }).toList();
      },
      pages: (bid, cid) async {
        final r = await api.catalogPages(def.id, cid);
        if (r['ok'] != true) throw ApiException(r['message'] ?? 'pages failed');
        return ((r['images'] as List?) ?? const []).map((e) => e.toString()).toList();
      },
      text: def.id == 'gutenberg' ? gutenbergText : null,
    );

/* ---------- MANGACA ORIGINALS ---------- */

Map<String, dynamic>? _catalogCache;

Future<Map<String, dynamic>> originalsCatalog() async {
  if (_catalogCache != null) return _catalogCache!;
  final r = await http
      .get(Uri.parse(api.abs('assets/catalog.json')))
      .timeout(const Duration(seconds: 15));
  _catalogCache = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  return _catalogCache!;
}

BookItem _originalsBook(Map<String, dynamic> b) => BookItem(
      sid: 'originals',
      bid: b['id'],
      title: b['title'],
      author: b['author'] ?? '',
      cover: api.abs(b['cover'] ?? ''),
      src: 'ORIGINALS',
      status: b['status'] ?? '',
      tags: List<String>.from(b['tags'] ?? const []),
      synopsis: b['synopsis'] ?? '',
      kind: 'manga',
    );

final originals = Source(
  id: 'originals',
  kind: 'manga',
  label: 'ORIGINALS',
  server: false,
  popular: (_) async =>
      ((await originalsCatalog())['books'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_originalsBook)
          .toList(),
  latest: (_) async =>
      ((await originalsCatalog())['books'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_originalsBook)
          .toList(),
  search: (q, _) async {
    final lq = q.toLowerCase();
    return ((await originalsCatalog())['books'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .where((b) =>
            ((b['title'] ?? '') + ' ' + ((b['tags'] ?? [])).join(' ') + ' ' + (b['synopsis'] ?? ''))
                .toLowerCase()
                .contains(lq))
        .map(_originalsBook)
        .toList();
  },
  details: (bid, _) async {
    final books = ((await originalsCatalog())['books'] as List? ?? const [])
        .whereType<Map<String, dynamic>>();
    for (final b in books) {
      if (b['id'] == bid) return _originalsBook(b);
    }
    throw ApiException('not found');
  },
  chapters: (bid) async {
    final books = ((await originalsCatalog())['books'] as List? ?? const [])
        .whereType<Map<String, dynamic>>();
    for (final b in books) {
      if (b['id'] == bid) {
        return ((b['chapters'] as List?) ?? const []).whereType<Map<String, dynamic>>().map((ch) {
          return Chapter(
            cid: ch['id'],
            number: ch['number'] ?? 0,
            title: ch['title'] ?? '',
            pages: ((ch['pages'] ?? 0) as num).toInt(),
            date: ch['released'] ?? '',
          );
        }).toList();
      }
    }
    throw ApiException('not found');
  },
  pages: (bid, cid) async {
    final books = ((await originalsCatalog())['books'] as List? ?? const [])
        .whereType<Map<String, dynamic>>();
    for (final b in books) {
      if (b['id'] != bid) continue;
      for (final ch in ((b['chapters'] as List?) ?? const []).whereType<Map<String, dynamic>>()) {
        if (ch['id'] != cid) continue;
        final dir = (ch['dir'] ?? '') as String;
        final ext = (ch['ext'] ?? 'jpg') as String;
        final total = ((ch['pages'] ?? 0) as num).toInt();
        return List.generate(total, (i) {
          final n = (i + 1).toString().padLeft(3, '0');
          return api.abs('$dir' 'p$n.$ext');
        });
      }
    }
    throw ApiException('chapter not found');
  },
);

/* ---------- MANGADEX (device-direct with a server-relay fallback) ----------
   Primary path: the user's own connection (fast, proven). If the device
   can't reach MangaDex at all (carrier DNS, aggressive filtering, CF
   challenge), every call automatically retries through OUR runtime's
   /api/proxy lane (api.mangadex.org is allowlisted there) — so the catalog
   can never come up empty just because one path failed. */

const _mdApi = 'https://api.mangadex.org';
const _mdLimit = 20;
const _mdRatings = '&contentRating[]=safe&contentRating[]=suggestive';

/* browser-like UA — some networks/CDNs treat exotic app UAs worse */
const mdUa =
    'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36 MANGACA/0.0.3';

Future<Map<String, dynamic>> _mdJson(String url) async {
  // path 1 — device-direct
  try {
    final r = await http
        .get(Uri.parse(url), headers: {'User-Agent': mdUa, 'Accept': 'application/json'})
        .timeout(const Duration(seconds: 12));
    if (r.statusCode == 200) {
      return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    }
  } catch (_) {}
  // path 2 — our runtime relay (same contract, server egress)
  final r2 = await http
      .get(Uri.parse(api.px(url)), headers: {'User-Agent': 'MANGACA/0.0.3 (Android)'})
      .timeout(const Duration(seconds: 20));
  if (r2.statusCode != 200) throw ApiException('mangadex ${r2.statusCode}');
  return jsonDecode(utf8.decode(r2.bodyBytes)) as Map<String, dynamic>;
}

String _mdCover(String mangaId, List<dynamic> rels) {
  for (final r in rels) {
    if (r is Map<String, dynamic> && r['type'] == 'cover_art') {
      final fn = ((r['attributes'] as Map<String, dynamic>?)?['fileName'] ?? '') as String;
      if (fn.isNotEmpty) return 'https://uploads.mangadex.org/covers/$mangaId/$fn.512.jpg';
    }
  }
  return '';
}

String _mdTitle(Map<String, dynamic> attrs) {
  final t = attrs['title'];
  if (t is Map<String, dynamic>) {
    if (t['en'] is String && (t['en'] as String).isNotEmpty) return t['en'];
    for (final v in t.values) {
      if (v is String && v.isNotEmpty) return v;
    }
  }
  return 'Untitled';
}

BookItem _mdItem(Map<String, dynamic> item) {
  final attrs = (item['attributes'] as Map<String, dynamic>?) ?? {};
  return BookItem(
    sid: 'mangadex',
    bid: item['id'],
    title: _mdTitle(attrs),
    cover: _mdCover(item['id'], (item['relationships'] as List?) ?? const []),
    src: 'MANGA',
    status: attrs['status'] ?? '',
    kind: 'manga',
  );
}



/* comics lane — MangaDex tag catalogs (same tags as web):
   Web Comic / 4-Koma / Anthology / Oneshot. */
const mdTagWebComic = 'e197df38-d0e7-43b5-9b09-2842d0c326dd';
const mdTag4Koma = 'b11fda93-8f1d-4bef-b2ed-8803d3733170';
const mdTagAnthology = '51d83883-4103-437c-b4b1-731cb73d786c';
const mdTagOneshot = '0234a31e-a729-4e28-9d6a-3f87c4966b9e';

Future<List<BookItem>> mdByTag(String tag, int page, {String label = 'COMICS'}) async {
  final p = page < 1 ? 1 : page;
  final j = await _mdJson(
      '$_mdApi/manga?limit=$_mdLimit&offset=${(p - 1) * _mdLimit}&includes[]=cover_art&includedTags[]=${Uri.encodeComponent(tag)}&includedTagsMode=AND&hasAvailableChapters=true&order[followedCount]=desc$_mdRatings');
  return ((j['data'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(_mdItem)
      .map((b) => BookItem(
            sid: b.sid,
            bid: b.bid,
            title: b.title,
            cover: b.cover,
            src: label,
            kind: 'comic',
            status: b.status,
          ))
      .toList();
}

/* origin lanes — JAPANESE manga / KOREAN manhwa / CHINESE manhua, all with
   English translations available (availableTranslatedLanguage[]=en).
   orderBy: followedCount = most-read, latestUploadedChapter = most current. */
Future<List<BookItem>> mdOriginal(String lang, int page,
    {String orderBy = 'followedCount', String label = 'MANGA'}) async {
  final p = page < 1 ? 1 : page;
  final orderKey = orderBy == 'current' ? 'latestUploadedChapter' : 'followedCount';
  final j = await _mdJson(
      '$_mdApi/manga?limit=$_mdLimit&offset=${(p - 1) * _mdLimit}&includes[]=cover_art'
      '&originalLanguage[]=${Uri.encodeComponent(lang)}'
      '&availableTranslatedLanguage[]=en'
      '&hasAvailableChapters=true&order[$orderKey]=desc$_mdRatings');
  return ((j['data'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(_mdItem)
      .map((b) => BookItem(
            sid: b.sid,
            bid: b.bid,
            title: b.title,
            cover: b.cover,
            src: label,
            kind: 'manga',
            status: b.status,
          ))
      .toList();
}

Future<List<BookItem>> comicPopular(int page) => mdByTag(mdTagWebComic, page);
Future<List<BookItem>> comicLatest(int page) async {
  final j = await _mdJson(
      '$_mdApi/manga?limit=$_mdLimit&offset=${(page - 1) * _mdLimit}&includes[]=cover_art&includedTags[]=${Uri.encodeComponent(mdTagWebComic)}&includedTagsMode=AND&hasAvailableChapters=true&order[latestUploadedChapter]=desc$_mdRatings');
  return ((j['data'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(_mdItem)
      .map((b) => BookItem(
            sid: b.sid,
            bid: b.bid,
            title: b.title,
            cover: b.cover,
            src: 'COMICS',
            kind: 'comic',
            status: b.status,
          ))
      .toList();
}

final mangadex = Source(
  id: 'mangadex',
  kind: 'manga',
  label: 'MANGA',
  server: false,
  popular: (page) async {
    final j = await _mdJson(
        '$_mdApi/manga?limit=$_mdLimit&offset=${(page - 1) * _mdLimit}&includes[]=cover_art&order[followedCount]=desc&hasAvailableChapters=true$_mdRatings');
    return ((j['data'] as List?) ?? const []).whereType<Map<String, dynamic>>().map(_mdItem).toList();
  },
  latest: (page) async {
    final j = await _mdJson(
        '$_mdApi/manga?limit=$_mdLimit&offset=${(page - 1) * _mdLimit}&includes[]=cover_art&order[latestUploadedChapter]=desc&hasAvailableChapters=true$_mdRatings');
    return ((j['data'] as List?) ?? const []).whereType<Map<String, dynamic>>().map(_mdItem).toList();
  },
  search: (q, page) async {
    final j = await _mdJson(
        '$_mdApi/manga?limit=$_mdLimit&offset=${(page - 1) * _mdLimit}&includes[]=cover_art&title=${Uri.encodeComponent(q)}&hasAvailableChapters=true$_mdRatings');
    return ((j['data'] as List?) ?? const []).whereType<Map<String, dynamic>>().map(_mdItem).toList();
  },
  details: (bid, _) async {
    final j = await _mdJson('$_mdApi/manga/$bid?includes[]=cover_art&includes[]=author&includes[]=artist');
    final m = (j['data'] as Map<String, dynamic>?) ?? {};
    final attrs = (m['attributes'] as Map<String, dynamic>?) ?? {};
    String author = '';
    for (final r in ((m['relationships'] as List?) ?? const [])) {
      if (r is Map<String, dynamic> && r['type'] == 'author') {
        author = (((r['attributes'] as Map<String, dynamic>?)?['name']) ?? '') as String;
        break;
      }
    }
    String desc = '';
    final d = attrs['description'];
    if (d is Map<String, dynamic>) {
      desc = (d['en'] ?? d.values.firstWhere((v) => v is String && v.isNotEmpty, orElse: () => '') ?? '') as String;
    }
    return BookItem(
      sid: 'mangadex',
      bid: bid,
      title: _mdTitle(attrs),
      author: author,
      cover: _mdCover(bid, (m['relationships'] as List?) ?? const []),
      src: 'MANGA',
      status: attrs['status'] ?? '',
      year: attrs['year'],
      tags: ((attrs['tags'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map((t) => (((t['attributes'] as Map<String, dynamic>?)?['name'] as Map<String, dynamic>?)?['en'] ?? '') as String)
          .where((s) => s.isNotEmpty)
          .take(8)
          .toList(),
      synopsis: desc,
      kind: 'manga',
    );
  },
  chapters: (bid) async {
    final j = await _mdJson(
        '$_mdApi/manga/$bid/feed?limit=500&order[chapter]=desc&translatedLanguage[]=en&includeEmptyPages=0$_mdRatings');
    return ((j['data'] as List?) ?? const []).whereType<Map<String, dynamic>>().map((ch) {
      final a = (ch['attributes'] as Map<String, dynamic>?) ?? {};
      final chNum = a['chapter'] is String ? num.tryParse(a['chapter'] as String) : (a['chapter'] as num?);
      return Chapter(
        cid: ch['id'] ?? '',
        number: chNum ?? 0,
        title: (a['title'] ?? '') is String && (a['title'] as String).isNotEmpty
            ? a['title']
            : (a['chapter'] != null ? 'Chapter ${a['chapter']}' : 'Oneshot'),
        pages: ((a['pages'] ?? 0) as num).toInt(),
        date: ((a['publishAt'] ?? '') as String).length >= 10
            ? (a['publishAt'] as String).substring(0, 10)
            : '',
      );
    }).toList();
  },
  pages: (bid, cid) async {
    final j = await _mdJson('$_mdApi/at-home/server/$cid');
    final base = (j['baseUrl'] ?? '') as String;
    final ch = (j['chapter'] as Map<String, dynamic>?) ?? {};
    if (base.isEmpty || ch.isEmpty) throw ApiException('no pages yet');
    final saver = ((ch['dataSaver'] as List?) ?? const []).whereType<String>().toList();
    final full = ((ch['data'] as List?) ?? const []).whereType<String>().toList();
    final files = saver.isNotEmpty ? saver : full;
    final seg = saver.isNotEmpty ? 'data-saver' : 'data';
    return files.map((f) => '$base/$seg/${ch['hash']}/$f').toList();
  },
);

/* ---------- GUTENBERG (classics — via the server catalog lane) ----------
   gutendex.com is bot-walled from every residential/datacenter path except
   our own edge's cached runtime lane, so popular/latest/search ride the
   server catalog (seed-backed) and text/covers load device-direct. */

String _gutTxt(String id) => 'https://www.gutenberg.org/cache/epub/$id/pg$id.txt';
String _gutCover(String id) =>
    'https://www.gutenberg.org/cache/epub/$id/pg$id.cover.medium.jpg';

const gutenbergSeed = [
  {'id': '1342', 'title': 'Pride and Prejudice', 'author': 'Jane Austen'},
  {'id': '84', 'title': 'Frankenstein', 'author': 'Mary Wollstonecraft Shelley'},
  {'id': '11', 'title': "Alice's Adventures in Wonderland", 'author': 'Lewis Carroll'},
  {'id': '2701', 'title': 'Moby Dick', 'author': 'Herman Melville'},
  {'id': '1661', 'title': 'The Adventures of Sherlock Holmes', 'author': 'A. Conan Doyle'},
  {'id': '98', 'title': 'A Tale of Two Cities', 'author': 'Charles Dickens'},
  {'id': '345', 'title': 'Dracula', 'author': 'Bram Stoker'},
  {'id': '174', 'title': 'The Picture of Dorian Gray', 'author': 'Oscar Wilde'},
  {'id': '76', 'title': 'Adventures of Huckleberry Finn', 'author': 'Mark Twain'},
  {'id': '2600', 'title': 'War and Peace', 'author': 'Leo Tolstoy'},
  {'id': '2554', 'title': 'Crime and Punishment', 'author': 'Fyodor Dostoevsky'},
  {'id': '1184', 'title': 'The Count of Monte Cristo', 'author': 'Alexandre Dumas'},
];

BookItem _gutSeedItem(Map<String, String> s) => BookItem(
      sid: 'gutenberg',
      bid: s['id']!,
      title: s['title']!,
      author: s['author']!,
      cover: api.bookCover(_gutCover(s['id']!)),
      src: 'CLASSICS',
      status: 'published',
      kind: 'book',
    );

/* public: the offline-safe classics list for UI fallbacks */
List<BookItem> gutenbergSeedItems() => gutenbergSeed.map(_gutSeedItem).toList();

Future<String> gutenbergText(String bid) async {
  final id = bid.toString();
  /* direct candidates only — the old gutendex formats probe added a
     guaranteed 25s timeout stall to every classic before its first word. */
  final candidates = <String>[
    _gutTxt(id),
    'https://www.gutenberg.org/files/$id/$id-0.txt',
    'https://www.gutenberg.org/files/$id/$id.txt',
    'https://www.gutenberg.org/cache/epub/$id/pg$id.txt.utf-8',
  ];
  for (final url in candidates) {
    try {
      final r = await http.get(Uri.parse(api.px(url))).timeout(const Duration(seconds: 30));
      if (r.statusCode != 200) continue;
      final raw = utf8.decode(r.bodyBytes, allowMalformed: true);
      if (raw.trimLeft().startsWith('<') || RegExp(r'<html[\s>]', caseSensitive: false).hasMatch(raw.substring(0, raw.length > 400 ? 400 : raw.length))) {
        continue;
      }
      return stripGutenbergBoilerplate(raw);
    } catch (_) {}
  }
  throw ApiException('no readable text available right now — try again in a minute');
}

String stripGutenbergBoilerplate(String raw) {
  final start = RegExp(r'\*\*\*\s*START OF (?:THE|THIS) PROJECT GUTENBERG EBOOK[^*]*\*\*\*', caseSensitive: false)
      .firstMatch(raw);
  final end = RegExp(r'\*\*\*\s*END OF (?:THE|THIS) PROJECT GUTENBERG EBOOK', caseSensitive: false)
      .firstMatch(raw);
  var body = raw;
  if (start != null) body = body.substring(start.end);
  if (end != null) body = body.substring(0, end.start);
  if (body.trim().length < 200) body = raw;
  return body.replaceAll('\r\n', '\n').trim();
}

/* classics list lane — server catalog (gutenberg kind = book), seed-backed */
Future<List<BookItem>> _gutLane(String tab, int page) async {
  try {
    final r = await api.catalogBrowse('book', tab, page).timeout(const Duration(seconds: 20));
    final items = (r['items'] as List?) ?? const [];
    final rows = items
        .whereType<Map<String, dynamic>>()
        .where((it) => it['src'] == 'gutenberg')
        .map((it) => BookItem(
              sid: 'gutenberg',
              bid: (it['id'] ?? '').toString(),
              title: it['title'] ?? '',
              cover: (it['cover'] ?? '') is String && (it['cover'] as String).isNotEmpty
                  ? api.bookCover(it['cover'])
                  : api.bookCover(_gutCover((it['id'] ?? '').toString())),
              src: 'CLASSICS',
              kind: 'book',
            ))
        .toList();
    if (rows.isNotEmpty) return rows;
  } catch (_) {}
  return gutenbergSeed.map(_gutSeedItem).toList();
}

final gutenberg = Source(
  id: 'gutenberg',
  kind: 'book',
  label: 'CLASSICS',
  server: false,
  popular: (page) => _gutLane('popular', page),
  latest: (page) => _gutLane('latest', page),
  search: (q, page) async {
    try {
      final r = await api.catalogSearch(q, 'book', page).timeout(const Duration(seconds: 20));
      final items = (r['items'] as List?) ?? const [];
      final rows = items
          .whereType<Map<String, dynamic>>()
          .where((it) => it['src'] == 'gutenberg')
          .map((it) => BookItem(
                sid: 'gutenberg',
                bid: (it['id'] ?? '').toString(),
                title: it['title'] ?? '',
                cover: (it['cover'] ?? '') is String && (it['cover'] as String).isNotEmpty
                    ? api.bookCover(it['cover'])
                    : api.bookCover(_gutCover((it['id'] ?? '').toString())),
                src: 'CLASSICS',
                kind: 'book',
              ))
          .toList();
      if (rows.isNotEmpty) return rows;
    } catch (_) {}
    final lq = q.toLowerCase();
    return gutenbergSeed
        .where((s) => ('${s['title']} ${s['author']}').toLowerCase().contains(lq))
        .map(_gutSeedItem)
        .toList();
  },
  details: (bid, _) async {
    try {
      final r = await api.catalogDetails('gutenberg', bid.toString()).timeout(const Duration(seconds: 20));
      if (r['ok'] == true) {
        return BookItem(
          sid: 'gutenberg',
          bid: bid.toString(),
          title: r['title'] ?? 'Untitled',
          author: r['author'] ?? 'Unknown',
          cover: (r['cover'] ?? '') is String && (r['cover'] as String).isNotEmpty
              ? api.bookCover(r['cover'])
              : api.bookCover(_gutCover(bid.toString())),
          src: 'CLASSICS',
          status: 'published',
          tags: (r['genres'] ?? '') is String && (r['genres'] as String).isNotEmpty
              ? (r['genres'] as String).split(',').take(6).map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
              : ['classic', 'public domain'],
          synopsis: (r['description'] ?? '') is String && (r['description'] as String).isNotEmpty
              ? r['description']
              : 'A public-domain classic, free to read in the iReader engine.',
          kind: 'book',
        );
      }
    } catch (_) {}
    final seeds = gutenbergSeed.where((s) => s['id'] == bid.toString()).toList();
    if (seeds.isEmpty) throw ApiException('book not found');
    final s = seeds.first;
    return BookItem(
      sid: 'gutenberg',
      bid: s['id']!,
      title: s['title']!,
      author: s['author']!,
      cover: api.bookCover(_gutCover(s['id']!)),
      src: 'CLASSICS',
      status: 'published',
      tags: ['classic', 'public domain'],
      synopsis: 'A public-domain classic, free to read in the iReader engine.',
      kind: 'book',
    );
  },
  chapters: (_) async => [Chapter(cid: 'full', number: 1, title: 'Full text', pages: 0)],
  pages: (_, __) async => const [],
  text: (bid) => gutenbergText(bid),
);

/* ---------- registry + merged lanes ---------- */

final List<Source> sources = [
  originals,
  mangadex,
  ...serverDefs.map(serverSource),
];

Source? sourceById(String sid) {
  for (final s in sources) {
    if (s.id == sid) return s;
  }
  return null;
}

List<BookItem> _interleave(List<List<BookItem>> lists) {
  final out = <BookItem>[];
  final max = lists.fold<int>(0, (m, l) => l.length > m ? l.length : m);
  for (var i = 0; i < max; i++) {
    for (final l in lists) {
      if (i < l.length) out.add(l[i]);
    }
  }
  return out;
}

Future<List<BookItem>> _catalogLane(String kind, String tab, int page) async {
  final r = await api.catalogBrowse(kind, tab, page).timeout(const Duration(seconds: 20));
  if (r['ok'] != true) return [];
  return ((r['items'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map((it) {
        String? labelDef;
        for (final d in serverDefs) {
          if (d.id == it['src']) labelDef = d.label;
        }
        final label = (it['kind'] == 'book') ? 'CLASSICS' : (labelDef ?? 'NOVELS');
        return BookItem(
          sid: (it['src'] ?? '').toString(),
          bid: (it['id'] ?? '').toString(),
          title: it['title'] ?? '',
          cover: it['cover'] != null && (it['cover'] as String).isNotEmpty
              ? api.bookCover(it['cover'])
              : '',
          src: label,
          kind: (it['kind'] ?? kind).toString(),
        );
      })
      .toList();
}

/* gutendex topic rails (novels & classics) — server lane, seed-free.
   Returns books with the caller's kind so cards label correctly. */
Future<List<BookItem>> topicLane(String topic, String kind, int page) async {
  final r = await api.catalogTopic(topic, page).timeout(const Duration(seconds: 20));
  final items = (r['items'] as List?) ?? const [];
  return items
      .whereType<Map<String, dynamic>>()
      .map((it) => BookItem(
            sid: (it['src'] ?? 'gutenberg').toString(),
            bid: (it['id'] ?? '').toString(),
            title: it['title'] ?? '',
            cover: (it['cover'] ?? '') is String && (it['cover'] as String).isNotEmpty
                ? api.bookCover(it['cover'])
                : '',
            src: kind == 'book' ? 'CLASSICS' : 'NOVELS',
            kind: kind,
          ))
      .toList();
}

/* AniList genre discovery (device-direct, bot-friendly) — feeds the manga
   genre rails. Items are discovery cards: tapping resolves the title into a
   readable source via global title search. */
Future<List<BookItem>> anilistGenre(String genre) async {
  const q = r'query($g:[String]){Page(page:1,perPage:14){media(sort:TRENDING_DESC,genre_in:$g,type:MANGA){title{english romaji}coverImage{large}}}}';
  final r = await http
      .post(
        Uri.parse('https://graphql.anilist.co'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'query': q, 'variables': {'g': [genre]}}),
      )
      .timeout(const Duration(seconds: 12));
  if (r.statusCode != 200) throw ApiException('anilist ${r.statusCode}');
  final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  final page = (j['data'] as Map<String, dynamic>?)?['Page'] as Map<String, dynamic>?;
  final media = (page?['media'] as List?) ?? const [];
  return media
      .whereType<Map<String, dynamic>>()
      .map((m) {
        final t = (m['title'] as Map<String, dynamic>?) ?? {};
        final title = ((t['english'] ?? t['romaji'] ?? '') as String).trim();
        final cov = ((m['coverImage'] as Map<String, dynamic>?)?['large'] ?? '') as String;
        return BookItem(sid: 'disco', bid: '', title: title, cover: cov, src: 'MANGA', kind: 'manga');
      })
      .where((b) => b.title.isNotEmpty)
      .toList();
}

/* AniList origin discovery — countryOfOrigin lanes (JP manga / KR manhwa /
   CN manhua). Bot-friendly and fast; used as the fallback when MangaDex
   can't answer, and as the discovery rail for CURRENT titles. Items are
   discovery cards (sid 'disco') that resolve into a readable source on tap. */
Future<List<BookItem>> anilistCountry(String country, {int perPage = 14}) async {
  final q =
      'query(\$c:String){Page(page:1,perPage:$perPage){media(sort:TRENDING_DESC,countryOfOrigin:\$c,type:MANGA,isAdult:false){title{english romaji}coverImage{large}}}}';
  final r = await http
      .post(
        Uri.parse('https://graphql.anilist.co'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'query': q, 'variables': {'c': country}}),
      )
      .timeout(const Duration(seconds: 12));
  if (r.statusCode != 200) throw ApiException('anilist ${r.statusCode}');
  final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  final page = (j['data'] as Map<String, dynamic>?)?['Page'] as Map<String, dynamic>?;
  final media = (page?['media'] as List?) ?? const [];
  return media
      .whereType<Map<String, dynamic>>()
      .map((m) {
        final t = (m['title'] as Map<String, dynamic>?) ?? {};
        final title = ((t['english'] ?? t['romaji'] ?? '') as String).trim();
        final cov = ((m['coverImage'] as Map<String, dynamic>?)?['large'] ?? '') as String;
        return BookItem(sid: 'disco', bid: '', title: title, cover: cov, src: 'MANGA', kind: 'manga');
      })
      .where((b) => b.title.isNotEmpty)
      .toList();
}

/* AniList tag discovery — powers the comics fallback (4-koma tag etc.) */
Future<List<BookItem>> anilistTag(String tag, {int perPage = 14}) async {
  final q =
      'query(\$t:String){Page(page:1,perPage:$perPage){media(sort:TRENDING_DESC,tag:\$t,type:MANGA,isAdult:false){title{english romaji}coverImage{large}}}}';
  final r = await http
      .post(
        Uri.parse('https://graphql.anilist.co'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'query': q, 'variables': {'t': tag}}),
      )
      .timeout(const Duration(seconds: 12));
  if (r.statusCode != 200) throw ApiException('anilist ${r.statusCode}');
  final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  final page = (j['data'] as Map<String, dynamic>?)?['Page'] as Map<String, dynamic>?;
  final media = (page?['media'] as List?) ?? const [];
  return media
      .whereType<Map<String, dynamic>>()
      .map((m) {
        final t = (m['title'] as Map<String, dynamic>?) ?? {};
        final title = ((t['english'] ?? t['romaji'] ?? '') as String).trim();
        final cov = ((m['coverImage'] as Map<String, dynamic>?)?['large'] ?? '') as String;
        return BookItem(sid: 'disco', bid: '', title: title, cover: cov, src: 'COMICS', kind: 'comic');
      })
      .where((b) => b.title.isNotEmpty)
      .toList();
}

Future<List<BookItem>> mergedPopular(int page) async {
  final server = _catalogLane('manga', 'popular', page).catchError((_) => <BookItem>[]);
  final client = mangadex.popular(page).catchError((_) => <BookItem>[]);
  return _interleave([await server, await client]);
}

Future<List<BookItem>> mergedLatest(int page) async {
  final server = _catalogLane('manga', 'latest', page).catchError((_) => <BookItem>[]);
  final client = mangadex.latest(page).catchError((_) => <BookItem>[]);
  return _interleave([await server, await client]);
}

Future<List<BookItem>> globalSearch(String q, int page) async {
  final jobs = <Future<List<BookItem>>>[];
  for (final def in serverDefs) {
    jobs.add(_serverSearch(def, q, page).catchError((_) => <BookItem>[]));
  }
  jobs.add(mangadex.search(q, page).catchError((_) => <BookItem>[]));
  final lists = await Future.wait(jobs);
  return _interleave(lists);
}

/* ---------- trending (For You rail) ---------- */

class TrendItem {
  final String title, cover, sub, match;
  TrendItem({required this.title, required this.cover, required this.sub, required this.match});
}

Future<List<TrendItem>> trending() async {
  try {
    final r = await http
        .get(Uri.parse('https://api.jikan.moe/v4/top/manga?limit=14&filter=bypopularity'))
        .timeout(const Duration(seconds: 8));
    if (r.statusCode == 200) {
      final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
      final rows = <TrendItem>[];
      for (final m in ((j['data'] as List?) ?? const [])) {
        if (m is! Map<String, dynamic>) continue;
        final imgs = ((m['images'] as Map<String, dynamic>?)?['jpg'] as Map<String, dynamic>?);
        if (imgs == null) continue;
        final title = ((m['title_english'] ?? m['title'] ?? '') as String).trim();
        rows.add(TrendItem(
          title: title,
          cover: (imgs['large_image_url'] ?? imgs['image_url'] ?? '') as String,
          sub: (((m['genres'] as List?) ?? const []).isNotEmpty
              ? (((m['genres'] as List).first as Map<String, dynamic>)['name'] ?? '')
              : '') as String,
          match: title,
        ));
      }
      if (rows.isNotEmpty) return rows;
    }
  } catch (_) {}
  // fallback: MangaDex popular
  try {
    final items = await mangadex.popular(1).timeout(const Duration(seconds: 12));
    return items.take(14).map((b) => TrendItem(title: b.title, cover: b.cover, sub: 'MANGA', match: b.title)).toList();
  } catch (_) {}
  return [
    TrendItem(
      title: 'Guarding the River of Time',
      cover: api.abs('assets/grott/ch01/cover.jpg'),
      sub: 'MANGACA ORIGINAL',
      match: 'Guarding the River of Time',
    ),
  ];
}

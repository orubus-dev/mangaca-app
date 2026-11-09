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
  final r = await api.catalogBrowse(def.kind, tab, page);
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
                ? api.imgx(it['cover'])
                : '',
            src: def.label,
            kind: def.kind,
          ))
      .toList();
}

Future<List<BookItem>> _serverSearch(ServerDef def, String q, int page) async {
  final r = await api.catalogSearch(q, def.kind, page);
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
                ? api.imgx(it['cover'])
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
              ? api.imgx(r['cover'])
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
  final r = await http.get(Uri.parse(api.abs('assets/catalog.json')));
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

/* ---------- MANGADEX (device-direct on purpose — same as the web) ---------- */

const _mdApi = 'https://api.mangadex.org';
const _mdLimit = 20;
const _mdRatings = '&contentRating[]=safe&contentRating[]=suggestive';

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

Future<Map<String, dynamic>> _mdJson(String url) async {
  final r = await http.get(Uri.parse(url), headers: {'User-Agent': 'MANGACA/0.0.1 (Android)'});
  if (r.statusCode != 200) throw ApiException('mangadex ${r.statusCode}');
  return jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
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
        '$_mdApi/manga?limit=$_mdLimit&offset=${(page - 1) * _mdLimit}&includes[]=cover_art&order[latestUploaded]=desc&hasAvailableChapters=true$_mdRatings');
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

/* ---------- GUTENBERG (via the runtime proxy — same as web) ---------- */

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

BookItem _gutItem(dynamic b) {
  final m = b as Map<String, dynamic>;
  final formats = (m['formats'] as Map<String, dynamic>?) ?? {};
  final cov = formats['image/jpeg'] ?? '';
  return BookItem(
    sid: 'gutenberg',
    bid: (m['id'] ?? '').toString(),
    title: m['title'] ?? '',
    author: ((m['authors'] as List?) ?? const []).isNotEmpty
        ? (((m['authors'] as List).first as Map<String, dynamic>)['name'] ?? 'Unknown') as String
        : 'Unknown',
    cover: cov is String && cov.isNotEmpty ? api.px(cov) : api.px(_gutCover((m['id'] ?? '').toString())),
    src: 'NOVELS',
    status: 'published',
    kind: 'novel',
  );
}

BookItem _gutSeedItem(Map<String, String> s) => BookItem(
      sid: 'gutenberg',
      bid: s['id']!,
      title: s['title']!,
      author: s['author']!,
      cover: api.px(_gutCover(s['id']!)),
      src: 'NOVELS',
      status: 'published',
      kind: 'novel',
    );

Future<List<dynamic>> _tryGutendex(String qs) async {
  final r = await http.get(Uri.parse(api.px('https://gutendex.com/books$qs')));
  if (r.statusCode != 200) throw ApiException('gutendex ${r.statusCode}');
  final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
  final results = (j['results'] as List?) ?? const [];
  if (results.isEmpty) throw ApiException('empty');
  return results;
}

Future<String> gutenbergText(String bid) async {
  final id = bid.toString();
  final candidates = <String>[];
  try {
    final rows = await _tryGutendex('?ids=$id');
    if (rows.isNotEmpty) {
      final b = rows.first as Map<String, dynamic>;
      final formats = (b['formats'] as Map<String, dynamic>?) ?? {};
      String? u;
      for (final key in formats.keys) {
        if (key.startsWith('text/plain')) {
          final v = formats[key];
          if (v is String && v.isNotEmpty) {
            u = v;
            break;
          }
        }
      }
      if (u != null) candidates.add(u);
    }
  } catch (_) {}
  candidates.add(_gutTxt(id));
  candidates.add('https://www.gutenberg.org/files/$id/$id-0.txt');
  candidates.add('https://www.gutenberg.org/files/$id/$id.txt');
  for (final url in candidates) {
    try {
      final r = await http.get(Uri.parse(api.px(url))).timeout(const Duration(seconds: 45));
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

final gutenberg = Source(
  id: 'gutenberg',
  kind: 'novel',
  label: 'CLASSICS',
  server: false,
  popular: (page) async {
    try {
      return (await _tryGutendex('?sort=downloads&page=${page.clamp(1, 99)}'))
          .map(_gutItem)
          .toList();
    } catch (_) {
      return gutenbergSeed.map(_gutSeedItem).toList();
    }
  },
  latest: (page) async {
    try {
      return (await _tryGutendex('?sort=descending&page=${page.clamp(1, 99)}'))
          .map(_gutItem)
          .toList();
    } catch (_) {
      return gutenbergSeed.map(_gutSeedItem).toList().reversed.toList();
    }
  },
  search: (q, page) async {
    try {
      return (await _tryGutendex('?search=${Uri.encodeComponent(q)}&page=${page.clamp(1, 99)}'))
          .map(_gutItem)
          .toList();
    } catch (_) {
      final lq = q.toLowerCase();
      return gutenbergSeed
          .where((s) => ('${s['title']} ${s['author']}').toLowerCase().contains(lq))
          .map(_gutSeedItem)
          .toList();
    }
  },
  details: (bid, _) async {
    try {
      final rows = await _tryGutendex('?ids=$bid');
      final b = rows.first as Map<String, dynamic>;
      final formats = (b['formats'] as Map<String, dynamic>?) ?? {};
      final cov = formats['image/jpeg'] ?? '';
      final authors = (b['authors'] as List?) ?? const [];
      String year = '';
      if (authors.isNotEmpty) {
        final by = ((authors.first as Map<String, dynamic>)['birth_year'] ?? '').toString();
        if (by != 'null' && by.isNotEmpty) year = by;
      }
      return BookItem(
        sid: 'gutenberg',
        bid: bid.toString(),
        title: b['title'] ?? '',
        author: authors.isNotEmpty
            ? (((authors.first as Map<String, dynamic>)['name'] ?? 'Unknown') as String)
            : 'Unknown',
        cover: cov is String && cov.isNotEmpty ? api.px(cov) : api.px(_gutCover(bid)),
        src: 'NOVELS',
        status: 'published',
        year: year,
        tags: ((b['subjects'] as List?) ?? const [])
            .map((s) => (s as String).split(' -- ').first)
            .take(6)
            .toList(),
        synopsis: ((b['summaries'] as List?) ?? const []).isNotEmpty
            ? (b['summaries'] as List).first as String
            : 'A public-domain classic, free to read in the iReader engine.',
        kind: 'novel',
      );
    } catch (_) {
      final seeds = gutenbergSeed.where((s) => s['id'] == bid.toString()).toList();
      if (seeds.isEmpty) throw ApiException('book not found');
      final s = seeds.first;
      return BookItem(
        sid: 'gutenberg',
        bid: s['id']!,
        title: s['title']!,
        author: s['author']!,
        cover: api.px(_gutCover(s['id']!)),
        src: 'NOVELS',
        status: 'published',
        tags: ['classic', 'public domain'],
        synopsis: 'A public-domain classic, free to read in the iReader engine.',
        kind: 'novel',
      );
    }
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
  final r = await api.catalogBrowse(kind, tab, page);
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
              ? api.imgx(it['cover'])
              : '',
          src: label,
          kind: (it['kind'] ?? kind).toString(),
        );
      })
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
    final items = await mangadex.popular(1);
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

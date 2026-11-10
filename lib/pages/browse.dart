/* MANGACA browse — the home tab. Top-bar section tabs (FOR YOU / POPULAR /
   LATEST / TV), kind chips (MANGA / COMICS / NOVELS / CLASSICS), For-You
   feed with hero + rails, infinite popular/latest grids.

   Boot hardening: the feed renders INSTANTLY, every section loads on its own
   with a hard timeout, and a failed section shows a one-tap RETRY row —
   a slow network can never leave the app on an empty loading screen. */

import 'dart:async';

import 'package:flutter/material.dart';
import '../api.dart' as api;
import '../models.dart';
import '../sources.dart';
import '../store.dart';
import '../widgets.dart';
import 'details.dart';

class BrowsePage extends StatefulWidget {
  final String section;
  final ValueChanged<String> onSection;
  const BrowsePage({super.key, required this.section, required this.onSection});
  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  String kind = 'manga'; // manga | comic | novel | book

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        HomeTabs(section: widget.section, onSection: widget.onSection),
        Expanded(
          child: widget.section == 'foryou'
              ? ForYouFeed(kind: kind, onKind: (k) => setState(() => kind = k))
              : FeedGrid(
                  tab: widget.section,
                  kind: kind,
                  onKind: (k) => setState(() => kind = k),
                ),
        ),
      ],
    );
  }
}

/* the shared top tab row — Browse and TV sit on the same rail */
class HomeTabs extends StatelessWidget {
  final String section;
  final ValueChanged<String> onSection;
  const HomeTabs({super.key, required this.section, required this.onSection});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget tab(String id, String label) {
      final active = section == id;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSection(id),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Text(label,
                  style: tUi(11.5, w: FontWeight.w700)
                      .copyWith(color: active ? p.fg : p.faint, letterSpacing: 0.6)),
              const SizedBox(height: 8),
              Container(
                height: 2.5,
                decoration: BoxDecoration(
                  gradient: active ? const LinearGradient(colors: kRainbow) : null,
                  color: active ? null : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(color: p.bg, border: Border(bottom: BorderSide(color: p.line))),
      child: Row(
        children: [
          tab('foryou', 'FOR YOU'),
          tab('popular', 'POPULAR'),
          tab('latest', 'LATEST'),
          tab('tv', 'TV'),
        ],
      ),
    );
  }
}

/* ---------- kind chips ---------- */
class KindChips extends StatelessWidget {
  final String kind;
  final ValueChanged<String> onKind;
  const KindChips({super.key, required this.kind, required this.onKind});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 2),
      child: Row(
        children: [
          Expanded(child: MChip('MANGA', on: kind == 'manga', onTap: () => onKind('manga'))),
          const SizedBox(width: 8),
          Expanded(child: MChip('COMICS', on: kind == 'comic', onTap: () => onKind('comic'))),
          const SizedBox(width: 8),
          Expanded(child: MChip('NOVELS', on: kind == 'novel', onTap: () => onKind('novel'))),
          const SizedBox(width: 8),
          Expanded(child: MChip('CLASSICS', on: kind == 'book', onTap: () => onKind('book'))),
        ],
      ),
    );
  }
}

/* ---------- resilient rail section ----------
   A row that loads itself with a hard timeout and owns its failure state. */
class RailSection extends StatefulWidget {
  final String title;
  final Future<List<RailCardData>> Function() loader;
  const RailSection({super.key, required this.title, required this.loader});
  @override
  State<RailSection> createState() => _RailSectionState();
}

class RailCardData {
  final String cover, title, sub;
  final VoidCallback onTap;
  final String? chip;
  RailCardData({required this.cover, required this.title, required this.sub, required this.onTap, this.chip});
}

class _RailSectionState extends State<RailSection> {
  List<RailCardData>? rows;
  bool failed = false;
  int attempt = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      rows = null;
      failed = false;
    });
    try {
      final r = await widget.loader().timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() => rows = r);
    } catch (_) {
      if (!mounted) return;
      setState(() => failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle('${widget.title}${attempt > 0 ? '  (retry ${attempt})' : ''}'),
        if (rows == null && !failed)
          SizedBox(
            height: 158,
            child: Row(
              children: [
                _railSkeleton(),
                const SizedBox(width: 10),
                _railSkeleton(),
                const SizedBox(width: 10),
                _railSkeleton(),
              ],
            ),
          )
        else if (failed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: GestureDetector(
              onTap: () {
                attempt += 1;
                _load();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  border: Border.all(color: p.lineHard),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text('COULDN\'T LOAD — TAP TO RETRY',
                    style: tMono(10, w: FontWeight.w700).copyWith(color: p.dim, letterSpacing: 0.6)),
              ),
            ),
          )
        else if (rows!.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text('nothing here right now — check back soon',
                style: tMono(10).copyWith(color: p.faint)),
          )
        else
          Rail(
            children: rows!
                .map((r) => RailCard(
                      cover: r.cover,
                      title: r.title,
                      sub: r.sub,
                      chip: r.chip,
                      onTap: r.onTap,
                    ))
                .toList(),
          ),
      ],
    );
  }

  Widget _railSkeleton() {
    final p = context.pal;
    return Container(
      width: 110,
      height: 158,
      decoration: BoxDecoration(
        color: p.bg2,
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Center(child: SpinBadge()),
    );
  }
}

/* ---------- For You ---------- */
class ForYouFeed extends StatefulWidget {
  final String kind;
  final ValueChanged<String> onKind;
  const ForYouFeed({super.key, required this.kind, required this.onKind});
  @override
  State<ForYouFeed> createState() => _ForYouFeedState();
}

class _ForYouFeedState extends State<ForYouFeed> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  BookItem? _hero;
  List<MapEntry<String, ProgressEntry>> _resume = [];

  @override
  void initState() {
    super.initState();
    _loadResume();
    _loadHero();
  }

  @override
  void didUpdateWidget(covariant ForYouFeed old) {
    super.didUpdateWidget(old);
    // kind changes only affect the kind-scoped children (they rebuild via keys)
  }

  void _loadResume() {
    final resume = <MapEntry<String, ProgressEntry>>[];
    for (final entry in Store.progress.entries) {
      final parts = entry.key.split(':');
      if (parts.length < 2) continue;
      final inLib = Store.history.any((h) => h.sid == parts[0] && h.bid == parts[1]) ||
          Store.library.any((b) => b['sid'] == parts[0] && b['bid'] == parts[1]);
      if (inLib) resume.add(MapEntry(entry.key, entry.value));
    }
    resume.sort((a, b) => b.value.at.compareTo(a.value.at));
    if (mounted) setState(() => _resume = resume);
  }

  Future<void> _loadHero() async {
    try {
      final orig = sourceById('originals')!;
      final books = await orig.popular(1).timeout(const Duration(seconds: 12));
      if (!mounted) return;
      setState(() => _hero = books.isNotEmpty ? books.first : null);
    } catch (_) {
      // hero is decoration — a hung originals lane never blocks the feed
      if (mounted) setState(() => _hero = null);
    }
  }

  void _openBook(BookItem b) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DetailsPage(sid: b.sid, bid: b.bid, coverHint: b.cover),
    ));
  }

  void _openTrend(RailCardData t) async {
    toast(context, 'Finding "${t.title}"…');
    try {
      final res = await globalSearch(t.title, 1).timeout(const Duration(seconds: 15));
      if (res.isEmpty) {
        if (mounted) toast(context, 'No readable source carries this yet', err: true);
        return;
      }
      if (mounted) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => DetailsPage(sid: res.first.sid, bid: res.first.bid, coverHint: res.first.cover),
        ));
      }
    } catch (_) {
      if (mounted) toast(context, 'Could not open', err: true);
    }
  }

  void _resumeOpen(String key, ProgressEntry prog) {
    final parts = key.split(':');
    if (parts.length < 2) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DetailsPage(sid: parts[0], bid: parts.sublist(1).join(':'), coverHint: '', startCid: prog.cid),
    ));
  }

  RailCardData trendCard(TrendItem t) => RailCardData(
        cover: t.cover, title: t.title, sub: t.sub, onTap: () => _openTrend(t));

  RailCardData bookCardData(BookItem b, {String? sub}) => RailCardData(
        cover: b.cover, title: b.title, sub: sub ?? b.author, onTap: () => _openBook(b));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = context.pal;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
      children: [
        KindChips(kind: widget.kind, onKind: widget.onKind),
        const SizedBox(height: 8),
        _heroBanner(_hero),
        if (_resume.isNotEmpty) ...[
          const SectionTitle('CONTINUE READING'),
          Rail(
            children: _resume.take(10).map((e) {
              final parts = e.key.split(':');
              final sid = parts[0];
              final bid = parts.sublist(1).join(':');
              String title = '';
              String cover = '';
              final h = Store.history.where((h) => h.sid == sid && h.bid == bid).firstOrNull;
              if (h != null) {
                title = h.title;
                cover = h.cover;
              } else {
                final b = Store.library.where((b) => b['sid'] == sid && b['bid'] == bid).firstOrNull;
                if (b != null) {
                  title = (b['title'] ?? '') as String;
                  cover = (b['cover'] ?? '') as String;
                }
              }
              return RailCard(
                cover: cover,
                title: title,
                sub: e.value.ctitle,
                chip: 'P.${e.value.page}${e.value.total > 0 ? '/${e.value.total}' : ''}',
                onTap: () => _resumeOpen(e.key, e.value),
              );
            }).toList(),
          ),
        ],
        RailSection(
          key: ValueKey('trend'),
          title: 'TRENDING NOW',
          loader: () async => (await trending()).map(trendCard).toList(),
        ),

        /* kind rails + popular grid */
        ..._kindRails(),
        _PopularGrid(key: ValueKey('grid-${widget.kind}'), kind: widget.kind, onOpen: _openBook),
        const SizedBox(height: 10),
        Text('Every row loads on its own — if one comes up empty, tap retry.',
            style: tUi(10).copyWith(color: p.faint)),
      ],
    );
  }

  List<Widget> _kindRails() {
    switch (widget.kind) {
      case 'manga':
        return [
          _mdTagRail('e197df38-d0e7-43b5-9b09-2842d0c326dd', 'WEB MANGA', 'MANGA'),
          _mdGenreRail('Action', 'ACTION MANGA'),
          _mdGenreRail('Romance', 'ROMANCE MANGA'),
        ];
      case 'comic':
        return [
          _mdTagRail(mdTag4Koma, '4-KOMA COMICS', 'COMICS'),
          _mdTagRail(mdTagAnthology, 'ANTHOLOGY COMICS', 'COMICS'),
          _mdTagRail(mdTagOneshot, 'ONESHOTS', 'COMICS'),
        ];
      case 'novel':
        return [
          _topicRail('mystery', 'MYSTERY NOVELS', 'novel'),
          _topicRail('adventure', 'ADVENTURE NOVELS', 'novel'),
          _topicRail('romance', 'ROMANCE NOVELS', 'novel'),
          _topicRail('fantasy', 'FANTASY NOVELS', 'novel'),
        ];
      case 'book':
      default:
        return [
          _topicRail('adventure', 'ADVENTURE CLASSICS', 'book'),
          _topicRail('gothic', 'GOTHIC CLASSICS', 'book'),
          _topicRail('mystery', 'MYSTERY CLASSICS', 'book'),
          _topicRail('science fiction', 'EARLY SCIENCE FICTION', 'book'),
        ];
    }
  }

  RailSection _mdTagRail(String tag, String title, String label) {
    return RailSection(
      key: ValueKey('$title-${widget.kind}'),
      title: title,
      loader: () async {
        List<BookItem> rows = [];
        try {
          rows = await mdByTag(tag, 1, label: label);
        } catch (_) {}
        return rows
            .take(12)
            .map((b) => RailCardData(
                  cover: b.cover,
                  title: b.title,
                  sub: b.status.toUpperCase(),
                  onTap: () => _openBook(b),
                ))
            .toList();
      },
    );
  }

  /* AniList genre discovery — resolves into a readable source on tap */
  RailSection _mdGenreRail(String genre, String title) {
    return RailSection(
      key: ValueKey('$title-${widget.kind}'),
      title: title,
      loader: () async {
        List<BookItem> rows = [];
        try {
          rows = await anilistGenre(genre);
        } catch (_) {}
        return rows
            .take(12)
            .map((b) => RailCardData(
                  cover: b.cover,
                  title: b.title,
                  sub: 'TAP TO FIND A SOURCE',
                  onTap: () => _openTrend(RailCardData(cover: b.cover, title: b.title, sub: '', onTap: () {})),
                ))
            .toList();
      },
    );
  }

  RailSection _topicRail(String topic, String title, String kind) {
    return RailSection(
      key: ValueKey('$title-${widget.kind}'),
      title: title,
      loader: () async => (await topicLane(topic, kind, 1))
          .take(12)
          .map((b) => RailCardData(
                cover: b.cover,
                title: b.title,
                sub: kind == 'book' ? 'CLASSIC' : 'NOVEL',
                onTap: () => _openBook(b),
              ))
          .toList(),
    );
  }

  Widget _heroBanner(BookItem? hero) {
    final p = context.pal;
    if (hero == null) {
      return Container(
        height: 118,
        margin: const EdgeInsets.only(bottom: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: p.bg2,
          border: Border.all(color: p.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('READ BEYOND THE ILLUSION', style: tDisplay(13).copyWith(color: p.fg, letterSpacing: 1.5)),
            const SizedBox(height: 4),
            Text('manga · comics · novels · classics · TV',
                style: tUi(10.5).copyWith(color: p.faint)),
          ],
        ),
      );
    }
    return GestureDetector(
      onTap: () => _openBook(hero),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 168,
          child: Stack(
            fit: StackFit.expand,
            children: [
              LetterCover(title: hero.title),
              if (hero.cover.isNotEmpty)
                Image.network(hero.cover,
                    fit: BoxFit.cover,
                    headers: const {'User-Agent': 'MANGACA/0.0.2 (Android)'},
                    errorBuilder: (_, __, ___) => const SizedBox()),
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Color(0xD9000000)],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: kRainbow),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('MANGACA ORIGINAL · FULL COLOR',
                            style: tMono(8.5, w: FontWeight.w700).copyWith(color: Colors.black)),
                      ),
                      const SizedBox(height: 6),
                      Text(hero.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tDisplay(17).copyWith(color: Colors.white)),
                      if (hero.author.isNotEmpty)
                        Text(hero.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tUi(11).copyWith(color: Colors.white70)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------- popular grid (kind-scoped, infinite when the setting is on) ---------- */
class _PopularGrid extends StatefulWidget {
  final String kind;
  final void Function(BookItem) onOpen;
  const _PopularGrid({super.key, required this.kind, required this.onOpen});
  @override
  State<_PopularGrid> createState() => _PopularGridState();
}

class _PopularGridState extends State<_PopularGrid> {
  List<BookItem> rows = [];
  bool loading = true;
  bool failed = false;
  int attempt = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      List<BookItem> r = [];
      switch (widget.kind) {
        case 'manga':
          r = await mergedPopular(1).timeout(const Duration(seconds: 18));
          break;
        case 'comic':
          r = await comicPopular(1).timeout(const Duration(seconds: 18));
          break;
        case 'novel':
          r = await _catalogLaneSafe('novel');
          break;
        case 'book':
        default:
          r = await _gutLaneSafe();
          break;
      }
      if (!mounted) return;
      setState(() {
        rows = r.take(30).toList();
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        failed = true;
        loading = false;
      });
    }
  }

  Future<List<BookItem>> _catalogLaneSafe(String kind) async {
    final r = await api.catalogBrowse(kind, 'popular', 1).timeout(const Duration(seconds: 18));
    final items = (r['items'] as List?) ?? const [];
    return items.whereType<Map<String, dynamic>>().map((it) {
      final isBook = it['kind'] == 'book';
      return BookItem(
        sid: (it['src'] ?? '').toString(),
        bid: (it['id'] ?? '').toString(),
        title: it['title'] ?? '',
        cover: (it['cover'] ?? '') is String && (it['cover'] as String).isNotEmpty
            ? api.bookCover(it['cover'])
            : '',
        src: isBook ? 'CLASSICS' : 'NOVELS',
        kind: (it['kind'] ?? kind).toString(),
      );
    }).toList();
  }

  Future<List<BookItem>> _gutLaneSafe() async {
    try {
      final r = await api.catalogBrowse('book', 'popular', 1).timeout(const Duration(seconds: 18));
      final items = (r['items'] as List?) ?? const [];
      final rows = items
          .whereType<Map<String, dynamic>>()
          .map((it) => BookItem(
                sid: (it['src'] ?? 'gutenberg').toString(),
                bid: (it['id'] ?? '').toString(),
                title: it['title'] ?? '',
                cover: (it['cover'] ?? '') is String && (it['cover'] as String).isNotEmpty
                    ? api.bookCover(it['cover'])
                    : '',
                src: 'CLASSICS',
                kind: 'book',
              ))
          .toList();
      if (rows.isNotEmpty) return rows;
    } catch (_) {}
    return gutenbergSeed.map(_gutSeedItem).toList();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final title = switch (widget.kind) {
      'manga' => 'POPULAR THIS WEEK',
      'comic' => 'POPULAR COMICS',
      'novel' => 'POPULAR NOVELS',
      _ => 'POPULAR CLASSICS',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(title),
        if (loading)
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.52,
            children: List.generate(6, (_) => Container(
              decoration: BoxDecoration(
                color: p.bg2,
                border: Border.all(color: p.line),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(child: SpinBadge()),
            )),
          )
        else if (failed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: GestureDetector(
              onTap: () {
                attempt += 1;
                _load();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  border: Border.all(color: p.lineHard),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text('COULDN\'T LOAD — TAP TO RETRY',
                    style: tMono(10, w: FontWeight.w700).copyWith(color: p.dim, letterSpacing: 0.6)),
              ),
            ),
          )
        else if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text('nothing here right now — check back soon',
                style: tMono(10).copyWith(color: p.faint)),
          )
        else
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.52,
            children: rows.map((b) => BookCard(item: b, onTap: () => widget.onOpen(b))).toList(),
          ),
      ],
    );
  }
}

/* ---------- POPULAR / LATEST feeds ---------- */
class FeedGrid extends StatefulWidget {
  final String tab; // popular | latest
  final String kind;
  final ValueChanged<String> onKind;
  const FeedGrid({super.key, required this.tab, required this.kind, required this.onKind});
  @override
  State<FeedGrid> createState() => _FeedGridState();
}

class _FeedGridState extends State<FeedGrid> {
  final _items = <BookItem>[];
  final _controller = ScrollController();
  int _page = 1;
  bool _loading = false;
  bool _done = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (_controller.position.extentAfter < 600) _loadMore();
    });
    _loadMore();
  }

  @override
  void didUpdateWidget(covariant FeedGrid old) {
    super.didUpdateWidget(old);
    if (old.tab != widget.tab || old.kind != widget.kind) {
      _items.clear();
      _page = 1;
      _done = false;
      _error = false;
      _loadMore();
    }
  }

  Future<List<BookItem>> _fetch(int page) async {
    switch (widget.kind) {
      case 'manga':
        return widget.tab == 'popular' ? mergedPopular(page) : mergedLatest(page);
      case 'comic':
        return widget.tab == 'popular' ? comicPopular(page) : comicLatest(page);
      case 'novel':
        final r = await api.catalogBrowse('novel', widget.tab == 'latest' ? 'latest' : 'popular', page)
            .timeout(const Duration(seconds: 18));
        return _bookRows(r, 'novel');
      case 'book':
      default:
        final r = await api.catalogBrowse('book', widget.tab == 'latest' ? 'latest' : 'popular', page)
            .timeout(const Duration(seconds: 18));
        return _bookRows(r, 'book');
    }
  }

  List<BookItem> _bookRows(Map<String, dynamic> r, String kind) {
    final items = (r['items'] as List?) ?? const [];
    return items.whereType<Map<String, dynamic>>().map((it) {
      final isBook = it['kind'] == 'book';
      return BookItem(
        sid: (it['src'] ?? '').toString(),
        bid: (it['id'] ?? '').toString(),
        title: it['title'] ?? '',
        cover: (it['cover'] ?? '') is String && (it['cover'] as String).isNotEmpty
            ? api.bookCover(it['cover'])
            : '',
        src: isBook ? 'CLASSICS' : 'NOVELS',
        kind: (it['kind'] ?? kind).toString(),
      );
    }).toList();
  }

  Future<void> _loadMore() async {
    if (_loading || _done) return;
    _loading = true;
    setState(() {});
    try {
      final rows = await _fetch(_page).timeout(const Duration(seconds: 18));
      if (rows.isEmpty) _done = true;
      _error = false;
      if (mounted) {
        setState(() {
          _items.addAll(rows);
          _page += 1;
          _loading = false;
        });
      } else {
        _loading = false;
      }
    } catch (_) {
      _error = _items.isEmpty;
      _done = _items.isEmpty; // one tap retry reloads page 1
      _loading = false;
      if (mounted) setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      children: [
        KindChips(kind: widget.kind, onKind: widget.onKind),
        Expanded(
          child: _items.isEmpty && _loading && !_error
              ? const Center(child: SpinBadge())
              : _items.isEmpty && _error
                  ? Center(
                      child: GestureDetector(
                        onTap: () {
                          _done = false;
                          _error = false;
                          _loadMore();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: p.lineHard),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('COULDN\'T LOAD — TAP TO RETRY',
                              style: tMono(10.5, w: FontWeight.w700)
                                  .copyWith(color: p.dim, letterSpacing: 0.6)),
                        ),
                      ),
                    )
                  : GridView.builder(
                      controller: _controller,
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.52,
                      ),
                      itemCount: _items.length + (_done ? 0 : 1),
                      itemBuilder: (_, i) {
                        if (i >= _items.length) {
                          return Center(child: _error
                              ? Text('tap to retry', style: tMono(9.5).copyWith(color: p.faint))
                              : const SpinBadge());
                        }
                        final b = _items[i];
                        return BookCard(
                          item: b,
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => DetailsPage(sid: b.sid, bid: b.bid, coverHint: b.cover),
                          )),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

/* MANGACA browse — the home tab. Top-bar section tabs (FOR YOU / POPULAR /
   LATEST / TV), kind chips (MANGA / NOVELS / CLASSICS), For-You feed with
   hero + rails, infinite popular/latest grids. */

import 'package:flutter/material.dart';
import '../api.dart' as api;
import '../models.dart';
import '../sources.dart';
import '../store.dart';
import '../widgets.dart';
import '../main.dart' show openAuthSheet;
import 'details.dart';

class BrowsePage extends StatefulWidget {
  final String section;
  final ValueChanged<String> onSection;
  const BrowsePage({super.key, required this.section, required this.onSection});
  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  String kind = 'manga'; // manga | novel | book

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
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
          MChip('MANGA', on: kind == 'manga', onTap: () => onKind('manga')),
          const SizedBox(width: 8),
          MChip('NOVELS', on: kind == 'novel', onTap: () => onKind('novel')),
          const SizedBox(width: 8),
          MChip('CLASSICS', on: kind == 'book', onTap: () => onKind('book')),
        ],
      ),
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

class _ForYouFeedState extends State<ForYouFeed> {
  List<BookItem>? _hero;
  List<TrendItem>? _trending;
  List<BookItem>? _novels;
  List<BookItem>? _popular;
  List<MapEntry<String, ProgressEntry>> _resume = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // resume rail
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

    try {
      final orig = sourceById('originals')!;
      final books = await orig.popular(1);
      if (mounted) setState(() => _hero = books);
    } catch (_) {}
    trending().then((rows) {
      if (mounted) setState(() => _trending = rows);
    });
    try {
      final g = sourceById('gutenberg')!;
      final rows = await g.popular(1);
      if (mounted) setState(() => _novels = rows.take(12).toList());
    } catch (_) {}
    _loadPopular();
  }

  Future<void> _loadPopular() async {
    try {
      if (widget.kind == 'manga') {
        final rows = await mergedPopular(1);
        if (mounted) setState(() => _popular = rows.take(30).toList());
      } else {
        final r = await api.catalogBrowse(widget.kind, 'popular', 1);
        final items = (r['items'] as List?) ?? const [];
        final rows = items.whereType<Map<String, dynamic>>().map((it) {
          return BookItem(
            sid: (it['src'] ?? '').toString(),
            bid: (it['id'] ?? '').toString(),
            title: it['title'] ?? '',
            cover: (it['cover'] ?? '') is String && (it['cover'] as String).isNotEmpty
                ? api.imgx(it['cover'])
                : '',
            src: it['kind'] == 'book' ? 'CLASSICS' : 'NOVELS',
            kind: (it['kind'] ?? widget.kind).toString(),
          );
        }).toList();
        if (mounted) setState(() => _popular = rows.take(30).toList());
      }
    } catch (_) {
      if (mounted) setState(() => _popular = []);
    }
  }

  @override
  void didUpdateWidget(covariant ForYouFeed old) {
    super.didUpdateWidget(old);
    if (old.kind != widget.kind) _loadPopular();
  }

  void _openTrending(TrendItem t) async {
    toast(context, 'Finding “${t.match}”…');
    try {
      final res = await globalSearch(t.match, 1);
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

  void _openBook(BookItem b) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DetailsPage(sid: b.sid, bid: b.bid, coverHint: b.cover),
    ));
  }

  void _resumeOpen(String key, ProgressEntry prog) {
    final parts = key.split(':');
    if (parts.length < 2) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DetailsPage(sid: parts[0], bid: parts.sublist(1).join(':'), coverHint: '', startCid: prog.cid),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    if (_hero == null) {
      return const Center(child: SpinBadge());
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
      children: [
        KindChips(kind: widget.kind, onKind: widget.onKind),
        const SizedBox(height: 8),
        if (_hero!.isNotEmpty) _heroBanner(_hero!.first),
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
        const SectionTitle('TRENDING NOW'),
        _trending == null
            ? const SizedBox(height: 60, child: Center(child: SpinBadge()))
            : Rail(
                children: _trending!
                    .map((t) => RailCard(
                          cover: t.cover,
                          title: t.title,
                          sub: t.sub,
                          onTap: () => _openTrending(t),
                        ))
                    .toList(),
              ),
        const SectionTitle('TOP NOVELS — READ FREE'),
        _novels == null
            ? const SizedBox(height: 60, child: Center(child: SpinBadge()))
            : Rail(
                children: _novels!
                    .map((b) => RailCard(
                          cover: b.cover,
                          title: b.title,
                          sub: b.author,
                          onTap: () => _openBook(b),
                        ))
                    .toList(),
              ),
        SectionTitle(widget.kind == 'manga' ? 'POPULAR THIS WEEK' : widget.kind == 'novel' ? 'POPULAR NOVELS' : 'POPULAR CLASSICS'),
        _popular == null
            ? const SizedBox(height: 80, child: Center(child: SpinBadge()))
            : _popular!.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text('unavailable right now', style: tMono(10).copyWith(color: p.faint)),
                  )
                : GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.52,
                    children: _popular!.map((b) => BookCard(item: b, onTap: () => _openBook(b))).toList(),
                  ),
      ],
    );
  }

  Widget _heroBanner(BookItem hero) {
    final p = context.pal;
    return GestureDetector(
      onTap: () => _openBook(hero),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 168,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hero.cover.isNotEmpty)
                Image.network(hero.cover, fit: BoxFit.cover,
                    headers: const {'User-Agent': 'MANGACA/0.0.1 (Android)'},
                    errorBuilder: (_, __, ___) => Container(color: p.bg3)),
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
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _done) return;
    _loading = true;
    try {
      List<BookItem> rows = [];
      if (widget.kind == 'manga') {
        rows = widget.tab == 'popular' ? await mergedPopular(_page) : await mergedLatest(_page);
      } else {
        final kind = widget.kind == 'novel' ? 'novel' : 'book';
        final r = await api.catalogBrowse(kind, widget.tab == 'latest' ? 'latest' : 'popular', _page);
        final items = (r['items'] as List?) ?? const [];
        rows = items.whereType<Map<String, dynamic>>().map((it) {
          return BookItem(
            sid: (it['src'] ?? '').toString(),
            bid: (it['id'] ?? '').toString(),
            title: it['title'] ?? '',
            cover: (it['cover'] ?? '') is String && (it['cover'] as String).isNotEmpty
                ? api.imgx(it['cover'])
                : '',
            src: it['kind'] == 'book' ? 'CLASSICS' : 'NOVELS',
            kind: (it['kind'] ?? kind).toString(),
          );
        }).toList();
      }
      if (rows.isEmpty) _done = true;
      if (mounted) {
        setState(() {
          _items.addAll(rows);
          _page += 1;
        });
      }
    } catch (_) {
      _done = true;
    } finally {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        KindChips(kind: widget.kind, onKind: widget.onKind),
        Expanded(
          child: _items.isEmpty && _loading
              ? const Center(child: SpinBadge())
              : GridView.builder(
                  controller: _controller,
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.52,
                  ),
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
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


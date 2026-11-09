/* MANGACA details — book hero, library toggle, tags, synopsis, community
   (likes / favorites / comments on the genjutsu identity), lazy chapter list
   with unread dots and resume. */

import 'package:flutter/material.dart';
import '../api.dart' as api;
import '../models.dart';
import '../sources.dart';
import '../store.dart';
import '../widgets.dart';
import '../main.dart' show openAuthSheet;
import 'reader.dart';

class DetailsPage extends StatefulWidget {
  final String sid, bid, coverHint, startCid;
  const DetailsPage({super.key, required this.sid, required this.bid, this.coverHint = '', this.startCid = ''});
  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> {
  BookItem? book;
  List<Chapter> chapters = [];
  int shown = 0;
  String? error;
  SocialState? social;
  late final String mangaId;

  @override
  void initState() {
    super.initState();
    mangaId = '${widget.sid}:${widget.bid}';
    _load();
  }

  Future<void> _load() async {
    final source = sourceById(widget.sid);
    if (source == null) {
      setState(() => error = 'Unknown source.');
      return;
    }
    try {
      final b = await source.details(widget.bid, widget.coverHint);
      final chs = await source.chapters(widget.bid);
      if (!mounted) return;
      setState(() {
        book = b;
        chapters = chs;
        shown = chs.length.clamp(0, 100);
      });
      _loadSocial();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _loadSocial() async {
    try {
      final r = await api.socialState(mangaId);
      if (!mounted) return;
      setState(() {
        social = SocialState(
          ok: r['ok'] == true,
          liked: r['liked'] == true,
          favorited: r['favorited'] == true,
          likes: ((r['likes'] ?? 0) as num).toInt(),
          favorites: ((r['favorites'] ?? 0) as num).toInt(),
          comments: (r['comments'] as List?) ?? const [],
        );
      });
    } catch (_) {
      if (mounted) setState(() => social = SocialState(ok: false));
    }
  }

  void _openReader([Chapter? ch, int? resumePage]) {
    if (book == null || chapters.isEmpty) return;
    final idx = ch == null ? 0 : chapters.indexWhere((c) => c.cid == ch.cid);
    final source = sourceById(widget.sid)!;
    openReader(
      context,
      book: book!,
      chapters: chapters,
      source: source,
      startIndex: idx < 0 ? 0 : idx,
      resumePage: resumePage,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      backgroundColor: p.bg,
      body: error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(error!, textAlign: TextAlign.center, style: tUi(13).copyWith(color: p.dim))))
          : book == null
              ? const Center(child: SpinBadge())
              : CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      backgroundColor: p.bg,
                      foregroundColor: p.fg,
                      pinned: true,
                      elevation: 0,
                      title: Text(book!.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tDisplay(13).copyWith(color: p.fg)),
                    ),
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _hero(),
                          _actions(),
                          if (book!.tags.isNotEmpty) ...[
                            const SectionTitle('TAGS'),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              child: Wrap(spacing: 6, runSpacing: 6, children: book!.tags.map((t) => InfoChip(t)).toList()),
                            ),
                          ],
                          if (book!.synopsis.isNotEmpty) _synopsis(),
                          _community(),
                          const SectionTitle('CHAPTERS'),
                          if (chapters.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Text('No chapters yet.', style: tUi(12.5).copyWith(color: p.dim)),
                            )
                          else
                            for (var i = 0; i < shown; i++) _chapterRow(chapters[i]),
                          if (shown < chapters.length)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                              child: SizedBox(
                                width: double.infinity,
                                child: _GhostBtn(
                                  label: 'SHOW MORE CHAPTERS (${chapters.length - shown} LEFT)',
                                  onTap: () => setState(() {
                                    shown = (shown + 100).clamp(0, chapters.length);
                                  }),
                                ),
                              ),
                            ),
                          const SizedBox(height: 26),
                          Center(
                            child: Text('MANGACA · READ BEYOND THE ILLUSION',
                                style: tMono(9).copyWith(color: p.faint, letterSpacing: 1)),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _hero() {
    final p = context.pal;
    final yearStr = (book!.year == null || book!.year.toString() == 'null' || book!.year.toString().isEmpty)
        ? ''
        : ' · ${book!.year}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 110,
              height: 158,
              color: p.bg3,
              child: book!.cover.isNotEmpty
                  ? Image.network(book!.cover, fit: BoxFit.cover,
                      headers: const {'User-Agent': 'MANGACA/0.0.1 (Android)'},
                      errorBuilder: (_, __, ___) => const SizedBox())
                  : const SizedBox(),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(book!.title, style: tDisplay(16).copyWith(color: p.fg, height: 1.2)),
                const SizedBox(height: 4),
                Text('${book!.author.isEmpty ? 'Unknown' : book!.author}$yearStr',
                    style: tUi(11.5).copyWith(color: p.dim)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    InfoChip((book!.src.isNotEmpty ? book!.src : widget.sid.toUpperCase())),
                    InfoChip(book!.status.toUpperCase()),
                    InfoChip('${chapters.length} CH'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions() {
    final p = context.pal;
    final prog = Store.getProgress(widget.sid, widget.bid);
    final inLib = Store.inLibrary(widget.sid, widget.bid);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          GestureDetector(
            onTap: () async {
              if (Store.inLibrary(widget.sid, widget.bid)) {
                Store.removeLibrary(widget.sid, widget.bid);
                if (Store.user != null) api.librarySet(mangaId, null, remove: true).catchError((_) => <String, dynamic>{});
                toast(context, 'Removed from library');
              } else {
                Store.addLibrary(book!);
                if (Store.user != null) {
                  api.librarySet(mangaId, 'reading').catchError((_) => <String, dynamic>{});
                  api.socialFavorite(mangaId).catchError((_) => <String, dynamic>{});
                }
                toast(context, 'Added to library');
              }
              setState(() {});
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                border: Border.all(color: inLib ? p.fg : p.lineHard),
                borderRadius: BorderRadius.circular(7),
                color: inLib ? p.bg3 : Colors.transparent,
              ),
              child: Icon(inLib ? Icons.favorite : Icons.favorite_border,
                  size: 18, color: inLib ? p.fg : p.dim),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (prog != null && prog.cid.isNotEmpty) {
                  final idx = chapters.indexWhere((c) => c.cid == prog.cid);
                  _openReader(chapters[idx >= 0 ? idx : 0], prog.page);
                } else if (widget.startCid.isNotEmpty) {
                  final idx = chapters.indexWhere((c) => c.cid == widget.startCid);
                  _openReader(chapters[idx >= 0 ? idx : 0]);
                } else {
                  _openReader(chapters.isEmpty ? null : chapters.first);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  border: Border.all(color: p.fg, width: 1.5),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.play_arrow, size: 17, color: p.fg),
                    const SizedBox(width: 6),
                    Text(
                      prog != null && prog.cid.isNotEmpty
                          ? 'RESUME CH ${_chNum(prog.cid)}'
                          : widget.startCid.isNotEmpty
                              ? 'RESUME READING'
                              : 'START READING',
                      style: tUi(12, w: FontWeight.w700).copyWith(color: p.fg, letterSpacing: 0.6),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _chNum(String cid) {
    final ch = chapters.where((c) => c.cid == cid).firstOrNull;
    if (ch == null || ch.number == 0) return '–';
    return ch.number.toInt().toString().padLeft(2, '0');
  }

  Widget _synopsis() {
    final p = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('SYNOPSIS'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(book!.synopsis, style: tUi(12.5).copyWith(color: p.dim, height: 1.65)),
        ),
      ],
    );
  }

  Widget _community() {
    final p = context.pal;
    if (social == null) {
      return const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SectionTitle('COMMUNITY'),
        Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: SpinBadge()),
      ]);
    }
    if (!social!.ok) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle('COMMUNITY'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text('Community data unavailable right now.', style: tUi(11.5).copyWith(color: p.faint)),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('COMMUNITY'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: p.line),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => _guard(() async {
                        await api.socialLike(mangaId);
                        _loadSocial();
                        toast(context, 'Liked');
                      }),
                      child: InfoChip('♥ ${social!.likes}'),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _guard(() async {
                        await api.socialFavorite(mangaId);
                        _loadSocial();
                        toast(context, 'Favorited');
                      }),
                      child: InfoChip('☆ ${social!.favorites}'),
                    ),
                    const Spacer(),
                    Text('${social!.comments.length} COMMENTS',
                        style: tMono(9.5).copyWith(color: p.faint)),
                  ],
                ),
                const SizedBox(height: 10),
                for (final c in social!.comments.take(20))
                  Builder(builder: (context) {
                    final m = c as Map<String, dynamic>;
                    final uname = ((m['username'] ?? m['user'] ?? '') ?? '').toString();
                    final body = ((m['body'] ?? m['text'] ?? '') ?? '').toString();
                    final at = DateTime.tryParse((m['created_at'] ?? '') as String)?.millisecondsSinceEpoch ?? 0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(color: p.bg3, borderRadius: BorderRadius.circular(7)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('@$uname', style: tUi(11, w: FontWeight.w700).copyWith(color: p.fg)),
                              const Spacer(),
                              if (at > 0) Text(timeAgo(at), style: tMono(9).copyWith(color: p.faint)),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(body, style: tUi(11.5).copyWith(color: p.dim, height: 1.45)),
                        ],
                      ),
                    );
                  }),
                if (Store.user != null)
                  _CommentForm(onPost: (text) async {
                    final r = await api.socialComment(mangaId, text).catchError((_) => <String, dynamic>{'ok': false});
                    if (r['ok'] == true) {
                      toast(context, 'Comment posted');
                      _loadSocial();
                    } else {
                      toast(context, 'Could not post comment', err: true);
                    }
                  })
                else
                  GestureDetector(
                    onTap: () => openAuthSheet(context),
                    child: Text('Sign in with genjutsu to comment',
                        style: tUi(11.5).copyWith(color: p.fg, decoration: TextDecoration.underline)),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _guard(Future<void> Function() fn) {
    if (Store.user == null) {
      openAuthSheet(context);
      return;
    }
    fn();
  }

  Widget _chapterRow(Chapter ch) {
    final p = context.pal;
    final prog = Store.getProgress(widget.sid, widget.bid);
    final isCurrent = prog != null && prog.cid == ch.cid;
    final isRead = Store.isRead(widget.sid, widget.bid, ch.cid);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: GestureDetector(
        onTap: () => _openReader(ch),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: isCurrent ? p.bg3 : p.bg2,
            border: Border.all(color: isCurrent ? p.fg : p.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Text(ch.number > 0 ? ch.number.toInt().toString().padLeft(2, '0') : '—',
                    style: tMono(11, w: FontWeight.w700).copyWith(color: p.faint)),
              ),
              Expanded(
                child: Text(ch.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: tUi(12.5, w: FontWeight.w500).copyWith(color: p.fg)),
              ),
              Text(
                [if (ch.pages > 0) '${ch.pages}p', if (ch.date.isNotEmpty) ch.date].join(' · '),
                style: tMono(9.5).copyWith(color: p.faint),
              ),
              if (!isRead && !isCurrent) ...[
                const SizedBox(width: 8),
                Container(width: 6, height: 6, decoration: const BoxDecoration(gradient: LinearGradient(colors: kRainbow), shape: BoxShape.circle)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentForm extends StatefulWidget {
  final Future<void> Function(String) onPost;
  const _CommentForm({required this.onPost});
  @override
  State<_CommentForm> createState() => _CommentFormState();
}

class _CommentFormState extends State<_CommentForm> {
  final _c = TextEditingController();
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _c,
            maxLength: 500,
            style: tUi(12).copyWith(color: p.fg),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'Say something about this title…',
              hintStyle: tUi(11).copyWith(color: p.faint),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: BorderSide(color: p.lineHard)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: BorderSide(color: p.fg)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _busy
              ? null
              : () async {
                  final t = _c.text.trim();
                  if (t.isEmpty) return;
                  setState(() => _busy = true);
                  await widget.onPost(t);
                  if (mounted) {
                    setState(() => _busy = false);
                    _c.clear();
                  }
                },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(border: Border.all(color: p.lineHard), borderRadius: BorderRadius.circular(7)),
            child: Text(_busy ? '…' : 'POST', style: tUi(11, w: FontWeight.w700).copyWith(color: p.fg)),
          ),
        ),
      ],
    );
  }
}

class _GhostBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GhostBtn({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border.all(color: p.lineHard), borderRadius: BorderRadius.circular(7)),
        child: Center(child: Text(label, style: tUi(11, w: FontWeight.w700).copyWith(color: p.fg))),
      ),
    );
  }
}

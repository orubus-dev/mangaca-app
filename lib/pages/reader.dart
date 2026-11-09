/* MANGACA iReader — the reading engine. Manga: WEBTOON (vertical strip),
   PAGED L→R, PAGED R→L. Novels & classics: text themes (paper / sepia /
   night / black) with adjustable size. Progress saves on-device + syncs for
   signed-in readers. Ported from the web ireader.js with the same settings. */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api.dart' as api;
import '../models.dart';
import '../sources.dart';
import '../store.dart';
import '../widgets.dart';

Future<void> openReader(
  BuildContext context, {
  required BookItem book,
  required List<Chapter> chapters,
  required Source source,
  required int startIndex,
  int? resumePage,
}) {
  return Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => ReaderPage(
      book: book,
      chapters: chapters,
      source: source,
      startIndex: startIndex,
      resumePage: resumePage,
    ),
  ));
}

class ReaderPage extends StatefulWidget {
  final BookItem book;
  final List<Chapter> chapters;
  final Source source;
  final int startIndex;
  final int? resumePage;
  const ReaderPage({
    super.key,
    required this.book,
    required this.chapters,
    required this.source,
    required this.startIndex,
    this.resumePage,
  });
  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  late int index;
  late String mode; // webtoon | paged-ltr | paged-rtl | text
  late String textTheme;
  late int textSize;
  List<String> pages = [];
  String? text;
  String? error;
  bool loading = true;
  final ScrollController _scroll = ScrollController();
  final PageController _pager = PageController();

  Chapter get chapter => widget.chapters[index];
  bool get isText => widget.book.kind == 'novel' || widget.source.text != null;

  @override
  void initState() {
    super.initState();
    index = widget.startIndex;
    mode = isText ? 'text' : Store.settings.readerMode;
    textTheme = Store.settings.textTheme;
    textSize = Store.settings.textSize;
    _load();
    _scroll.addListener(_onScroll);
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
      pages = [];
      text = null;
    });
    try {
      if (isText) {
        final t = await (widget.source.text ?? (bid) async => '')(widget.book.bid);
        if (!mounted) return;
        setState(() {
          text = t;
          loading = false;
        });
        _saveProgress(0, 1);
      } else {
        final p = await widget.source.pages(widget.book.bid, chapter.cid);
        if (!mounted) return;
        setState(() {
          pages = p.map(api.abs).toList();
          loading = false;
        });
        _saveProgress(0, pages.length);
        if (widget.resumePage != null && widget.resumePage! > 0) {
          final target = widget.resumePage! - 1;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (mode == 'webtoon') {
              _scroll.jumpTo((target * 560.0).clamp(0, _scroll.position.maxScrollExtent));
            } else {
              _pager.jumpToPage(target.clamp(0, pages.length - 1));
            }
          });
        }
      }
      Store.pushHistory(HistoryEntry(
        sid: widget.book.sid,
        bid: widget.book.bid,
        title: widget.book.title,
        cover: widget.book.cover,
        cid: chapter.cid,
        ctitle: chapter.title,
        at: DateTime.now().millisecondsSinceEpoch,
      ));
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  void _onScroll() {
    if (!isText && mode == 'webtoon') {
      if (_scroll.hasClients && _scroll.position.maxScrollExtent > 0) {
        final ratio = _scroll.offset / _scroll.position.maxScrollExtent;
        final page = (ratio * (pages.length - 1)).round() + 1;
        _saveProgress(page.clamp(1, pages.length), pages.length);
        if (ratio > 0.96) _markRead();
      }
    } else if (isText && text != null && text!.isNotEmpty) {
      if (_scroll.hasClients && _scroll.position.maxScrollExtent > 0) {
        final ratio = _scroll.offset / _scroll.position.maxScrollExtent;
        _saveProgress((ratio * 999).round(), 1000);
      }
    }
  }

  bool _readSaved = false;
  void _markRead() {
    if (_readSaved) return;
    _readSaved = true;
    Store.markRead(widget.book.sid, widget.book.bid, chapter.cid);
  }

  int _lastSavedAt = 0;
  void _saveProgress(int page, int total) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSavedAt < 4000) return;
    _lastSavedAt = now;
    Store.setProgress(widget.book.sid, widget.book.bid,
        ProgressEntry(cid: chapter.cid, ctitle: chapter.title, page: page, total: total, at: now));
    if (Store.user != null) {
      api.progressSave('${widget.book.sid}:${widget.book.bid}', chapter.cid, page, total)
          .catchError((_) => <String, dynamic>{});
    }
  }

  void _goto(int i) {
    if (i < 0 || i >= widget.chapters.length) return;
    setState(() {
      index = i;
      _readSaved = false;
      _lastSavedAt = 0;
      _scroll.jumpTo(0);
      _pager.jumpToPage(0);
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _pager.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /* ---------- text palette ---------- */
  (Color, Color) get _textColors {
    switch (textTheme) {
      case 'paper':
        return (const Color(0xFFF5F1E8), const Color(0xFF232323));
      case 'sepia':
        return (const Color(0xFFE8DCC5), const Color(0xFF433422));
      case 'black':
        return (const Color(0xFF000000), const Color(0xFFBBBBBB));
      default:
        return (const Color(0xFF0A0A0B), const Color(0xFFCCCCCC));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      backgroundColor: mode == 'text' ? _textColors.$1 : Colors.black,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: SafeArea(
          top: false,
          bottom: false,
          child: Stack(
            children: [
              GestureDetector(
                behavior: HitTestBehavior.deferToChild,
                onTap: () => setState(() => _chromeOn = !_chromeOn),
                child: _body(),
              ),
              _chrome(p),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    if (loading) return const Center(child: SpinBadge());
    if (error != null) {
      final p = context.pal;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Text(error!, textAlign: TextAlign.center, style: tUi(12.5).copyWith(color: p.dim, height: 1.6)),
        ),
      );
    }
    if (mode == 'text') return _textContent();
    if (pages.isEmpty) {
      final p = context.pal;
      return Center(child: Text('No pages yet.', style: tUi(12.5).copyWith(color: p.dim)));
    }
    if (mode == 'webtoon') return _webtoon();
    return _paged();
  }

  Widget _webtoon() {
    return ListView.builder(
      controller: _scroll,
      itemCount: pages.length,
      itemBuilder: (_, i) => Image.network(
        pages[i],
        headers: const {'User-Agent': 'MANGACA/0.0.1 (Android)', 'Referer': api.BASE},
        fit: BoxFit.fitWidth,
        width: double.infinity,
        loadingBuilder: (_, child, prog) =>
            prog == null ? child : const SizedBox(height: 480, child: Center(child: SpinBadge())),
        errorBuilder: (_, __, ___) => const SizedBox(
            height: 320,
            child: Center(child: Icon(Icons.broken_image_outlined, color: Colors.white24, size: 36))),
      ),
    );
  }

  Widget _paged() {
    final rtl = mode == 'paged-rtl';
    return PageView.builder(
      controller: _pager,
      reverse: rtl,
      itemCount: pages.length,
      onPageChanged: (i) {
        _saveProgress(i + 1, pages.length);
        if (i >= pages.length - 1) _markRead();
      },
      itemBuilder: (_, i) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final w = MediaQuery.of(context).size.width;
          final right = d.globalPosition.dx > w * 0.6;
          final left = d.globalPosition.dx < w * 0.4;
          final forward = rtl ? left : right;
          final back = rtl ? right : left;
          if (forward && i < pages.length - 1) _pager.nextPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
          else if (back && i > 0) _pager.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
        },
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                maxScale: 3,
                child: Image.network(
                  pages[i],
                  headers: const {'User-Agent': 'MANGACA/0.0.1 (Android)', 'Referer': api.BASE},
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, prog) =>
                      prog == null ? child : const Center(child: SpinBadge()),
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Colors.white24, size: 36),
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                color: Colors.black54,
                child: Text('${i + 1} / ${pages.length}',
                    style: tMono(10).copyWith(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textContent() {
    if (text == null || text!.isEmpty) {
      return Center(child: Text('Empty chapter.', style: tUi(12.5).copyWith(color: _textColors.$2)));
    }
    final paras = text!.split(RegExp(r'\n\s*\n'));
    final (bg, fg) = _textColors;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(18, 60, 18, 80),
      itemCount: paras.length + 1,
      itemBuilder: (_, i) {
        if (i == paras.length) return _nextChapterButton(fg);
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Text(
            paras[i].replaceAll('\n', ' ').trim(),
            style: TextStyle(
              fontFamily: 'SpaceGrotesk',
              fontSize: textSize.toDouble(),
              height: 1.7,
              color: fg,
            ),
          ),
        );
      },
    );
  }

  Widget _nextChapterButton(Color fg) {
    final canNext = index < widget.chapters.length - 1;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: canNext
            ? GestureDetector(
                onTap: () => _goto(index + 1),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(border: Border.all(color: fg), borderRadius: BorderRadius.circular(7)),
                  child: Text('NEXT CHAPTER →', style: tUi(12, w: FontWeight.w700).copyWith(color: fg)),
                ),
              )
            : Text('— end —', style: tUi(12).copyWith(color: fg.withOpacity(0.5))),
      ),
    );
  }

  /* ---------- chrome ---------- */
  bool _chromeOn = true;

  Widget _chrome(Palette p) {
    if (!_chromeOn) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _chromeOn = true),
        child: const SizedBox.expand(),
      );
    }
    return Column(
      children: [
        // top bar
        Container(
          color: mode == 'text' ? _textColors.$1.withOpacity(0.92) : Colors.black87,
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 4, left: 4, right: 12, bottom: 6),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.arrow_back,
                    color: mode == 'text' ? _textColors.$2 : Colors.white, size: 20),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.book.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: tUi(11.5, w: FontWeight.w700).copyWith(
                            color: mode == 'text' ? _textColors.$2 : Colors.white)),
                    Text(chapter.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: tUi(10).copyWith(
                            color: mode == 'text' ? _textColors.$2.withOpacity(0.7) : Colors.white70)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: _openSettings,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: mode == 'text' ? _textColors.$2 : Colors.white54),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(mode == 'text' ? 'Aa TEXT' : _modeLabel(),
                      style: tMono(10, w: FontWeight.w500).copyWith(
                          color: mode == 'text' ? _textColors.$2 : Colors.white)),
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        // bottom bar
        Container(
          color: mode == 'text' ? _textColors.$1.withOpacity(0.92) : Colors.black87,
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 8, left: 12, right: 12, top: 8),
          child: Row(
            children: [
              _navBtn('‹ PREV', index > 0, () => _goto(index - 1), mode == 'text' ? _textColors.$2 : Colors.white),
              Expanded(
                child: Center(
                  child: Text(
                    '${index + 1} / ${widget.chapters.length}',
                    style: tMono(10.5).copyWith(color: mode == 'text' ? _textColors.$2.withOpacity(0.8) : Colors.white70),
                  ),
                ),
              ),
              _navBtn('NEXT ›', index < widget.chapters.length - 1, () => _goto(index + 1),
                  mode == 'text' ? _textColors.$2 : Colors.white),
            ],
          ),
        ),
      ],
    );
  }

  String _modeLabel() {
    switch (mode) {
      case 'webtoon':
        return '⇕ WEBTOON';
      case 'paged-rtl':
        return '→ PAGED RTL';
      case 'paged-ltr':
        return '← PAGED LTR';
      default:
        return 'Aa TEXT';
    }
  }

  Widget _navBtn(String label, bool enabled, VoidCallback onTap, Color color) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Text(label,
          style: tUi(11, w: FontWeight.w700)
              .copyWith(color: enabled ? color : color.withOpacity(0.3))),
    );
  }

  void _openSettings() {
    final p = context.pal;
    if (mode == 'text') {
      showMSheet(context, (ctx) {
        final (bg, fg) = _textColors;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetGrab(),
            Text('TEXT READER', style: tDisplay(14).copyWith(color: p.fg)),
            const SizedBox(height: 12),
            const RainbowLine(),
            const SizedBox(height: 14),
            Text('THEME', style: tMono(9.5, w: FontWeight.w700).copyWith(color: p.faint)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['paper', 'sepia', 'night', 'black']
                  .map((t) => MChip(t.toUpperCase(),
                      on: textTheme == t,
                      onTap: () {
                        setState(() => textTheme = t);
                        Store.settings.textTheme = t;
                        Store.saveSettings();
                        Navigator.of(ctx).pop();
                      }))
                  .toList(),
            ),
            const SizedBox(height: 16),
            Text('SIZE', style: tMono(9.5, w: FontWeight.w700).copyWith(color: p.faint)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [14, 16, 18, 20, 24]
                  .map((s) => MChip('$s',
                      on: textSize == s,
                      onTap: () {
                        setState(() => textSize = s);
                        Store.settings.textSize = s;
                        Store.saveSettings();
                        Navigator.of(ctx).pop();
                      }))
                  .toList(),
            ),
            const SizedBox(height: 8),
          ],
        );
      });
      return;
    }
    showMSheet(context, (ctx) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SheetGrab(),
          Text('MANGA MODE', style: tDisplay(14).copyWith(color: p.fg)),
          const SizedBox(height: 12),
          const RainbowLine(),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            children: [
              ('webtoon', 'WEBTOON'),
              ('paged-ltr', 'PAGED L→R'),
              ('paged-rtl', 'PAGED R→L'),
            ]
                .map((m) => MChip(m.$2,
                    on: mode == m.$1,
                    onTap: () {
                      setState(() {
                        mode = m.$1;
                        Store.settings.readerMode = m.$1;
                        Store.saveSettings();
                      });
                      Navigator.of(ctx).pop();
                    }))
                .toList(),
          ),
          const SizedBox(height: 8),
        ],
      );
    });
  }
}

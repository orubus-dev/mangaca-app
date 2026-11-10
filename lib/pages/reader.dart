/* MANGACA iReader — the reading engine. Manga & comics: WEBTOON (vertical
   strip), PAGED L→R, PAGED R→L. Novels & classics: text themes (paper /
   sepia / night / black) with adjustable size + read-aloud TTS (speed /
   tone / volume, sentence highlight, transport) + touch lock.

   TTS design note: the transport never trusts speak() completion futures
   (cancellation and completion are indistinguishable on some Android
   engines — that's the classic "buggy TTS controls" bug). Everything is
   driven by the engine's completion/cancel handlers + a stop-and-resume
   state machine: pause = stop + keep index, resume = speak from index. */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
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

  /* touch lock — the explicit lock the reader never had */
  bool _locked = false;

  /* ---------- tts ----------
     Epoch state machine: EVERY control action (start/pause/resume/jump/
     settings change/chapter change) bumps _ttsEpoch. Utterances stamp the
     epoch they were started under, and the engine handlers ignore any
     event from a stale epoch — so a stop() that fires a late completion
     or error (the classic Android TTS bug) can never skip sentences,
     double-advance or resurrect itself after a pause. */
  FlutterTts? _tts;
  bool _ttsActive = false; // session on (transport visible)
  bool _ttsPaused = false;
  int _ttsIdx = 0;
  int _ttsShownIdx = -1; // highlighted sentence
  int _ttsEpoch = 0;
  int _ttsSpokenEpoch = -1;
  int _ttsErrors = 0; // consecutive engine errors (retry cap)
  List<String> _sentences = [];
  List<int> _sentencePara = []; // paragraph index per sentence
  List<GlobalKey> _paraKeys = [];
  double get _ttsRate => Store.settings.tts.rate;
  double get _ttsPitch => Store.settings.tts.pitch;
  double get _ttsVolume => Store.settings.tts.volume;

  Chapter get chapter => widget.chapters[index];
  bool get isText => widget.book.kind == 'novel' || widget.book.kind == 'book' || widget.source.text != null;

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
    _ttsStopHard();
    try {
      if (isText) {
        final t = await (widget.source.text ?? (bid) async => '')(widget.book.bid)
            .timeout(const Duration(seconds: 45));
        if (!mounted) return;
        setState(() {
          text = t;
          loading = false;
        });
        _saveProgress(0, 1000);
      } else {
        final p = await widget.source.pages(widget.book.bid, chapter.cid)
            .timeout(const Duration(seconds: 30));
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
              if (_scroll.hasClients) {
                _scroll.jumpTo((target * 560.0).clamp(0, _scroll.position.maxScrollExtent));
              }
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
    _ttsStopHard();
    setState(() {
      index = i;
      _readSaved = false;
      _lastSavedAt = 0;
    });
    _load();
  }

  @override
  void dispose() {
    _ttsStopHard();
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
              /* the content — fully inert while the touch lock is on */
              IgnorePointer(
                ignoring: _locked,
                child: GestureDetector(
                  behavior: HitTestBehavior.deferToChild,
                  onTap: () => setState(() => _chromeOn = !_chromeOn),
                  child: _body(),
                ),
              ),
              if (!_locked) _chrome(p),
              /* the lock badge — ALWAYS visible while locked, chrome or not.
                 It is the fixed, unmissable anchor the old build never had. */
              if (_locked)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 10,
                  right: 14,
                  child: GestureDetector(
                    onTap: () => setState(() => _locked = false),
                    child: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.82),
                        border: Border.all(color: const Color(0xFFFFB84D), width: 1.4),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(Icons.lock, color: Color(0xFFFFB84D), size: 18),
                    ),
                  ),
                ),
              /* floating unlock pill — the big, thumb-friendly unlock */
              if (_locked)
                Positioned(
                  right: 14,
                  bottom: MediaQuery.of(context).padding.bottom + 18,
                  child: GestureDetector(
                    onTap: () => setState(() => _locked = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.82),
                        border: Border.all(color: Colors.white38),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_open, color: Colors.white, size: 15),
                          const SizedBox(width: 7),
                          Text('TOUCH TO UNLOCK',
                              style: tMono(9.5, w: FontWeight.w700).copyWith(
                                  color: Colors.white, letterSpacing: 0.7)),
                        ],
                      ),
                    ),
                  ),
                ),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(28),
              child: Text(error!, textAlign: TextAlign.center,
                  style: tUi(12.5).copyWith(color: p.dim, height: 1.6)),
            ),
            GestureDetector(
              onTap: _load,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: p.lineHard),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text('RETRY', style: tMono(11, w: FontWeight.w700).copyWith(color: p.fg)),
              ),
            ),
          ],
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
        headers: const {'User-Agent': 'MANGACA/0.0.2 (Android)', 'Referer': api.BASE},
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
        /* the page owns ALL taps: side zones turn, center toggles chrome —
           the old nested-gesture version could leave the chrome unreachable */
        onTapUp: (d) {
          final w = MediaQuery.of(context).size.width;
          final x = d.globalPosition.dx;
          final right = x > w * 0.6;
          final left = x < w * 0.4;
          final forward = rtl ? left : right;
          final back = rtl ? right : left;
          if (forward && i < pages.length - 1) {
            _pager.nextPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
          } else if (back && i > 0) {
            _pager.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
          } else {
            setState(() => _chromeOn = !_chromeOn);
          }
        },
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                maxScale: 3,
                child: Image.network(
                  pages[i],
                  headers: const {'User-Agent': 'MANGACA/0.0.2 (Android)', 'Referer': api.BASE},
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

  /* ================= text content + tts highlight ================= */

  void _buildSentences() {
    final t = text ?? '';
    final paras = t.split(RegExp(r'\n\s*\n')).map((s) => s.replaceAll('\n', ' ').trim()).where((s) => s.isNotEmpty).toList();
    _sentences = [];
    _sentencePara = [];
    for (var pi = 0; pi < paras.length; pi++) {
      final sents = _splitSentences(paras[pi]);
      for (final s in sents) {
        _sentences.add(s);
        _sentencePara.add(pi);
      }
    }
    _paraKeys = List.generate(paras.length, (_) => GlobalKey());
  }

  List<String> _splitSentences(String para) {
    final parts = para.split(RegExp(r'(?<=[.!?…:;])\s+'));
    final out = <String>[];
    for (final raw in parts) {
      var s = raw.trim();
      if (s.isEmpty) continue;
      if (s.length > 700) {
        // very long run-on — cut at word boundaries so no engine chokes
        while (s.length > 700) {
          var cut = s.lastIndexOf(' ', 700);
          if (cut < 200) cut = 700;
          out.add(s.substring(0, cut).trim());
          s = s.substring(cut).trim();
        }
      }
      if (s.isNotEmpty) out.add(s);
    }
    return out.isEmpty && para.isNotEmpty ? [para] : out;
  }

  /* which sentence starts at the current viewport — TTS "continue from here" */
  int _sentenceAtViewport() {
    if (!_scroll.hasClients || _scroll.position.maxScrollExtent <= 0) return 0;
    final ratio = (_scroll.offset / _scroll.position.maxScrollExtent).clamp(0.0, 1.0);
    if (_sentencePara.isEmpty) return 0;
    final para = (ratio * (_paraKeys.length - 1)).round().clamp(0, _paraKeys.length - 1);
    final idx = _sentencePara.indexOf(para);
    return idx < 0 ? 0 : idx;
  }

  void _ensureVisibleSentence(int i) {
    if (i < 0 || i >= _sentencePara.length) return;
    final key = _paraKeys[_sentencePara[i]];
    final ctx = key.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.12,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    }
  }

  Widget _textContent() {
    if (text == null || text!.isEmpty) {
      return Center(child: Text('Empty chapter.', style: tUi(12.5).copyWith(color: _textColors.$2)));
    }
    final paras = text!.split(RegExp(r'\n\s*\n')).map((s) => s.replaceAll('\n', ' ').trim()).where((s) => s.isNotEmpty).toList();
    if (_paraKeys.length != paras.length) _buildSentences();
    final fg = _textColors.$2;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(18, 60, 18, 90),
      itemCount: paras.length + 1,
      itemBuilder: (_, i) {
        if (i == paras.length) return _nextChapterButton(fg);
        final para = paras[i];
        final key = _paraKeys[i];
        // sentence spans for this paragraph
        final start = _sentencePara.indexOf(i);
        Widget textWidget;
        if (_ttsActive && start >= 0) {
          final spans = <TextSpan>[];
          var cursor = start;
          var consumed = 0;
          while (cursor < _sentences.length && _sentencePara[cursor] == i) {
            final s = _sentences[cursor];
            spans.add(TextSpan(
              text: s + (cursor + 1 < _sentences.length && _sentencePara[cursor + 1] == i ? ' ' : ''),
              style: TextStyle(
                fontFamily: 'SpaceGrotesk',
                fontSize: textSize.toDouble(),
                height: 1.7,
                color: fg,
                backgroundColor: cursor == _ttsShownIdx
                    ? const Color(0x66FFB84D)
                    : null,
              ),
            ));
            consumed += s.length + 1;
            cursor++;
          }
          if (consumed < para.length) {
            spans.add(TextSpan(
              text: para.substring(consumed.clamp(0, para.length)),
              style: TextStyle(fontFamily: 'SpaceGrotesk', fontSize: textSize.toDouble(), height: 1.7, color: fg),
            ));
          }
          textWidget = Text.rich(
            TextSpan(children: spans),
            key: key,
          );
        } else {
          textWidget = Text(
            para,
            key: key,
            style: TextStyle(
              fontFamily: 'SpaceGrotesk',
              fontSize: textSize.toDouble(),
              height: 1.7,
              color: fg,
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: textWidget,
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

  /* ================= TTS engine ================= */

  Future<FlutterTts> _ttsEngine() async {
    if (_tts != null) return _tts!;
    final t = FlutterTts();
    await t.setLanguage('en-US');
    await t.setSpeechRate(_ttsRate);
    await t.setPitch(_ttsPitch);
    await t.setVolume(_ttsVolume);
    await t.awaitSpeakCompletion(false); // handlers drive everything (see header)
    t.setStartHandler(() {
      _ttsErrors = 0; // a clean start clears the error streak
    });
    t.setCompletionHandler(() {
      if (!_ttsActive || _ttsPaused) return;
      if (_ttsSpokenEpoch != _ttsEpoch) return; // stale event from a stopped utterance
      _ttsIdx = (_ttsIdx + 1).clamp(0, _sentences.isEmpty ? 0 : _sentences.length);
      if (mounted) setState(() {});
      _speakCurrent();
    });
    t.setCancelHandler(() {
      /* cancel arrives on stop() — the epoch guard makes it a no-op for
         stale utterances and a harmless one for deliberate stops */
    });
    t.setErrorHandler((msg) {
      if (!_ttsActive || _ttsPaused) return;
      if (_ttsSpokenEpoch != _ttsEpoch) return; // stale — ignore
      _ttsErrors += 1;
      if (_ttsErrors >= 3) {
        // engine is failing repeatedly — stop cleanly instead of looping
        _ttsEpoch++;
        if (mounted) {
          setState(() => _ttsPaused = true);
          toast(context, 'Read-aloud hit an engine error — paused. Tap play to retry.', err: true);
        }
        return;
      }
      _ttsIdx = (_ttsIdx + 1).clamp(0, _sentences.isEmpty ? 0 : _sentences.length);
      if (mounted) setState(() {});
      Future.delayed(const Duration(milliseconds: 120), _speakCurrent);
    });
    _tts = t;
    return t;
  }

  Future<void> _speakCurrent() async {
    if (!_ttsActive || _ttsPaused || !mounted) return;
    if (_ttsIdx >= _sentences.length) {
      _ttsFinish();
      return;
    }
    try {
      final t = await _ttsEngine();
      await t.setSpeechRate(_ttsRate);
      await t.setPitch(_ttsPitch);
      await t.setVolume(_ttsVolume);
      _ttsSpokenEpoch = _ttsEpoch; // this utterance is the current one
      if (mounted) setState(() => _ttsShownIdx = _ttsIdx);
      _ensureVisibleSentence(_ttsIdx);
      await t.speak(_sentences[_ttsIdx]);
    } catch (_) {
      // speak failed — pause the session rather than spin
      _ttsEpoch++;
      if (mounted) setState(() => _ttsPaused = true);
    }
  }

  void _ttsFinish() {
    _ttsEpoch++;
    _ttsActive = false;
    _ttsPaused = false;
    _ttsShownIdx = -1;
    if (mounted) {
      setState(() {});
      toast(context, 'Finished — that was the whole chapter');
    }
  }

  Future<void> _ttsStart({int? fromSentence}) async {
    if (_sentences.isEmpty) _buildSentences();
    if (_sentences.isEmpty) {
      toast(context, 'Nothing to read aloud', err: true);
      return;
    }
    final t = await _ttsEngine();
    _ttsEpoch++; // invalidate anything the engine still owes us
    setState(() {
      _ttsActive = true;
      _ttsPaused = false;
      _ttsIdx = (fromSentence ?? _sentenceAtViewport()).clamp(0, _sentences.length - 1);
    });
    await t.stop(); // clear anything pending (stale events now guarded)
    _speakCurrent();
  }

  Future<void> _ttsPause() async {
    _ttsEpoch++; // any completion/error racing this stop is now stale
    setState(() => _ttsPaused = true);
    try {
      await _tts?.stop(); // cancel handler is a no-op — index stays put
    } catch (_) {}
  }

  Future<void> _ttsResume() async {
    _ttsEpoch++;
    setState(() => _ttsPaused = false);
    _speakCurrent();
  }

  Future<void> _ttsToggle() async {
    if (_ttsPaused) {
      await _ttsResume();
    } else {
      await _ttsPause();
    }
  }

  Future<void> _ttsJump(int delta) async {
    if (!_ttsActive) return;
    _ttsEpoch++;
    final next = (_ttsIdx + delta).clamp(0, _sentences.isEmpty ? 0 : _sentences.length - 1);
    setState(() => _ttsIdx = next);
    try {
      await _tts?.stop();
    } catch (_) {}
    if (!_ttsPaused) _speakCurrent();
  }

  /* settings change while playing — stop and re-speak the current sentence
     in the new voice (the engine applies rate/pitch per utterance) */
  Future<void> _ttsApply(double rate, double pitch, double volume) async {
    Store.settings.tts..rate = rate..pitch = pitch..volume = volume;
    Store.saveSettings();
    _ttsEpoch++;
    setState(() {});
    if (_ttsActive) {
      try {
        await _tts?.stop();
      } catch (_) {}
      if (!_ttsPaused) _speakCurrent();
    }
  }

  Future<void> _ttsStopHard() async {
    _ttsEpoch++;
    _ttsActive = false;
    _ttsPaused = false;
    _ttsShownIdx = -1;
    try {
      await _tts?.stop();
    } catch (_) {}
  }

  /* ================= TTS transport pill ================= */

  Widget _ttsTransport(Color fg) {
    final total = _sentences.length;
    final pos = total == 0 ? 0.0 : ((_ttsIdx + 1) / total);
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _textColors.$1.withOpacity(0.95),
        border: Border.all(color: fg.withOpacity(0.35)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: _ttsToggle,
            child: Icon(_ttsPaused ? Icons.play_arrow : Icons.pause,
                color: fg, size: 24),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => _ttsJump(-1),
            child: Icon(Icons.replay, color: fg.withOpacity(0.75), size: 19),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: pos,
                    minHeight: 3,
                    backgroundColor: fg.withOpacity(0.18),
                    valueColor: AlwaysStoppedAnimation(const Color(0xFFFFB84D)),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'SENTENCE ${_ttsIdx + 1} / $total${_ttsPaused ? '  ·  PAUSED' : ''}',
                  style: tMono(8.5, w: FontWeight.w700).copyWith(color: fg.withOpacity(0.75), letterSpacing: 0.7),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _ttsJump(1),
            child: Icon(Icons.forward_30, color: fg.withOpacity(0.75), size: 19),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () => _ttsStopHard(),
            child: Icon(Icons.stop, color: fg.withOpacity(0.85), size: 21),
          ),
        ],
      ),
    );
  }

  /* ---------- chrome ---------- */
  bool _chromeOn = true;

  Widget _chrome(Palette p) {
    if (!_chromeOn) {
      /* chrome hidden — but a live read-aloud session keeps its transport
         on screen (tappable), because "where is pause?" was half of the
         buggy-controls complaint */
      return Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _chromeOn = true),
            child: const SizedBox.expand(),
          ),
          if (isText && _ttsActive && !_locked)
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.of(context).padding.bottom + 8,
              child: _ttsTransport(mode == 'text' ? _textColors.$2 : Colors.white),
            ),
        ],
      );
    }
    final barColor = mode == 'text' ? _textColors.$1.withOpacity(0.94) : Colors.black87;
    final fg = mode == 'text' ? _textColors.$2 : Colors.white;
    return Column(
      children: [
        // top bar
        Container(
          color: barColor,
          padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 4, left: 4, right: 8, bottom: 6),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: Icon(Icons.arrow_back, color: fg, size: 20),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.book.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: tUi(11.5, w: FontWeight.w700).copyWith(color: fg)),
                    Text(chapter.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: tUi(10).copyWith(color: fg.withOpacity(0.7))),
                  ],
                ),
              ),
              if (isText && !loading && error == null)
                GestureDetector(
                  onTap: () => _ttsActive ? _openTtsSheet() : _ttsStart(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: _ttsActive ? const LinearGradient(colors: kRainbow) : null,
                      border: _ttsActive ? null : Border.all(color: fg.withOpacity(0.5)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.graphic_eq, size: 13, color: _ttsActive ? Colors.black : fg),
                        const SizedBox(width: 5),
                        Text('SPEAK',
                            style: tMono(9.5, w: FontWeight.w700).copyWith(
                                color: _ttsActive ? Colors.black : fg, letterSpacing: 0.8)),
                      ],
                    ),
                  ),
                ),
              const SizedBox(width: 6),
              /* the touch lock — explicit, always visible in chrome */
              IconButton(
                onPressed: () => setState(() => _locked = true),
                icon: Icon(
                  Icons.lock_open,
                  size: 19,
                  color: fg.withOpacity(0.85),
                ),
                tooltip: 'Lock touches (read without accidental taps)',
              ),
              const SizedBox(width: 2),
              GestureDetector(
                onTap: _openSettings,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: fg.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(mode == 'text' ? 'Aa TEXT' : _modeLabel(),
                      style: tMono(10, w: FontWeight.w500).copyWith(color: fg)),
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        // tts transport (text mode only, while the session is live)
        if (isText && _ttsActive) _ttsTransport(fg),
        // bottom bar
        Container(
          color: barColor,
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 8, left: 12, right: 12, top: 8),
          child: Row(
            children: [
              _navBtn('‹ PREV', index > 0, () => _goto(index - 1), fg),
              Expanded(
                child: Center(
                  child: Text(
                    '${index + 1} / ${widget.chapters.length}',
                    style: tMono(10.5).copyWith(color: fg.withOpacity(0.8)),
                  ),
                ),
              ),
              _navBtn('NEXT ›', index < widget.chapters.length - 1, () => _goto(index + 1), fg),
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

  void _openTtsSheet() {
    final p = context.pal;
    showMSheet(context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx, setSheet) {
        final tts = Store.settings.tts;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetGrab(),
            Text('READ ALOUD', style: tDisplay(14).copyWith(color: p.fg)),
            const SizedBox(height: 4),
            Text('Speed, tone and volume — changes apply from the current sentence.',
                style: tUi(11).copyWith(color: p.dim)),
            const SizedBox(height: 12),
            const RainbowLine(),
            const SizedBox(height: 14),
            Text('SPEED', style: tMono(9.5, w: FontWeight.w700).copyWith(color: p.faint, letterSpacing: 1)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
                  .map((r) => MChip('×${_rateLabel(r)}',
                      on: tts.rate == r,
                      onTap: () {
                        _ttsApply(r, tts.pitch, tts.volume);
                        setSheet(() {});
                      }))
                  .toList(),
            ),
            const SizedBox(height: 14),
            Text('TONE', style: tMono(9.5, w: FontWeight.w700).copyWith(color: p.faint, letterSpacing: 1)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                (0.6, 'DEEP'),
                (0.85, 'LOW'),
                (1.0, 'NATURAL'),
                (1.25, 'BRIGHT'),
                (1.5, 'HIGH'),
              ]
                  .map((e) => MChip(e.$2,
                      on: tts.pitch == e.$1,
                      onTap: () {
                        _ttsApply(tts.rate, e.$1, tts.volume);
                        setSheet(() {});
                      }))
                  .toList(),
            ),
            const SizedBox(height: 14),
            Text('VOLUME', style: tMono(9.5, w: FontWeight.w700).copyWith(color: p.faint, letterSpacing: 1)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [0.4, 0.6, 0.8, 1.0]
                  .map((v) => MChip('${(v * 100).round()}%',
                      on: tts.volume == v,
                      onTap: () {
                        _ttsApply(tts.rate, tts.pitch, v);
                        setSheet(() {});
                      }))
                  .toList(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: RainbowEdgeButton(
                label: _ttsActive ? 'STOP READING' : 'READ THIS CHAPTER',
                onTap: () {
                  Navigator.of(ctx).pop();
                  if (_ttsActive) {
                    _ttsStopHard();
                  } else {
                    _ttsStart();
                  }
                },
              ),
            ),
            const SizedBox(height: 6),
          ],
        );
      });
    });
  }

  void _openSettings() {
    final p = context.pal;
    if (mode == 'text') {
      showMSheet(context, builder: (ctx) {
        final fg = _textColors.$2;
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
            const SizedBox(height: 16),
            Text('READ ALOUD', style: tMono(9.5, w: FontWeight.w700).copyWith(color: p.faint)),
            const SizedBox(height: 8),
            Row(
              children: [
                MChip('SPEAK ⚙', onTap: () {
                  Navigator.of(ctx).pop();
                  if (_ttsActive) {
                    _openTtsSheet();
                  } else {
                    _ttsStart();
                  }
                }),
                const SizedBox(width: 8),
                if (_ttsActive)
                  MChip('STOP', onTap: () {
                    Navigator.of(ctx).pop();
                    _ttsStopHard();
                  }),
              ],
            ),
            const SizedBox(height: 8),
          ],
        );
      });
      return;
    }
    showMSheet(context, builder: (ctx) {
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

String _rateLabel(double r) {
  if (r == r.roundToDouble()) return r.toStringAsFixed(0);
  return r.toStringAsFixed(2).replaceAll(RegExp(r'0$'), '');
}

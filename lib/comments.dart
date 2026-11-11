/* MANGACA chapter comments — threaded comments on the genjutsu identity.
   Public read, session-gated write: view, reply (one level, flattened
   server-side), like, delete-own. The reader opens it scoped to the current
   chapter; details opens it scoped to the whole book. */

import 'package:flutter/material.dart';
import 'api.dart' as api;
import 'store.dart';
import 'widgets.dart';
import 'main.dart' show openAuthSheet;

const Color kPink = Color(0xFFF2A9C4);

Future<void> showBookComments(
  BuildContext context, {
  required String book,
  String chapter = '',
  String? chapterLabel,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => CommentsSheet(book: book, chapter: chapter, chapterLabel: chapterLabel),
  );
}

class CommentsSheet extends StatefulWidget {
  final String book;
  final String chapter;
  final String? chapterLabel;
  const CommentsSheet({super.key, required this.book, this.chapter = '', this.chapterLabel});
  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  List<dynamic> _items = [];
  final Map<String, List<dynamic>> _replies = {};
  String? _replyTo;
  String? _replyToName;
  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String get _scopeLabel {
    final l = widget.chapterLabel ?? '';
    if (l.isNotEmpty) return l.toUpperCase();
    return widget.chapter.isNotEmpty ? 'THIS CHAPTER' : 'ALL CHAPTERS';
  }

  Future<void> _load() async {
    try {
      final r = await api.socialComments(widget.book, chapter: widget.chapter);
      if (!mounted) return;
      setState(() {
        _items = (r['comments'] as List?) ?? const [];
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openReplies(Map<String, dynamic> c) async {
    final id = (c['id'] ?? '').toString();
    try {
      final r = await api.socialComments(widget.book, parent: id);
      if (!mounted) return;
      setState(() => _replies[id] = (r['replies'] as List?) ?? const []);
    } catch (_) {
      if (mounted) toast(context, 'Could not load replies', err: true);
    }
  }

  void _needSignIn() {
    openAuthSheet(context, onSignedIn: () {
      if (mounted) setState(() {});
    });
  }

  Future<void> _like(Map<String, dynamic> c) async {
    if (Store.user == null) {
      _needSignIn();
      return;
    }
    try {
      final r = await api.socialCommentLike((c['id'] ?? '').toString());
      if (r['ok'] == true && mounted) {
        setState(() {
          c['liked'] = r['liked'] == true;
          c['likes'] = r['likes'] ?? 0;
        });
      }
    } catch (_) {
      if (mounted) toast(context, 'Could not like — try again', err: true);
    }
  }

  Future<void> _send() async {
    if (_sending) return;
    if (Store.user == null) {
      _needSignIn();
      return;
    }
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      final r = await api.socialComment(widget.book, text, chapter: widget.chapter, parent: _replyTo ?? '');
      if (!mounted) return;
      if (r['ok'] == true) {
        final c = ((r['comment'] as Map?) ?? const {}).cast<String, dynamic>();
        setState(() {
          if (_replyTo != null) {
            _replies.putIfAbsent(_replyTo!, () => []).add(c);
            for (final it in _items) {
              final m = it as Map<String, dynamic>;
              if ((m['id'] ?? '').toString() == _replyTo) {
                m['replies'] = (((m['replies'] as num?) ?? 0) + 1);
              }
            }
          } else {
            _items.insert(0, c);
          }
          _replyTo = null;
          _replyToName = null;
          _controller.clear();
        });
        _focus.unfocus();
      } else {
        toast(context, ((r['message'] ?? 'Could not post') ?? 'Could not post').toString(), err: true);
      }
    } catch (_) {
      if (mounted) toast(context, 'Could not post — try again', err: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> c) async {
    try {
      final r = await api.socialCommentDelete((c['id'] ?? '').toString());
      if (!mounted) return;
      if (r['ok'] == true) {
        setState(() {
          _items.removeWhere((e) => ((e as Map<String, dynamic>)['id'] ?? '') == c['id']);
          _replies.remove(c['id']);
        });
      } else {
        toast(context, 'Could not delete', err: true);
      }
    } catch (_) {
      if (mounted) toast(context, 'Could not delete', err: true);
    }
  }

  void _startReply(Map<String, dynamic> c) {
    setState(() {
      _replyTo = (c['id'] ?? '').toString();
      _replyToName = ((c['username'] ?? '') ?? '').toString();
    });
    _focus.requestFocus();
  }

  Widget _tile(Map<String, dynamic> c, {bool nested = false}) {
    final p = context.pal;
    final uname = ((c['username'] ?? '') ?? '').toString();
    final body = ((c['body'] ?? '') ?? '').toString();
    final at = DateTime.tryParse(((c['at'] ?? '') ?? '').toString())?.millisecondsSinceEpoch ?? 0;
    final likes = ((c['likes'] as num?) ?? 0).toInt();
    final liked = c['liked'] == true;
    final mine = c['mine'] == true;
    final replies = ((c['replies'] as num?) ?? 0).toInt();
    final id = (c['id'] ?? '').toString();
    final kids = _replies[id];
    return Container(
      margin: EdgeInsets.only(bottom: 8, left: nested ? 16 : 0),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(color: p.bg3, borderRadius: BorderRadius.circular(7)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('@$uname', style: tUi(11, w: FontWeight.w700).copyWith(color: mine ? kPink : p.fg)),
              if (mine) ...[
                const SizedBox(width: 5),
                Text('YOU', style: tMono(8, w: FontWeight.w700).copyWith(color: p.faint)),
              ],
              const Spacer(),
              if (at > 0) Text(timeAgo(at), style: tMono(9).copyWith(color: p.faint)),
            ],
          ),
          const SizedBox(height: 3),
          Text(body, style: tUi(11.5).copyWith(color: p.dim, height: 1.45)),
          const SizedBox(height: 6),
          Row(
            children: [
              GestureDetector(
                onTap: () => _like(c),
                child: Text(
                  liked ? '♥ $likes' : '♡ ${likes == 0 ? '' : likes}',
                  style: tMono(10.5, w: FontWeight.w700).copyWith(color: liked ? const Color(0xFFF2A9C4) : p.faint),
                ),
              ),
              const SizedBox(width: 14),
              GestureDetector(
                onTap: () => _startReply(c),
                child: Text('REPLY', style: tMono(9.5, w: FontWeight.w700).copyWith(color: p.faint, letterSpacing: 0.8)),
              ),
              const Spacer(),
              if (mine)
                GestureDetector(
                  onTap: () => _delete(c),
                  child: Text('DELETE', style: tMono(9.5, w: FontWeight.w700).copyWith(color: p.faint, letterSpacing: 0.8)),
                ),
            ],
          ),
          if (!nested && replies > 0 && kids == null)
            GestureDetector(
              onTap: () => _openReplies(c),
              child: Container(
                margin: const EdgeInsets.only(top: 7),
                child: Text('VIEW $replies ${replies == 1 ? 'REPLY' : 'REPLIES'}',
                    style: tMono(9.5, w: FontWeight.w700).copyWith(color: kPink, letterSpacing: 0.8)),
              ),
            ),
          if (kids != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                children: [for (final k in kids) _tile((k as Map).cast<String, dynamic>(), nested: true)],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final signedIn = Store.user != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.82),
        decoration: BoxDecoration(color: p.bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.bg3))),
              child: Row(
                children: [
                  Text('COMMENTS', style: tMono(11, w: FontWeight.w800).copyWith(color: p.fg, letterSpacing: 1)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(_scopeLabel,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: tMono(9).copyWith(color: p.faint, letterSpacing: 0.8)),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Text('CLOSE', style: tMono(9.5, w: FontWeight.w700).copyWith(color: p.faint, letterSpacing: 0.8)),
                  ),
                ],
              ),
            ),
            Flexible(
              child: _loading
                  ? Center(child: Text('loading comments…', style: tMono(10).copyWith(color: p.faint)))
                  : (_items.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text('No comments here yet — be the first.',
                                style: tUi(11.5).copyWith(color: p.faint)),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                          itemCount: _items.length,
                          itemBuilder: (_, i) => _tile((_items[i] as Map).cast<String, dynamic>()),
                        )),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: p.bg3))),
              child: _replyTo != null
                  ? Row(
                      children: [
                        Expanded(
                          child: Text('Replying to @$_replyToName',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: tMono(10).copyWith(color: kPink)),
                        ),
                        GestureDetector(
                          onTap: () => setState(() {
                            _replyTo = null;
                            _replyToName = null;
                          }),
                          child: Text('CANCEL', style: tMono(9.5, w: FontWeight.w700).copyWith(color: p.faint)),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(14, 0, 14, MediaQuery.of(context).padding.bottom + 12),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: p.bg3))),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      maxLength: 500,
                      style: tUi(12).copyWith(color: p.fg),
                      decoration: InputDecoration(
                        counterText: '',
                        isDense: true,
                        hintText: signedIn ? 'Add a comment…' : 'Sign in to comment',
                        hintStyle: tUi(11.5).copyWith(color: p.faint),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.bg3)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: p.bg3)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _send,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: kRainbow),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: _sending
                          ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : Text('POST', style: tMono(10, w: FontWeight.w800).copyWith(color: Colors.black, letterSpacing: 0.8)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

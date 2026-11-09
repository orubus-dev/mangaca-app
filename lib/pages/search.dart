/* MANGACA search — searches the readable catalog (all lanes, round-robin
   merged) plus the TV & movies catalog, exactly like the web overlay. */

import 'package:flutter/material.dart';
import '../api.dart' as api;
import '../models.dart';
import '../sources.dart';
import '../widgets.dart';
import 'details.dart';
import 'tv_show.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _c = TextEditingController();
  bool _busy = false;
  List<TvItem> _tv = [];
  Map<String, List<BookItem>> _byLabel = {};
  String _query = '';
  int _seq = 0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _run(String q) async {
    if (q.isEmpty) return;
    final seq = ++_seq;
    setState(() {
      _busy = true;
      _query = q;
      _tv = [];
      _byLabel = {};
    });
    List<TvItem> tv = [];
    List<BookItem> results = [];
    try {
      final f1 = api.tvSearchAll(q).catchError((_) => <TvItem>[]);
      final f2 = globalSearch(q, 1).catchError((_) => <BookItem>[]);
      tv = await f1;
      results = await f2;
    } catch (_) {}
    if (!mounted || seq != _seq) return;
    final byLabel = <String, List<BookItem>>{};
    for (final item in results) {
      final label = item.src.isNotEmpty ? item.src : item.sid.toUpperCase();
      (byLabel[label] ??= []).add(item);
    }
    setState(() {
      _tv = tv;
      _byLabel = byLabel;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg2,
        foregroundColor: p.fg,
        elevation: 0,
        titleSpacing: 10,
        title: TextField(
          controller: _c,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: _run,
          style: tUi(14).copyWith(color: p.fg),
          decoration: InputDecoration(
            hintText: 'Search all sources…',
            hintStyle: tUi(13).copyWith(color: p.faint),
            border: InputBorder.none,
            isDense: true,
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close, size: 20, color: p.dim),
          ),
        ],
      ),
      body: _busy
          ? const Center(child: SpinBadge())
          : _query.isEmpty
              ? Center(child: Text('Search manga, novels, classics and TV.',
                  style: tUi(12).copyWith(color: p.faint)))
              : _empty()
                  ? Center(
                      child: Text('Nothing found for “$_query”',
                          style: tUi(12.5).copyWith(color: p.dim)))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
                      children: [
                        if (_tv.isNotEmpty) ...[
                          const SectionTitle('TV & MOVIES'),
                          Rail(
                            children: _tv
                                .take(12)
                                .map((t) => TvRailCard(
                                      item: t,
                                      onTap: () => Navigator.of(context).push(
                                          MaterialPageRoute(builder: (_) => TvShowPage(id: t.id))),
                                    ))
                                .toList(),
                          ),
                        ],
                        for (final e in _byLabel.entries) ...[
                          SectionTitle(e.key),
                          GridView.count(
                            crossAxisCount: 3,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 0.52,
                            children: e.value
                                .take(8)
                                .map((b) => BookCard(
                                      item: b,
                                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                        builder: (_) => DetailsPage(sid: b.sid, bid: b.bid, coverHint: b.cover),
                                      )),
                                    ))
                                .toList(),
                          ),
                        ],
                      ],
                    ),
    );
  }

  bool _empty() => _tv.isEmpty && _byLabel.isEmpty;
}

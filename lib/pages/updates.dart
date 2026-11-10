/* MANGACA updates — new chapters across the library. */

import 'package:flutter/material.dart';
import '../models.dart';
import '../sources.dart';
import '../store.dart';
import '../widgets.dart';
import 'details.dart';

class _UpdRow {
  final Map<String, dynamic> book;
  final Chapter latest;
  final int unread;
  final int total;
  _UpdRow({required this.book, required this.latest, required this.unread, required this.total});
}

class UpdatesPage extends StatefulWidget {
  final VoidCallback onChanged;
  const UpdatesPage({super.key, required this.onChanged});
  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<_UpdRow>? _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = <_UpdRow>[];
    await Future.wait(Store.library.map((b) async {
      final s = sourceById((b['sid'] ?? '') as String);
      if (s == null) return;
      try {
        final chapters = await s.chapters((b['bid'] ?? '') as String);
        if (chapters.isEmpty) return;
        final prog = Store.getProgress((b['sid'] ?? '') as String, (b['bid'] ?? '') as String);
        final unread = prog == null
            ? chapters.length
            : chapters.where((c) => !Store.isRead((b['sid'] ?? '') as String, (b['bid'] ?? '') as String, c.cid)).length;
        rows.add(_UpdRow(book: b, latest: chapters.first, unread: unread, total: chapters.length));
      } catch (_) {}
    }));
    rows.sort((x, y) => y.latest.date.compareTo(x.latest.date));
    if (mounted) setState(() => _rows = rows);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = context.pal;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
      children: [
        const SectionTitle('UPDATES'),
        if (Store.library.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Column(
              children: [
                Icon(Icons.update_outlined, size: 40, color: p.faint),
                const SizedBox(height: 12),
                Text('Add books to your library to track\nnew chapters here.',
                    textAlign: TextAlign.center,
                    style: tUi(12.5).copyWith(color: p.dim, height: 1.6)),
              ],
            ),
          )
        else if (_rows == null)
          const SizedBox(height: 80, child: Center(child: SpinBadge()))
        else if (_rows!.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Center(child: Text('Could not check updates right now.',
                style: tUi(12.5).copyWith(color: p.dim))),
          )
        else
          for (final r in _rows!)
            _row(r),
      ],
    );
  }

  Widget _row(_UpdRow r) {
    final p = context.pal;
    final sid = (r.book['sid'] ?? '') as String;
    final bid = (r.book['bid'] ?? '') as String;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => DetailsPage(sid: sid, bid: bid, coverHint: (r.book['cover'] ?? '') as String, startCid: r.latest.cid),
        )),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: p.bg2,
            border: Border.all(color: p.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 44,
                  height: 62,
                  color: p.bg3,
                  child: ((r.book['cover'] ?? '') as String).isNotEmpty
                      ? SmartCover(url: (r.book['cover'] ?? '') as String, fit: BoxFit.cover)
                      : const SizedBox(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text((r.book['title'] ?? '') as String,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: tUi(12.5, w: FontWeight.w500).copyWith(color: p.fg)),
                    const SizedBox(height: 2),
                    Text('NEW: CH ${r.latest.number > 0 ? r.latest.number : '—'} · ${r.latest.title} · ${r.total} ch total',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: tUi(10.5).copyWith(color: p.faint)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (r.unread > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: kRainbow),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('${r.unread} NEW',
                      style: tMono(9, w: FontWeight.w700).copyWith(color: Colors.black)),
                )
              else
                Text('UP TO DATE', style: tMono(8.5, w: FontWeight.w700).copyWith(color: p.faint)),
            ],
          ),
        ),
      ),
    );
  }
}

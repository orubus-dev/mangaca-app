/* MANGACA history — what you read, grouped by day. */

import 'package:flutter/material.dart';
import '../store.dart';
import '../widgets.dart';
import 'details.dart';

class HistoryPage extends StatefulWidget {
  final VoidCallback onChanged;
  const HistoryPage({super.key, required this.onChanged});
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = context.pal;
    final hist = Store.history;
    final groups = <String, List<dynamic>>{};
    for (final h in hist) {
      final day = DateTime.fromMillisecondsSinceEpoch(h.at).toIso8601String().substring(0, 10);
      (groups[day] ??= []).add(h);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
      children: [
        const SectionTitle('HISTORY'),
        if (hist.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Column(
              children: [
                Icon(Icons.history_outlined, size: 40, color: p.faint),
                const SizedBox(height: 12),
                Text('Nothing read yet.', style: tUi(12.5).copyWith(color: p.dim)),
              ],
            ),
          )
        else
          for (final entry in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 12, 2, 6),
              child: Text(entry.key, style: tMono(10, w: FontWeight.w700).copyWith(color: p.faint, letterSpacing: 1)),
            ),
            for (final h in entry.value)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => DetailsPage(
                        sid: h.sid as String,
                        bid: h.bid as String,
                        coverHint: h.cover,
                        startCid: h.cid),
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
                            child: h.cover.isNotEmpty
                                ? Image.network(h.cover, fit: BoxFit.cover,
                                    headers: const {'User-Agent': 'MANGACA/0.0.1 (Android)'},
                                    errorBuilder: (_, __, ___) => const SizedBox())
                                : const SizedBox(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(h.title,
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: tUi(12.5, w: FontWeight.w500).copyWith(color: p.fg)),
                              const SizedBox(height: 2),
                              Text('CH ${h.ctitle.isNotEmpty ? h.ctitle : h.cid} · ${timeAgo(h.at)}',
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: tUi(10.5).copyWith(color: p.faint)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
      ],
    );
  }
}

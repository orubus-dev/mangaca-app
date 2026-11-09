/* MANGACA library — the user's saved titles with progress badges. */

import 'package:flutter/material.dart';
import '../models.dart';
import '../store.dart';
import '../widgets.dart';
import 'details.dart';

class LibraryPage extends StatefulWidget {
  final VoidCallback onChanged;
  const LibraryPage({super.key, required this.onChanged});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = context.pal;
    final lib = Store.library;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
      children: [
        SectionTitle('LIBRARY — ${lib.length} TITLES'),
        if (lib.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 60),
            child: Column(
              children: [
                Icon(Icons.collections_bookmark_outlined, size: 40, color: p.faint),
                const SizedBox(height: 12),
                Text('Your library is empty.\nBrowse → tap a book → ♡ LIBRARY.',
                    textAlign: TextAlign.center,
                    style: tUi(12.5).copyWith(color: p.dim, height: 1.6)),
              ],
            ),
          )
        else
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.52,
            children: lib.map((b) {
              final sid = (b['sid'] ?? '') as String;
              final bid = (b['bid'] ?? '') as String;
              final prog = Store.getProgress(sid, bid);
              final badge = prog != null && prog.page > 0
                  ? 'P.${prog.page}${prog.total > 0 ? '/${prog.total}' : ''}'
                  : null;
              final item = BookItem.fromMini(b);
              return BookCard(
                item: item,
                badge: badge,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => DetailsPage(sid: sid, bid: bid, coverHint: item.cover),
                )),
              );
            }).toList(),
          ),
      ],
    );
  }
}

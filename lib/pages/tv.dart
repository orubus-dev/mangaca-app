/* MANGACA TV — the top-bar tab inside the home tab. Rows from the runtime's
   hidden provider layer (GLOBAL catalogs + VAULT), show pages with episode
   lists, playback via the gesture player (VAULT) or the partner WebView
   (GLOBAL). All requests ride the user's own connection. */

import 'package:flutter/material.dart';
import '../api.dart' as api;
import '../models.dart';
import '../widgets.dart';
import 'tv_show.dart';

class TvPage extends StatefulWidget {
  final ValueChanged<String> onSection;
  const TvPage({super.key, required this.onSection});
  @override
  State<TvPage> createState() => _TvPageState();
}

class _TvPageState extends State<TvPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  static const rows = <(String, String)>[
    ('cm:series:top', 'TRENDING SERIES'),
    ('cm:airing', 'AIRING TODAY'),
    ('cm:movie:top', 'POPULAR MOVIES'),
    ('cm:movie:bestrated', 'TOP RATED MOVIES'),
    ('cm:series:new', 'NEW SERIES'),
    ('vault:all', 'MANGACA VAULT — FULL FILMS IN 2K'),
  ];

  void openShow(TvItem it) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => TvShowPage(id: it.id)));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = context.pal;
    return Column(
      children: [
        // same tab rail as Browse — TV active
        Container(
          decoration: BoxDecoration(color: p.bg, border: Border(bottom: BorderSide(color: p.line))),
          child: Row(
            children: [
              _tab('foryou', 'FOR YOU'),
              _tab('popular', 'POPULAR'),
              _tab('latest', 'LATEST'),
              _tabActive('tv'),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
            children: [
              const SectionTitle('TV & MOVIES'),
              Text(
                'Series and films, streamed right here on your own connection. Tap any poster, pick an episode, press play.',
                style: tUi(12).copyWith(color: p.dim, height: 1.5),
              ),
              const SizedBox(height: 4),
              for (final (id, title) in rows)
                _Row(key: ValueKey(id), title: title, rowId: id, onTap: openShow),
              const SizedBox(height: 26),
              Center(
                child: Text('MANGACA TV · READ BEYOND THE ILLUSION',
                    style: tMono(9).copyWith(color: p.faint, letterSpacing: 1)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tab(String id, String label) {
    final p = context.pal;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.onSection(id),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Text(label, style: tUi(11.5, w: FontWeight.w700).copyWith(color: p.faint, letterSpacing: 0.6)),
            const SizedBox(height: 8),
            Container(height: 2.5, color: Colors.transparent),
          ],
        ),
      ),
    );
  }

  Widget _tabActive(String label) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Text(label.toUpperCase(),
              style: tUi(11.5, w: FontWeight.w700)
                  .copyWith(color: context.pal.fg, letterSpacing: 0.6)),
          const SizedBox(height: 8),
          Container(height: 2.5, decoration: const BoxDecoration(gradient: LinearGradient(colors: kRainbow))),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String title;
  final String rowId;
  final ValueChanged<TvItem> onTap;
  const _Row({super.key, required this.title, required this.rowId, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(title),
        FutureBuilder<List<TvItem>>(
          future: api.tvRow(rowId),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(height: 60, child: Center(child: SpinBadge()));
            }
            final items = snap.data ?? const <TvItem>[];
            if (items.isEmpty) {
              return Text('row unavailable right now', style: tMono(10).copyWith(color: p.faint));
            }
            return SizedBox(
              height: 205,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => TvRailCard(item: items[i], onTap: () => onTap(items[i])),
              ),
            );
          },
        ),
      ],
    );
  }
}

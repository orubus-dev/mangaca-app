/* MANGACA TV show page — poster hero, meta chips, episode list.
   Tapping an episode opens the right player lane:
   • cm:play:*  → partner WebView player (SERVER 1/2/3 chips)
   • vault:*    → native gesture player (double-tap seek, hold speed, quality) */

import 'package:flutter/material.dart';
import '../api.dart' as api;
import '../models.dart';
import '../widgets.dart';
import '../player/embed_player.dart';
import '../player/vault_player.dart';

class TvShowPage extends StatefulWidget {
  final String id;
  const TvShowPage({super.key, required this.id});
  @override
  State<TvShowPage> createState() => _TvShowPageState();
}

class _TvShowPageState extends State<TvShowPage> {
  late Future<TvShow?> _future;

  @override
  void initState() {
    super.initState();
    _future = api.tvShow(widget.id);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      backgroundColor: p.bg,
      body: FutureBuilder<TvShow?>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: SpinBadge());
          }
          final show = snap.data;
          if (show == null) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_circle_outline, size: 42, color: p.faint),
                  const SizedBox(height: 10),
                  Text('Show not found.', style: tUi(13).copyWith(color: p.dim)),
                ],
              ),
            );
          }
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                backgroundColor: p.bg,
                foregroundColor: p.fg,
                elevation: 0,
                pinned: true,
                title: Text(show.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: tDisplay(13).copyWith(color: p.fg)),
              ),
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _hero(show),
                    if (show.description.isNotEmpty) ...[
                      const SectionTitle('ABOUT'),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                        child: Text(show.description,
                            style: tUi(12.5).copyWith(color: p.dim, height: 1.6)),
                      ),
                    ],
                    const SectionTitle('EPISODES'),
                    for (final ep in show.episodes)
                      _EpisodeRow(show: show, ep: ep),
                    const SizedBox(height: 26),
                    Center(
                      child: Text('MANGACA TV · READ BEYOND THE ILLUSION',
                          style: tMono(9).copyWith(color: p.faint, letterSpacing: 1)),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _hero(TvShow show) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 120,
              height: 172,
              color: p.bg3,
              child: show.poster.isNotEmpty
                  ? Image.network(show.poster, fit: BoxFit.cover,
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
                Text(show.title, style: tDisplay(17).copyWith(color: p.fg, height: 1.2)),
                if (show.tagline.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(show.tagline, style: tUi(12).copyWith(color: p.dim)),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    InfoChip(show.kind.toUpperCase()),
                    InfoChip('${show.episodes.length} EP'),
                    InfoChip('HD STREAM'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  final TvShow show;
  final Episode ep;
  const _EpisodeRow({required this.show, required this.ep});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: GestureDetector(
        onTap: () {
          if (ep.isPartnerLane) {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => EmbedPlayerPage(show: show, episode: ep),
            ));
          } else {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => VaultPlayerPage(show: show, episode: ep),
            ));
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: p.bg2,
            border: Border.all(color: p.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.play_arrow, size: 18, color: p.dim),
              const SizedBox(width: 8),
              Expanded(
                child: Text(ep.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tUi(12.5, w: FontWeight.w500).copyWith(color: p.fg)),
              ),
              Text(
                [ep.duration, ep.quality].where((s) => s.isNotEmpty).join(' · '),
                style: tMono(10).copyWith(color: p.faint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

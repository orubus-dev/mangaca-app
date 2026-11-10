/* MANGACA widgets.dart — shared UI kit. Liquid glass × monochrome brutalism,
   rainbow accent. Same look as the web app (Mihon-style). */

import 'package:flutter/material.dart';
import 'models.dart';

/* ---------- palette (same tokens as style.css) ---------- */
const kBgDark = Color(0xFF0A0A0B);
const kBg2Dark = Color(0xFF121214);
const kBg3Dark = Color(0xFF1A1A1D);
const kFgDark = Color(0xFFF2F2F0);
const kDimDark = Color(0xFFA2A2AB);
const kFaintDark = Color(0xFF6C6C75);
const kLineDark = Color(0xFF26262B);
const kLineHardDark = Color(0xFF3A3A41);

const kBgLight = Color(0xFFF2F2EF);
const kBg2Light = Color(0xFFFFFFFF);
const kBg3Light = Color(0xFFE8E8E3);
const kFgLight = Color(0xFF101012);
const kDimLight = Color(0xFF55555E);
const kFaintLight = Color(0xFF8A8A94);
const kLineLight = Color(0xFFD5D5CF);
const kLineHardLight = Color(0xFF101012);

const kRainbow = <Color>[
  Color(0xFFFF5A5A),
  Color(0xFFFFB84D),
  Color(0xFFFFE75A),
  Color(0xFF57E389),
  Color(0xFF4DC3FF),
  Color(0xFFB877FF),
];

class Palette {
  final bool dark;
  const Palette(this.dark);
  Color get bg => dark ? kBgDark : kBgLight;
  Color get bg2 => dark ? kBg2Dark : kBg2Light;
  Color get bg3 => dark ? kBg3Dark : kBg3Light;
  Color get fg => dark ? kFgDark : kFgLight;
  Color get dim => dark ? kDimDark : kDimLight;
  Color get faint => dark ? kFaintDark : kFaintLight;
  Color get line => dark ? kLineDark : kLineLight;
  Color get lineHard => dark ? kLineHardDark : kLineHardLight;
  Color get glass => dark ? Colors.white.withOpacity(0.05) : Colors.white.withOpacity(0.66);
  LinearGradient get rainbow => const LinearGradient(colors: kRainbow);
}

/* ---------- text styles ---------- */
TextStyle tDisplay(double size) => TextStyle(
      fontFamily: 'ArchivoBlack',
      fontSize: size,
      letterSpacing: 1.2,
      color: null,
    );
TextStyle tUi(double size, {FontWeight w = FontWeight.w400}) =>
    TextStyle(fontFamily: 'SpaceGrotesk', fontSize: size, fontWeight: w);
TextStyle tMono(double size, {FontWeight w = FontWeight.w400}) =>
    TextStyle(fontFamily: 'IBMPlexMono', fontSize: size, fontWeight: w);

/* ---------- rainbow widgets ---------- */
class RainbowLine extends StatelessWidget {
  final double height;
  const RainbowLine({super.key, this.height = 2.5});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: const BoxDecoration(gradient: LinearGradient(colors: kRainbow)),
    );
  }
}

class RainbowEdgeButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  const RainbowEdgeButton({super.key, required this.label, this.onTap, this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12)});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Opacity(
      opacity: onTap == null ? 0.6 : 1,
      child: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(colors: kRainbow)),
        padding: const EdgeInsets.all(1.5),
        child: Material(
          color: p.fg,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: padding,
              child: Center(
                child: Text(label, style: tUi(12, w: FontWeight.w700).copyWith(color: p.bg, letterSpacing: 0.8)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ---------- chips ---------- */
class MChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback? onTap;
  const MChip(this.label, {super.key, this.on = false, this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: on ? p.fg : Colors.transparent,
          border: Border.all(color: on ? p.fg : p.lineHard, width: 1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: tMono(10.5, w: FontWeight.w700).copyWith(color: on ? p.bg : p.dim),
        ),
      ),
    );
  }
}

class InfoChip extends StatelessWidget {
  final String label;
  const InfoChip(this.label, {super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: p.lineHard, width: 1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: tMono(9.5, w: FontWeight.w500).copyWith(color: p.dim, letterSpacing: 0.4)),
    );
  }
}

/* ---------- spinner badge (same look as .spin-badge) ---------- */
class SpinBadge extends StatefulWidget {
  const SpinBadge({super.key});
  @override
  State<SpinBadge> createState() => _SpinBadgeState();
}

class _SpinBadgeState extends State<SpinBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  @override
  void initState() {
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
    super.initState();
  }
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return RotationTransition(
      turns: _c,
      child: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: p.faint, width: 2),
        ),
        child: const SizedBox(),
      ),
    );
  }
}

/* ---------- book card (browse grid) ---------- */
/* deterministic pastel from the title — every no-cover state still looks
   like a card, never like a broken image */
const kLetterHues = [
  Color(0xFF3D2C3E), Color(0xFF2C3A3E), Color(0xFF3E2C2C),
  Color(0xFF2C3E2F), Color(0xFF2E2C3E), Color(0xFF3E3A2C),
];

class LetterCover extends StatelessWidget {
  final String title;
  final String? label;
  const LetterCover({super.key, required this.title, this.label});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final t = title.trim().isEmpty ? '?' : title.trim();
    final hue = kLetterHues[t.codeUnitAt(0) % kLetterHues.length];
    return Container(
      color: hue,
      alignment: Alignment.center,
      child: Text(
        t.substring(0, 1).toUpperCase(),
        style: tDisplay(30).copyWith(color: p.fg.withOpacity(0.85)),
      ),
    );
  }
}

/* ---------- smart cover ----------
   One widget, every cover host: tries the given URL first (our /api/img
   proxy lane), and if that fails flips to the DIRECT original host — some
   cover CDNs (novelbuddy's rs. host) aren't on the proxy allowlist but
   serve fine from a real device; others (chikari) block devices and need
   the proxy. The letter card underneath means a cover can never render as
   a broken-image glyph — worst case is a clean letter tile. */
class SmartCover extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final Map<String, String> headers;
  const SmartCover({super.key, required this.url, this.fit = BoxFit.cover, this.headers = const {}});
  @override
  State<SmartCover> createState() => _SmartCoverState();
}

class _SmartCoverState extends State<SmartCover> {
  late List<String> _candidates;
  int _idx = 0;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _candidates = _candidatesFor(widget.url);
  }

  @override
  void didUpdateWidget(covariant SmartCover old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _candidates = _candidatesFor(widget.url);
      _idx = 0;
      _gen++;
    }
  }

  static List<String> _candidatesFor(String url) {
    if (url.isEmpty) return const [];
    const base = 'https://mangaca.pages.dev';
    const marker = '/api/img?u=';
    if (url.contains(marker)) {
      // proxied cover — the direct original is the fallback
      final raw = url.substring(url.indexOf(marker) + marker.length);
      final inner = Uri.decodeComponent(raw);
      return (inner.isNotEmpty && inner != url) ? [url, inner] : [url];
    }
    if (url.startsWith('http')) {
      // direct cover — the runtime proxy is the fallback
      return [url, '$base/api/img?u=${Uri.encodeComponent(url)}'];
    }
    if (url.startsWith('/')) return ['$base$url'];
    return [url];
  }

  @override
  Widget build(BuildContext context) {
    if (_idx >= _candidates.length) return const SizedBox(); // letter tile shows through
    final gen = _gen;
    return Image.network(
      _candidates[_idx],
      fit: widget.fit,
      headers: widget.headers.isEmpty
          ? const {'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36 MANGACA/0.0.3'}
          : widget.headers,
      errorBuilder: (_, __, ___) {
        if (gen == _gen && _idx < _candidates.length - 1) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || gen != _gen) return;
            setState(() => _idx += 1);
          });
        }
        return const SizedBox();
      },
    );
  }
}

class BookCard extends StatelessWidget {
  final BookItem item;
  final VoidCallback onTap;
  final String? badge;
  const BookCard({super.key, required this.item, required this.onTap, this.badge});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          color: p.bg3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              LetterCover(title: item.title),
              if (item.cover.isNotEmpty)
                SmartCover(url: item.cover, fit: BoxFit.cover),
              Positioned(
                top: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: kRainbow),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    (item.src.isNotEmpty ? item.src : item.sid.toUpperCase()),
                    style: tMono(8.5, w: FontWeight.w700).copyWith(color: Colors.black),
                  ),
                ),
              ),
              if (badge != null)
                Positioned(
                  bottom: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    color: Colors.black.withOpacity(0.72),
                    child: Text(badge!, style: tMono(9.5, w: FontWeight.w700).copyWith(color: Colors.white)),
                  ),
                ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(8, 18, 8, 7),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xE6000000)],
                    ),
                  ),
                  child: Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tUi(11.5, w: FontWeight.w500).copyWith(color: Colors.white, height: 1.25),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------- rail card ---------- */
class RailCard extends StatelessWidget {
  final String cover, title, sub;
  final VoidCallback onTap;
  final String? chip;
  const RailCard({super.key, required this.cover, required this.title, required this.sub, required this.onTap, this.chip});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 110,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: 110,
                    height: 158,
                    color: p.bg3,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        LetterCover(title: title),
                        if (cover.isNotEmpty) SmartCover(url: cover, fit: BoxFit.cover),
                      ],
                    ),
                  ),
                ),
                if (chip != null)
                  Positioned(
                    bottom: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: kRainbow),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(chip!, style: tMono(8.5, w: FontWeight.w700).copyWith(color: Colors.black)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tUi(11.5, w: FontWeight.w500).copyWith(color: p.fg, height: 1.2)),
            if (sub.isNotEmpty)
              Text(sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tUi(10).copyWith(color: p.faint)),
          ],
        ),
      ),
    );
  }
}

/* ---------- TV rail card ---------- */
class TvRailCard extends StatelessWidget {
  final TvItem item;
  final VoidCallback onTap;
  const TvRailCard({super.key, required this.item, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final sub = [item.tagline, item.kind.toUpperCase()].where((s) => s.isNotEmpty).join(' · ');
    return RailCard(cover: item.poster, title: item.title, sub: sub, onTap: onTap);
  }
}

/* ---------- section title ---------- */
class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 20, 2, 8),
      child: Text(text, style: tDisplay(12.5).copyWith(color: p.fg, letterSpacing: 1.4)),
    );
  }
}

/* ---------- rail ---------- */
class Rail extends StatelessWidget {
  final List<Widget> children;
  const Rail({super.key, required this.children});
  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      final p = context.pal;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('unavailable right now', style: tMono(10).copyWith(color: p.faint)),
      );
    }
    return SizedBox(
      height: 205,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: children.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) => children[i],
      ),
    );
  }
}

/* ---------- bottom sheet shell (glass, grab + rainbow) ---------- */
Future<T?> showMSheet<T>(BuildContext context, {required WidgetBuilder builder}) {
  final p = context.pal;
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Container(
      decoration: BoxDecoration(
        color: p.bg2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        border: Border(top: BorderSide(color: p.lineHard, width: 1)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 10,
          bottom: 18 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: builder(ctx),
      ),
    ),
  );
}

class SheetGrab extends StatelessWidget {
  const SheetGrab({super.key});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 26,
        height: 2.5,
        margin: const EdgeInsets.only(bottom: 10),
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: kRainbow),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(3)),
        ),
      ),
    );
  }
}

/* ---------- toasts ---------- */
void toast(BuildContext context, String msg, {bool err = false}) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  final p = context.pal;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg, style: tUi(12).copyWith(color: p.fg)),
      backgroundColor: err ? const Color(0xFF2B1214) : p.bg3,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(milliseconds: 2200),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: err ? const Color(0xFFFF5A5A) : p.lineHard),
      ),
    ),
  );
}

/* ---------- misc ---------- */
String timeAgo(int ts) {
  final d = DateTime.now().millisecondsSinceEpoch - ts;
  if (d < 60000) return 'just now';
  if (d < 3600000) return '${(d / 60000).floor()}m ago';
  if (d < 86400000) return '${(d / 3600000).floor()}h ago';
  return '${(d / 86400000).floor()}d ago';
}

/* ---------- palette accessor ---------- */
Palette paletteOf(BuildContext context) =>
    Palette(Theme.of(context).brightness != Brightness.light);

extension CtxPal on BuildContext {
  Palette get pal => paletteOf(this);
}

/* ---------- shared helpers ---------- */
extension FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}

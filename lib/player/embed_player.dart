/* MANGACA embed player — GLOBAL-lane titles stream through partner players
   loaded in an in-app WebView. The WebView runs on the user's own device and
   connection (their IP, never a datacenter) — that is the whole point of this
   lane. One tap switches delivery partner if one is misbehaving. */

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../api.dart' as api;
import '../models.dart';
import '../widgets.dart';

class EmbedPlayerPage extends StatefulWidget {
  final TvShow show;
  final Episode episode;
  const EmbedPlayerPage({super.key, required this.show, required this.episode});
  @override
  State<EmbedPlayerPage> createState() => _EmbedPlayerPageState();
}

class _EmbedPlayerPageState extends State<EmbedPlayerPage> {
  late final WebViewController _controller;
  List<Mirror> _mirrors = [];
  int _mirrorIdx = -1;
  bool _loading = true;
  String? _fail;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setMediaPlaybackRequiresUserGesture(false)
      ..setBackgroundColor(const Color(0xFF000000))
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (_) => setState(() => _loading = false),
      ));
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final play = await api.tvQualities(widget.episode.id);
      if (play == null || play.mirrors.isEmpty) {
        setState(() { _loading = false; _fail = 'This title has no stream right now — try another.'; });
        return;
      }
      setState(() => _mirrors = play.mirrors);
      mount(0);
    } catch (_) {
      setState(() { _loading = false; _fail = 'Could not open this stream — go back and try another.'; });
    }
  }

  void mount(int i) {
    if (i >= _mirrors.length) return;
    setState(() {
      _mirrorIdx = i;
      _loading = true;
      _fail = null;
    });
    final url = _mirrors[i].url;
    _controller.loadRequest(Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // top bar over the stage
            Container(
              color: Colors.black,
              padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.show.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: tUi(12, w: FontWeight.w700).copyWith(color: Colors.white)),
                        Text(widget.episode.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: tUi(10.5).copyWith(color: Colors.white70)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // stage
            Expanded(
              child: Stack(
                children: [
                  const SizedBox.expand(),
                  WebViewWidget(controller: _controller),
                  if (_loading && _fail == null)
                    const Center(child: SpinBadge()),
                  if (_fail != null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_fail!,
                            textAlign: TextAlign.center,
                            style: tUi(12.5).copyWith(color: const Color(0xFF9A9AA4), height: 1.6)),
                      ),
                    ),
                ],
              ),
            ),
            // server chips
            Container(
              width: double.infinity,
              color: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Wrap(
                spacing: 6,
                children: [
                  for (var i = 0; i < _mirrors.length; i++)
                    _serverChip(i),
                ],
              ),
            ),
            // meta
            Container(
              width: double.infinity,
              color: p.bg,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${widget.show.title} — ${widget.episode.title}',
                      style: tUi(12.5, w: FontWeight.w700).copyWith(color: p.fg)),
                  if (widget.show.description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(widget.show.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: tUi(11).copyWith(color: p.dim, height: 1.5)),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      InfoChip(widget.show.kind.toUpperCase()),
                      InfoChip('HD STREAM'),
                      InfoChip('SERVER 1/2/3 SWITCH'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _serverChip(int i) {
    final m = _mirrors[i];
    final on = i == _mirrorIdx;
    return GestureDetector(
      onTap: () { if (i != _mirrorIdx) { toast(context, 'Switching to ${m.label}'); mount(i); } },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: on ? Colors.white : Colors.transparent,
          border: Border.all(color: on ? Colors.white : const Color(0xFF3A3A41)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(m.label,
            style: tMono(10, w: FontWeight.w700).copyWith(color: on ? Colors.black : Colors.white70)),
      ),
    );
  }
}

/* MANGACA vault player — the full custom gesture player for our own film
   library (mp4/HLS through the signed stream proxy). Ported 1:1 from the web
   tvplayer: tap toggles controls, double-tap L/R seeks with ripples, holding
   temporary ×speed, real quality menu, speed menu, fullscreen (landscape).
   Plays via ExoPlayer (video_player) straight from the user's connection. */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../api.dart' as api;
import '../models.dart';
import '../store.dart';
import '../widgets.dart';

const _qualRank = {'4K': 2160, '2K': 1440, '1080P': 1080, '720P': 720, '480P': 480, '360P': 360};

class VaultPlayerPage extends StatefulWidget {
  final TvShow show;
  final Episode episode;
  const VaultPlayerPage({super.key, required this.show, required this.episode});
  @override
  State<VaultPlayerPage> createState() => _VaultPlayerPageState();
}

class _VaultPlayerPageState extends State<VaultPlayerPage> {
  VideoPlayerController? _vc;
  List<Quality> _qualities = [];
  List<SubtitleTrack> _subs = [];
  String _currentLabel = '';
  bool _controlsOn = true;
  bool _loading = true;
  bool _holding = false;
  Duration _position = Duration.zero;
  Duration _duration = const Duration(seconds: 1);
  Duration _buffered = Duration.zero;
  int _hideTimer = 0;
  DateTime _lastTap = DateTime.fromMillisecondsSinceEpoch(0);

  TvPrefs get tv => Store.settings.tv;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      final play = await api.tvQualities(widget.episode.id);
      _qualities = play?.qualities ?? const [];
      _subs = play?.subtitles ?? const [];
    } catch (_) {}
    String? label;
    if (_qualities.isNotEmpty) {
      final sorted = [..._qualities]
        ..sort((a, b) => (_qualRank[b.label] ?? 0).compareTo(_qualRank[a.label] ?? 0));
      label = sorted.first.label;
      _currentLabel = label;
    }
    await _attach(api.tvStreamUrl(widget.episode.id, label), Duration.zero);
  }

  Future<void> _attach(String url, Duration resumeAt) async {
    setState(() => _loading = true);
    final old = _vc;
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _vc = controller;
    await old?.dispose();
    try {
      await controller.initialize();
      if (!mounted || _vc != controller) {
        await controller.dispose();
        return;
      }
      if (resumeAt > Duration.zero) await controller.seekTo(resumeAt);
      await controller.setLooping(false);
      await controller.setPlaybackSpeed(_holding ? tv.holdSpeed.toDouble() : tv.speed.toDouble());
      await controller.play();
      controller.addListener(() {
        if (!mounted || _vc != controller) return;
        setState(() {
          _position = controller.value.position;
          _duration = controller.value.duration;
          if (controller.value.buffered.isNotEmpty) {
            _buffered = controller.value.buffered.last.end;
          }
          _loading = controller.value.isBuffering;
        });
      });
      setState(() => _loading = false);
      _showControls();
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        toast(context, 'Stream hiccup — tap play to retry', err: true);
      }
    }
  }

  void _showControls() {
    setState(() => _controlsOn = true);
    _hideTimer++;
    final token = _hideTimer;
    Future.delayed(const Duration(milliseconds: 3200), () {
      if (!mounted || token != _hideTimer) return;
      if (!(_vc?.value.isPlaying ?? false)) return;
      setState(() => _controlsOn = false);
    });
  }

  void _togglePlay() {
    final c = _vc;
    if (c == null) return;
    if (c.value.isPlaying) {
      c.pause();
    } else {
      c.play();
    }
    _showControls();
  }

  void _seekBy(int delta) {
    final c = _vc;
    if (c == null || _duration <= Duration.zero) return;
    var target = c.value.position + Duration(seconds: delta);
    if (target < Duration.zero) target = Duration.zero;
    if (target > _duration) target = _duration;
    c.seekTo(target);
    _showControls();
  }

  Future<void> _cycleQuality() async {
    if (_qualities.length < 2) {
      toast(context, _qualities.isNotEmpty ? 'Only ${_qualities.first.label} is served for this title' : 'Quality info not available yet');
      return;
    }
    final idx = _qualities.indexWhere((q) => q.label == _currentLabel);
    final next = _qualities[(idx + 1) % _qualities.length];
    final resumeAt = _vc?.value.position ?? Duration.zero;
    setState(() => _currentLabel = next.label);
    await _attach(api.tvStreamUrl(widget.episode.id, next.label), resumeAt);
    if (mounted) toast(context, 'Quality ${next.label}');
  }

  void _cycleSpeed() {
    final c = _vc;
    if (c == null) return;
    const rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final cur = c.value.playbackSpeed;
    var idx = rates.indexWhere((r) => (r - cur).abs() < 0.01);
    final next = rates[(idx + 1) % rates.length];
    c.setPlaybackSpeed(next);
    Store.settings.tv.speed = next;
    Store.saveSettings();
    _showControls();
    toast(context, 'Speed $next×');
  }

  Future<void> _toggleFullscreen() async {
    final landscape = MediaQuery.of(context).orientation == Orientation.portrait;
    if (landscape) {
      await SystemChromeLandscape.lock();
    } else {
      await SystemChromeLandscape.unlock();
    }
  }

  String _fmt(Duration d) {
    final s = d.inSeconds.clamp(0, 359999);
    final m = (s ~/ 60), r = s % 60;
    if (m >= 60) return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
    return '$m:${r.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    SystemChromeLandscape.unlockQuiet();
    _vc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final c = _vc;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: OrientationBuilder(builder: (context, orientation) {
          final landscape = orientation == Orientation.landscape;
          return Column(
            children: [
              // stage
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (_) {},
                  onTap: () {
                    final now = DateTime.now();
                    if (now.difference(_lastTap).inMilliseconds < 300) {
                      // handled by double tap below
                    }
                    _lastTap = now;
                    _showControls();
                  },
                  onDoubleTap: () {},
                  onDoubleTapDown: (details) {
                    final w = MediaQuery.of(context).size.width;
                    final x = details.localPosition.dx;
                    final zone = x < w * 0.4 ? 'L' : x > w * 0.6 ? 'R' : 'C';
                    _seekBy(zone == 'L' ? -tv.seekSeconds : tv.seekSeconds);
                    toast(context, zone == 'L' ? '−${tv.seekSeconds}s' : '+${tv.seekSeconds}s');
                  },
                  onLongPressStart: (_) {
                    _holding = true;
                    _vc?.setPlaybackSpeed(tv.holdSpeed.toDouble());
                    _showControls();
                    toast(context, '»${tv.holdSpeed}×');
                  },
                  onLongPressEnd: (_) {
                    _holding = false;
                    _vc?.setPlaybackSpeed(tv.speed.toDouble());
                  },
                  child: Container(
                    color: Colors.black,
                    alignment: Alignment.center,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (c != null && c.value.isInitialized)
                          AspectRatio(
                            aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
                            child: VideoPlayer(c),
                          )
                        else
                          const SizedBox.expand(),
                        if (_loading) const SpinBadge(),
                        if (_controlsOn) _stageControls(c),
                      ],
                    ),
                  ),
                ),
              ),
              if (!landscape) ...[
                // server-less meta block below the stage (same as the web player)
                Container(
                  width: double.infinity,
                  color: p.bg,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${widget.show.title} — ${widget.episode.title}',
                          style: tUi(12.5, w: FontWeight.w700).copyWith(color: p.fg)),
                      if (widget.show.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(widget.show.description,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: tUi(11).copyWith(color: p.dim, height: 1.5)),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          InfoChip(widget.show.kind.toUpperCase()),
                          InfoChip(_currentLabel.isEmpty ? 'HD STREAM' : _currentLabel),
                          InfoChip('DOUBLE-TAP ±${tv.seekSeconds}s'),
                          InfoChip('HOLD ×${tv.holdSpeed}'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        }),
      ),
    );
  }

  Widget _stageControls(VideoPlayerController? c) {
    final playing = c?.value.isPlaying ?? false;
    return SizedBox.expand(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // top
          Container(
            padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
            decoration: const BoxDecoration(color: Colors.black38),
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
          // center play
          Center(
            child: GestureDetector(
              onTap: _togglePlay,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24),
                ),
                child: Icon(playing ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 30),
              ),
            ),
          ),
          // bottom controls
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            decoration: const BoxDecoration(color: Colors.black38),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(_fmt(_position), style: tMono(10).copyWith(color: Colors.white)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                        ),
                        child: Slider(
                          value: _position.inMilliseconds
                              .clamp(0, _duration.inMilliseconds <= 0 ? 0 : _duration.inMilliseconds)
                              .toDouble(),
                          max: (_duration.inMilliseconds <= 0 ? 1 : _duration.inMilliseconds).toDouble(),
                          onChanged: (v) {
                            final t = Duration(milliseconds: v.toInt());
                            _vc?.seekTo(t);
                            setState(() => _position = t);
                            _showControls();
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_fmt(_duration), style: tMono(10).copyWith(color: Colors.white)),
                  ],
                ),
                Row(
                  children: [
                    _pbtn('↺ ${tv.seekSeconds}s', () => _seekBy(-tv.seekSeconds)),
                    const SizedBox(width: 6),
                    _pbtn('${tv.seekSeconds}s ↻', () => _seekBy(tv.seekSeconds)),
                    const Spacer(),
                    _pbtn('${_vc?.value.playbackSpeed.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '') ?? '1'}×', _cycleSpeed),
                    const SizedBox(width: 6),
                    _pbtn(_currentLabel.isEmpty ? '…' : _currentLabel, _cycleQuality),
                    const SizedBox(width: 6),
                    _pbtn('⛶', _toggleFullscreen),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pbtn(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: tMono(10, w: FontWeight.w700).copyWith(color: Colors.white)),
      ),
    );
  }
}

/* ---------- orientation helpers ---------- */
class SystemChromeLandscape {
  static Future<void> lock() async {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  static Future<void> unlock() async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  static void unlockQuiet() {
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }
}

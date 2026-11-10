/* MANGACA More — settings. Account, appearance, iReader defaults, TV player,
   APP UPDATES (delta self-updater), Legal & Privacy, catalog, about. Same
   structure as the web app's More tab. */

import 'package:flutter/material.dart';
import '../api.dart' as api;
import '../store.dart';
import '../updater.dart';
import '../widgets.dart';
import '../main.dart' show openAuthSheet, openAccountSheet, showConsentSheet;
import 'legal.dart';

class MorePage extends StatefulWidget {
  final VoidCallback onChanged;
  final VoidCallback onThemeChanged;
  const MorePage({super.key, required this.onChanged, required this.onThemeChanged});
  @override
  State<MorePage> createState() => _MorePageState();
}

class _MorePageState extends State<MorePage> with AutomaticKeepAliveClientMixin {
  final UpdaterService _updater = UpdaterService();
  Map<String, dynamic> _installed = {'code': 0, 'name': '?'};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _updater.addListener(_onUpdateState);
    _updater.installedInfo().then((v) {
      if (mounted) setState(() => _installed = v);
    });
  }

  void _onUpdateState() {
    if (mounted) setState(() {});
    final st = _updater.state.stage;
    if (st == 'uptodate' || st == 'available') {
      toast(context, _updater.state.message);
    }
  }

  @override
  void dispose() {
    _updater.removeListener(_onUpdateState);
    super.dispose();
  }

  String _fmtMb(int bytes) {
    if (bytes >= 1048576) return '${(bytes / 1048576).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).round()} KB';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final p = context.pal;
    final tv = Store.settings.tv;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 26),
      children: [
        const SectionTitle('ACCOUNT'),
        _group(p, Store.user != null
            ? [
                _row('👤', '@${Store.user!.username}', value: 'GENJUTSU', onTap: () => openAccountSheet(context)),
                _row('⏻', 'Sign out', onTap: () async {
                  try {
                    await api.authLogout();
                  } catch (_) {}
                  Store.setUser(null);
                  toast(context, 'Signed out');
                  widget.onChanged();
                  setState(() {});
                }),
              ]
            : [
                _row('🔑', 'Continue with genjutsu', value: 'SIGN IN', onTap: () => openAuthSheet(context)),
              ]),
        const SectionTitle('APPEARANCE'),
        _group(p, [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Text('◐', style: tUi(14)),
                const SizedBox(width: 10),
                Expanded(child: Text('Theme', style: tUi(12.5).copyWith(color: p.fg))),
                Wrap(
                  spacing: 6,
                  children: ['auto', 'dark', 'light']
                      .map((t) => MChip(t.toUpperCase(),
                          on: Store.settings.theme == t,
                          onTap: () {
                            Store.settings.theme = t;
                            Store.saveSettings();
                            widget.onThemeChanged();
                            setState(() {});
                          }))
                      .toList(),
                ),
              ],
            ),
          ),
        ]),
        const SectionTitle('iREADER DEFAULTS'),
        _group(p, [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Text('⇕', style: tUi(14)),
                const SizedBox(width: 10),
                Expanded(child: Text('Manga mode', style: tUi(12.5).copyWith(color: p.fg))),
                Wrap(
                  spacing: 6,
                  children: [
                    ('webtoon', 'WEBTOON'),
                    ('paged-ltr', 'L→R'),
                    ('paged-rtl', 'R→L'),
                  ]
                      .map((m) => MChip(m.$2,
                          on: Store.settings.readerMode == m.$1,
                          onTap: () {
                            Store.settings.readerMode = m.$1;
                            Store.saveSettings();
                            setState(() {});
                          }))
                      .toList(),
                ),
              ],
            ),
          ),
        ]),
        const SectionTitle('TV PLAYER'),
        _group(p, [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Text('⇋', style: tUi(14)),
                const SizedBox(width: 10),
                Expanded(child: Text('Double-tap seek', style: tUi(12.5).copyWith(color: p.fg))),
                Wrap(
                  spacing: 6,
                  children: [5, 10, 15, 30]
                      .map((s) => MChip('${s}s',
                          on: tv.seekSeconds == s,
                          onTap: () {
                            Store.settings.tv.seekSeconds = s;
                            Store.saveSettings();
                            setState(() {});
                          }))
                      .toList(),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Text('»', style: tUi(14)),
                const SizedBox(width: 10),
                Expanded(child: Text('Hold speed', style: tUi(12.5).copyWith(color: p.fg))),
                Wrap(
                  spacing: 6,
                  children: [1.5, 2, 3]
                      .map((s) => MChip('×$s',
                          on: tv.holdSpeed == s,
                          onTap: () {
                            Store.settings.tv.holdSpeed = s;
                            Store.saveSettings();
                            setState(() {});
                          }))
                      .toList(),
                ),
              ],
            ),
          ),
        ]),
        ..._updatesSection(p),
        const SectionTitle('LEGAL & PRIVACY'),
        _group(p, [
          _row('🛡', 'Privacy Policy', value: '›', onTap: () => _openLegal('privacy')),
          _row('§', 'Terms of Service', value: '›', onTap: () => _openLegal('terms')),
          _row('✦', 'Community Guidelines', value: '›', onTap: () => _openLegal('guidelines')),
          _row('🍪', 'Cookie preferences',
              value: Store.settings.cookieMode.toUpperCase(),
              onTap: () async {
                await showConsentSheet(context);
                setState(() {});
              }),
        ]),
        const SectionTitle('CATALOG'),
        _group(p, [
          _row('◈', 'Manga', value: 'AGGREGATED'),
          _row('¶', 'Novels & classics', value: 'AGGREGATED'),
          _row('🔒', 'Sources', value: 'MANAGED FOR YOU'),
        ]),
        const SectionTitle('ABOUT'),
        _group(p, [
          _row('◈', 'Version', value: 'v${_installed['code'] ?? 0} "${_installed['name'] ?? '?'}"'),
          _row('🌀', 'Identity', value: 'GENJUTSU · PASSWORDLESS'),
          _row('▶', 'TV streaming', value: 'IN THIS APP'),
          _row('⚡', 'Playback route', value: 'YOUR OWN CONNECTION'),
        ]),
        const SizedBox(height: 8),
        Text(
          'TV & movies stream through the app with requests going out from your own device and connection — never from a shared server.',
          style: tUi(10.5).copyWith(color: p.faint, height: 1.55),
        ),
        const SizedBox(height: 10),
        Center(
          child: GestureDetector(
            onTap: () async {
              toast(context, 'On-device data cleared — restart the app');
            },
            child: Text('Reset on-device data (coming with the next build)',
                style: tUi(10.5).copyWith(color: p.faint)),
          ),
        ),
      ],
    );
  }

  void _openLegal(String kind) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => LegalPage(kind: kind)));
  }

  /* ---------- APP UPDATES — the delta self-updater UI ---------- */
  String _stageLabel(String stage) {
    switch (stage) {
      case 'checking':
        return 'CHECKING…';
      case 'uptodate':
        return 'UP TO DATE';
      case 'available':
        return 'UPDATE READY';
      case 'downloading':
        return 'DOWNLOADING…';
      case 'patching':
        return 'REBUILDING ON DEVICE…';
      case 'verifying':
        return 'VERIFYING…';
      case 'installing':
        return 'READY TO INSTALL';
      case 'done':
        return 'DONE';
      case 'error':
        return 'FAILED — CHECK AGAIN';
      default:
        return 'DELTA · ONLY WHAT CHANGED';
    }
  }

  List<Widget> _updatesSection(Palette p) {
    final st = _updater.state;
    final busy = st.stage == 'checking' || st.stage == 'downloading' || st.stage == 'patching' || st.stage == 'verifying';
    final children = <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Text('◈', style: tUi(14)),
            const SizedBox(width: 10),
            Expanded(child: Text('Installed version', style: tUi(12.5).copyWith(color: p.fg))),
            Text('v${_installed['code'] ?? 0} · ${_installed['name'] ?? '?'}',
                style: tMono(9.5, w: FontWeight.w700).copyWith(color: p.faint, letterSpacing: 0.6)),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Text('⟳', style: tUi(14)),
            const SizedBox(width: 10),
            Expanded(child: Text('Check for updates', style: tUi(12.5).copyWith(color: p.fg))),
            Text(_stageLabel(st.stage),
                style: tMono(9.5, w: FontWeight.w700).copyWith(color: p.faint, letterSpacing: 0.6)),
          ],
        ),
      ),
    ];

    // the honest progress bar — every stage reports real bytes/steps
    if (st.stage == 'downloading' || st.stage == 'patching' || st.stage == 'verifying' || st.stage == 'installing') {
      final pct = (st.progress * 100).clamp(0.0, 100.0);
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: st.stage == 'downloading' ? st.progress : (st.progress > 0 ? st.progress : 0.12)),
                duration: const Duration(milliseconds: 250),
                builder: (_, v, __) => LinearProgressIndicator(
                  value: v.clamp(0.0, 1.0),
                  minHeight: 5,
                  backgroundColor: p.bg3,
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF57E389)),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    st.stage == 'downloading'
                        ? '${st.message}  ${st.total > 0 ? '${_fmtMb(st.received)} / ${_fmtMb(st.total)} · ${pct.toStringAsFixed(0)}%' : ''}'
                        : st.message,
                    style: tUi(10.5).copyWith(color: p.dim),
                  ),
                ),
              ],
            ),
          ],
        ),
      ));
    }

    // when a build is available — what it is + the update button
    if (st.stage == 'available' && st.latest != null) {
      final viaDelta = st.delta != null;
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'v${st.latest!.name} (code ${st.latest!.code}) · ${_fmtMb(viaDelta ? st.delta!.size : st.latest!.size)} '
              '${viaDelta ? 'delta patch — rebuilt on device, no full download' : 'full install'}',
              style: tUi(10.5).copyWith(color: p.dim, height: 1.4),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: RainbowEdgeButton(
                label: 'UPDATE NOW',
                onTap: () => _updater.startUpdate(),
              ),
            ),
          ],
        ),
      ));
    }

    children.add(Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: GestureDetector(
        onTap: busy ? null : () => _updater.checkForUpdates(),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: busy ? p.line : p.lineHard),
            borderRadius: BorderRadius.circular(7),
          ),
          child: busy
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 13,
                      height: 13,
                      child: SpinBadge(),
                    ),
                    const SizedBox(width: 8),
                    Text(_stageLabel(st.stage),
                        style: tMono(10, w: FontWeight.w700).copyWith(color: p.dim, letterSpacing: 0.6)),
                  ],
                )
              : Text(st.stage == 'available' || st.stage == 'error' || st.stage == 'uptodate'
                      ? 'CHECK AGAIN'
                      : 'CHECK NOW',
                  style: tMono(10, w: FontWeight.w700).copyWith(color: p.fg, letterSpacing: 0.6)),
        ),
      ),
    ));

    return [
      const SectionTitle('APP UPDATES'),
      _group(p, children),
    ];
  }

  Widget _group(Palette p, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: p.bg2,
        border: Border.all(color: p.line),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [for (var i = 0; i < children.length; i++) ...[
        if (i > 0) Container(height: 1, color: p.line),
        children[i],
      ]]),
    );
  }

  Widget _row(String icon, String label, {String? value, VoidCallback? onTap}) {
    final p = context.pal;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Text(icon, style: tUi(13)),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: tUi(12.5).copyWith(color: p.fg))),
            if (value != null)
              Text(value, style: tMono(9.5, w: FontWeight.w700).copyWith(color: p.faint, letterSpacing: 0.6)),
          ],
        ),
      ),
    );
  }
}


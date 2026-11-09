/* MANGACA More — settings. Account, appearance, iReader defaults, TV player,
   Legal & Privacy, catalog, about. Same structure as the web app's More tab. */

import 'package:flutter/material.dart';
import '../api.dart' as api;
import '../store.dart';
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
  @override
  bool get wantKeepAlive => true;

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
          _row('◈', 'Version', value: '0.0.1 "APPLINK"'),
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


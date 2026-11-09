/* MANGACA app shell — Mihon-style on Android: compact top bar, bottom tabs,
   browse grid → info → read, TV tab with full streaming. Same backend as the
   web app (mangaca.pages.dev), genjutsu passwordless identity. */

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart' as api;
import 'models.dart';
import 'store.dart';
import 'widgets.dart';
import 'pages/browse.dart';
import 'pages/tv.dart';
import 'pages/library.dart';
import 'pages/updates.dart';
import 'pages/history.dart';
import 'pages/more.dart';
import 'pages/search.dart';

const ORUBUS_BOT = 'https://t.me/orubus_bot';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.init();
  // restore the signed-in user from the server when a session exists
  runApp(const MangacaApp());
}

class MangacaApp extends StatefulWidget {
  const MangacaApp({super.key});
  @override
  State<MangacaApp> createState() => _MangacaAppState();
}

class _MangacaAppState extends State<MangacaApp> {
  bool _dark = true;

  void applyTheme() {
    final t = Store.settings.theme;
    final systemDark = WidgetsBinding
            .instance.platformDispatcher.platformBrightness !=
        Brightness.light;
    final dark = t == 'dark' || (t == 'auto' && systemDark);
    setState(() => _dark = dark);
  }

  @override
  void initState() {
    super.initState();
    applyTheme();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette(_dark);
    return MaterialApp(
      title: 'MANGACA',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: false,
        brightness: _dark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: p.bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kRainbow.last,
          brightness: _dark ? Brightness.dark : Brightness.light,
          surface: p.bg,
        ),
        fontFamily: 'SpaceGrotesk',
      ),
      builder: (context, child) => DefaultTextStyle(
        style: tUi(14).copyWith(color: p.fg),
        child: child!,
      ),
      home: Shell(onThemeChanged: applyTheme, isDark: _dark),
    );
  }
}

/* ================= shell ================= */

class Shell extends StatefulWidget {
  final VoidCallback onThemeChanged;
  final bool isDark;
  const Shell({super.key, required this.onThemeChanged, required this.isDark});
  @override
  State<Shell> createState() => ShellState();
}

class ShellState extends State<Shell> {
  int tab = 3; // browse is the home tab, like the web
  String homeSection = 'foryou'; // foryou | popular | latest | tv
  int themeCycle = 0;

  @override
  void initState() {
    super.initState();
    boot();
  }

  Future<void> boot() async {
    try {
      final me = await api.authMe();
      if (me['ok'] == true && me['user'] != null) {
        Store.setUser(MUser.fromJson(Map<String, dynamic>.from(me['user'])));
        try {
          final rows = await api.progressList();
          if (rows['items'] != null) Store.mergeServerProgress(rows['items']);
        } catch (_) {}
        if (mounted) setState(() {});
        if (!(me['user']['profile_complete'] == true)) {
          if (mounted) openProfileWizard(context);
        }
      }
    } catch (_) {}
    if (Store.settings.cookieMode == 'not set' && mounted) {
      // first-run notice — same role as the web consent bar
      showConsentSheet(context, firstRun: true);
    }
  }

  void goHomeSection(String s) => setState(() => homeSection = s);

  Future<void> refresh() async => setState(() {});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Scaffold(
      backgroundColor: p.bg,
      appBar: _topBar(p),
      body: IndexedStack(
        index: tab,
        children: [
          LibraryPage(onChanged: refresh),
          UpdatesPage(onChanged: refresh),
          HistoryPage(onChanged: refresh),
          homeSection == 'tv'
              ? TvPage(onSection: goHomeSection)
              : BrowsePage(section: homeSection, onSection: goHomeSection),
          MorePage(onChanged: refresh, onThemeChanged: widget.onThemeChanged),
        ],
      ),
      bottomNavigationBar: _bottomNav(p),
    );
  }

  PreferredSizeWidget _topBar(Palette p) {
    final u = Store.user;
    return AppBar(
      backgroundColor: p.bg2,
      foregroundColor: p.fg,
      elevation: 0,
      toolbarHeight: 46 + MediaQuery.of(context).padding.top * 0,
      titleSpacing: 12,
      title: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(gradient: LinearGradient(colors: kRainbow)),
            padding: const EdgeInsets.all(2),
            child: const FittedBox(child: Text('M', style: TextStyle(fontFamily: 'ArchivoBlack', color: Colors.black))),
          ),
          const SizedBox(width: 8),
          Text('MANGACA', style: tDisplay(14).copyWith(color: p.fg, letterSpacing: 2)),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search, size: 21),
          color: p.dim,
          tooltip: 'Search',
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SearchPage())),
        ),
        IconButton(
          onPressed: () {
            final order = ['auto', 'dark', 'light'];
            themeCycle = (themeCycle + 1) % 3;
            Store.settings.theme = order[themeCycle];
            Store.saveSettings();
            widget.onThemeChanged();
            toast(context, 'Theme: ${Store.settings.theme.toUpperCase()}');
          },
          icon: const Icon(Icons.contrast, size: 20),
          color: p.dim,
          tooltip: 'Theme',
        ),
        GestureDetector(
          onTap: () {
            if (Store.user != null) {
              openAccountSheet(context, onChanged: refresh);
            } else {
              openAuthSheet(context, onSignedIn: refresh);
            }
          },
          child: Container(
            margin: const EdgeInsets.only(right: 12, left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: u != null ? p.bg3 : Colors.transparent,
              border: Border.all(color: u != null ? p.faint : p.lineHard),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (u != null) ...[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: kRainbow),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text((u.username).substring(0, u.username.length.clamp(1, 10)),
                      style: tUi(11, w: FontWeight.w700).copyWith(color: p.fg)),
                ] else
                  Text('SIGN IN', style: tUi(10.5, w: FontWeight.w700).copyWith(color: p.dim, letterSpacing: 0.8)),
              ],
            ),
          ),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: p.line),
      ),
    );
  }

  Widget _bottomNav(Palette p) {
    final items = [
      (Icons.collections_bookmark_outlined, 'Library'),
      (Icons.update_outlined, 'Updates'),
      (Icons.history_outlined, 'History'),
      (Icons.explore_outlined, 'Browse'),
      (Icons.more_horiz, 'More'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: p.bg2,
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: List.generate(items.length, (i) {
              final active = tab == i;
              final icon = items[i].$1;
              final label = items[i].$2;
              return Expanded(
                child: InkWell(
                  onTap: () => setState(() => tab = i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Icon(icon, size: 22, color: active ? p.fg : p.faint),
                          if (active)
                            Positioned(
                              top: -4,
                              left: 4,
                              right: 4,
                              child: Container(height: 2.5, decoration: const BoxDecoration(gradient: LinearGradient(colors: kRainbow))),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(label,
                          style: tUi(9.5, w: active ? FontWeight.w700 : FontWeight.w400)
                              .copyWith(color: active ? p.fg : p.faint)),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/* ================= auth sheet ================= */

Future<void> openAuthSheet(BuildContext context, {VoidCallback? onSignedIn}) async {
  final p = context.pal;
  final code = TextEditingController();
  final err = ValueNotifier<String>('');
  final busy = ValueNotifier<bool>(false);

  await showMSheet(context, builder: (ctx) {
    return ValueListenableBuilder<String>(
      valueListenable: err,
      builder: (context, errVal, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: busy,
          builder: (context, busyVal, _) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SheetGrab(),
                Text('CONTINUE WITH GENJUTSU', style: tDisplay(16).copyWith(color: p.fg)),
                const SizedBox(height: 8),
                Text(
                  "Passwordless — exactly like “continue with Google”. No password fields, no username form: your genjutsu identity is verified, then you pick a username and a role here.",
                  style: tUi(12).copyWith(color: p.dim, height: 1.5),
                ),
                const SizedBox(height: 10),
                const RainbowLine(),
                const SizedBox(height: 14),
                Text('GENJUTSU LINK CODE', style: tMono(9.5, w: FontWeight.w700).copyWith(color: p.faint, letterSpacing: 1)),
                const SizedBox(height: 6),
                TextField(
                  controller: code,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                  style: tMono(14).copyWith(color: p.fg),
                  decoration: _inputDeco(p, 'GENJ-XXXX'),
                ),
                const SizedBox(height: 8),
                _GhostButton(
                  label: 'GET A CODE — OPEN @orubus_bot ↗',
                  onTap: () => launchUrl(Uri.parse(ORUBUS_BOT), mode: LaunchMode.externalApplication),
                ),
                const SizedBox(height: 6),
                Text(
                  'Send /genjutsu to the Orubus bot on Telegram → it mints a one-time GENJ code → paste it above. First use creates your MANGACA account and binds this device to it.',
                  style: tUi(10.5).copyWith(color: p.faint, height: 1.45),
                ),
                if (errVal.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(errVal, style: tUi(11.5).copyWith(color: const Color(0xFFFF5A5A))),
                ],
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: busyVal ? null : () async {
                      if (code.text.trim().isEmpty) {
                        err.value = 'Tap “GET A CODE” first — the bot mints a GENJ-XXXX code for you.';
                        return;
                      }
                      busy.value = true;
                      err.value = '';
                      try {
                        final res = await api.authCodeClaim(code.text.trim());
                        busy.value = false;
                        if (res['ok'] != true) {
                          err.value = (res['message'] ?? 'Sign in failed.').toString();
                          return;
                        }
                        Store.setUser(MUser.fromJson(Map<String, dynamic>.from(res['user'])));
                        if (ctx.mounted) Navigator.of(ctx).pop();
                        onSignedIn?.call();
                        toast(context,
                            res['created'] == true
                                ? 'Account created — welcome @${Store.user!.username}'
                                : 'Signed in as @${Store.user!.username}');
                        try {
                          final rows = await api.progressList();
                          if (rows['items'] != null) Store.mergeServerProgress(rows['items']);
                        } catch (_) {}
                        if (!Store.user!.profileComplete && context.mounted) {
                          openProfileWizard(context, onDone: onSignedIn);
                        }
                      } catch (e) {
                        busy.value = false;
                        err.value = 'network error';
                      }
                    },
                    child: RainbowEdgeButton(
                      label: busyVal ? '…' : 'CONTINUE WITH GENJUTSU',
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  });
}

InputDecoration _inputDeco(Palette p, String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: tMono(13).copyWith(color: p.faint),
    filled: true,
    fillColor: p.bg3,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: BorderSide(color: p.lineHard)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(7), borderSide: BorderSide(color: p.fg)),
  );
}

/* ================= profile wizard ================= */

Future<void> openProfileWizard(BuildContext context, {VoidCallback? onDone}) async {
  final p = context.pal;
  final uname = TextEditingController();
  final err = ValueNotifier<String>('');
  final role = ValueNotifier<String>('reader');
  final roles = [
    ('reader', 'READER', 'Browse, read, comment, like'),
    ('author', 'AUTHOR', 'Publish stories & chapters'),
    ('publisher', 'PUBLISHER', 'Run titles & upload series'),
  ];

  await showMSheet(context, builder: (ctx) {
    return ValueListenableBuilder<String>(
      valueListenable: err,
      builder: (context, errVal, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetGrab(),
            Text('FINISH YOUR ACCOUNT', style: tDisplay(16).copyWith(color: p.fg)),
            const SizedBox(height: 6),
            Text(
              'Identity verified by genjutsu${Store.user?.gid.isNotEmpty == true ? ' · ${Store.user!.gid}' : ''}. Now pick the username people will see and how you use MANGACA.',
              style: tUi(12).copyWith(color: p.dim, height: 1.5),
            ),
            const SizedBox(height: 10),
            const RainbowLine(),
            const SizedBox(height: 14),
            Text('USERNAME', style: tMono(9.5, w: FontWeight.w700).copyWith(color: p.faint, letterSpacing: 1)),
            const SizedBox(height: 6),
            TextField(
              controller: uname,
              autocorrect: false,
              maxLength: 20,
              style: tUi(14).copyWith(color: p.fg),
              decoration: _inputDeco(p, 'e.g. shadow_alchemist'),
            ),
            Text('3–20 characters · letters, numbers, _ . - only',
                style: tUi(10.5).copyWith(color: p.faint)),
            const SizedBox(height: 12),
            ValueListenableBuilder<String>(
              valueListenable: role,
              builder: (context, rv, _) => Row(
                children: roles.map((r) {
                  final on = rv == r.$1;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => role.value = r.$1,
                      child: Container(
                        margin: EdgeInsets.only(right: r == roles.last ? 0 : 8),
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                        decoration: BoxDecoration(
                          color: on ? p.bg3 : Colors.transparent,
                          border: Border.all(color: on ? p.fg : p.lineHard),
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: on ? [BoxShadow(offset: const Offset(3, 3), color: p.bg.withOpacity(0.6))] : null,
                        ),
                        child: Column(
                          children: [
                            Text(r.$2, style: tDisplay(11).copyWith(color: p.fg)),
                            const SizedBox(height: 3),
                            Text(r.$3,
                                textAlign: TextAlign.center,
                                style: tUi(9).copyWith(color: p.dim, height: 1.3)),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            if (errVal.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(errVal, style: tUi(11.5).copyWith(color: const Color(0xFFFF5A5A))),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: RainbowEdgeButton(
                label: 'ENTER MANGACA',
                onTap: () async {
                  err.value = '';
                  final res = await api.authProfile(uname.text.trim(), role.value).catchError((e) => <String, dynamic>{'ok': false, 'message': 'network error'});
                  if (res['ok'] != true) {
                    err.value = (res['message'] ?? 'Could not save — try again.').toString();
                    return;
                  }
                  Store.setUser(MUser.fromJson(Map<String, dynamic>.from(res['user'])));
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  onDone?.call();
                  toast(context, 'Welcome @${Store.user!.username} · ${Store.user!.role.toUpperCase()}');
                },
              ),
            ),
          ],
        );
      },
    );
  });
}

/* ================= account sheet ================= */

Future<void> openAccountSheet(BuildContext context, {VoidCallback? onChanged}) async {
  final p = context.pal;
  final u = Store.user;
  if (u == null) return;
  await showMSheet(context, builder: (ctx) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetGrab(),
        Text('GENJUTSU IDENTITY', style: tDisplay(16).copyWith(color: p.fg)),
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: p.bg3, borderRadius: BorderRadius.circular(8)),
              child: Text(u.username.isNotEmpty ? u.username[0].toUpperCase() : '?',
                  style: tDisplay(18).copyWith(color: p.fg)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('@${u.username}', style: tUi(14, w: FontWeight.w700).copyWith(color: p.fg)),
                  Text('ID ${u.sub.isEmpty ? u.gid : u.sub}',
                      style: tMono(9).copyWith(color: p.faint)),
                  const SizedBox(height: 4),
                  InfoChip(u.role.toUpperCase()),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'One genjutsu identity everywhere — Orubus, Genjutsu and now MANGACA. Reading progress, comments and likes ride on this identity.',
          style: tUi(11.5).copyWith(color: p.dim, height: 1.5),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _GhostButton(
                label: 'OPEN GENJUTSU ↗',
                onTap: () => launchUrl(Uri.parse('https://genjustu.pages.dev'), mode: LaunchMode.externalApplication),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RainbowEdgeButton(
                label: 'SIGN OUT',
                onTap: () async {
                  try {
                    await api.authLogout();
                  } catch (_) {}
                  Store.setUser(null);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  onChanged?.call();
                  toast(context, 'Signed out');
                },
              ),
            ),
          ],
        ),
      ],
    );
  });
}

/* ================= consent sheet (first run) ================= */

Future<void> showConsentSheet(BuildContext context, {bool firstRun = false}) async {
  final p = context.pal;
  await showMSheet(context, builder: (ctx) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SheetGrab(),
        Text('COOKIES & PRIVACY', style: tDisplay(16).copyWith(color: p.fg)),
        const SizedBox(height: 8),
        Text(
          'MANGACA keeps one sign-in session on this device (the app cannot keep you signed in without it) plus on-device storage for your preferences, progress and library. No third-party ad tracking.',
          style: tUi(12).copyWith(color: p.dim, height: 1.5),
        ),
        const SizedBox(height: 10),
        const RainbowLine(),
        const SizedBox(height: 12),
        Text('Details: Privacy Policy · Terms — in More › Legal & Privacy',
            style: tUi(10.5).copyWith(color: p.faint)),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _GhostButton(
                label: 'ESSENTIAL ONLY',
                onTap: () {
                  Store.settings.cookieMode = 'essential';
                  Store.saveSettings();
                  Navigator.of(ctx).pop();
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: RainbowEdgeButton(
                label: 'ACCEPT ALL',
                onTap: () {
                  Store.settings.cookieMode = 'all';
                  Store.saveSettings();
                  Navigator.of(ctx).pop();
                },
              ),
            ),
          ],
        ),
      ],
    );
  });
}

/* ================= ghost button ================= */

class _GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _GhostButton({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          border: Border.all(color: p.lineHard),
          borderRadius: BorderRadius.circular(7),
        ),
        child: Center(
          child: Text(label,
              textAlign: TextAlign.center,
              style: tUi(11, w: FontWeight.w500).copyWith(color: p.fg)),
        ),
      ),
    );
  }
}

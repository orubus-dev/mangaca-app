/* MANGACA models — mirrors the runtime's JSON contracts exactly. */

class BookItem {
  final String sid; // source id (originals / mangadex / weebcentral / gutenberg / ...)
  final String bid; // book id inside the source
  final String title;
  final String cover;
  final String src; // display label (MANGA / NOVELS / CLASSICS / ORIGINALS)
  final String kind; // manga | novel | book
  final String author;
  final String status;
  final dynamic year;
  final String synopsis;
  final List<String> tags;

  BookItem({
    required this.sid,
    required this.bid,
    required this.title,
    this.cover = '',
    this.src = '',
    this.kind = 'manga',
    this.author = '',
    this.status = '',
    this.year,
    this.synopsis = '',
    this.tags = const [],
  });

  String get key => '$sid:$bid';

  Map<String, dynamic> toMini() => {
        'sid': sid,
        'bid': bid,
        'title': title,
        'cover': cover,
        'src': src,
        'kind': kind,
      };

  factory BookItem.fromMini(Map<String, dynamic> m) => BookItem(
        sid: m['sid'] ?? '',
        bid: m['bid'] ?? '',
        title: m['title'] ?? '',
        cover: m['cover'] ?? '',
        src: m['src'] ?? '',
        kind: m['kind'] ?? 'manga',
      );
}

class Chapter {
  final String cid;
  final String title;
  final num number;
  final int pages;
  final String date;
  Chapter({required this.cid, required this.title, this.number = 0, this.pages = 0, this.date = ''});
}

class TvItem {
  final String id;
  final String title;
  final String poster;
  final String tagline;
  final String kind;
  final String provider;
  final String description;
  TvItem({
    required this.id,
    required this.title,
    this.poster = '',
    this.tagline = '',
    this.kind = '',
    this.provider = '',
    this.description = '',
  });
}

class Episode {
  final String id;
  final String title;
  final String duration;
  final String quality;
  final String overview;
  Episode({required this.id, required this.title, this.duration = '', this.quality = '', this.overview = ''});

  bool get isPartnerLane => id.startsWith('cm:play:');
}

class TvShow {
  final String id;
  final String title;
  final String poster;
  final String tagline;
  final String description;
  final String kind;
  final String provider;
  final List<Episode> episodes;
  TvShow({
    required this.id,
    required this.title,
    this.poster = '',
    this.tagline = '',
    this.description = '',
    this.kind = 'series',
    this.provider = '',
    this.episodes = const [],
  });
}

class Mirror {
  final String label;
  final String url;
  Mirror({required this.label, required this.url});
}

class Quality {
  final String label;
  final String m3u8;
  Quality({required this.label, required this.m3u8});
}

class SubtitleTrack {
  final String lang;
  final String url;
  SubtitleTrack({required this.lang, required this.url});
}

class SocialState {
  final bool ok;
  final bool liked;
  final bool favorited;
  final int likes;
  final int favorites;
  final List<dynamic> comments;
  SocialState({
    required this.ok,
    this.liked = false,
    this.favorited = false,
    this.likes = 0,
    this.favorites = 0,
    this.comments = const [],
  });
}

class MUser {
  final String username;
  final String display;
  final String role;
  final String gid;
  final String sub;
  final bool profileComplete;
  MUser({
    required this.username,
    this.display = '',
    this.role = 'reader',
    this.gid = '',
    this.sub = '',
    this.profileComplete = false,
  });

  factory MUser.fromJson(Map<String, dynamic> j) => MUser(
        username: j['username'] ?? '',
        display: j['display'] ?? j['username'] ?? '',
        role: j['role'] ?? 'reader',
        gid: j['gid'] ?? '',
        sub: j['sub'] ?? '',
        profileComplete: j['profile_complete'] == true,
      );
}

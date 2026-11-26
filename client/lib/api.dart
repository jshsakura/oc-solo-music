import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 서버 `/api/tracks` 의 곡 하나입니다.
@immutable
class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.source,
    required this.duration,
    required this.hasCover,
    required this.liked,
    this.hasLyrics = false,
  });

  factory Track.fromJson(Map<String, dynamic> json) => Track(
    id: json['id'] as String,
    title: (json['title'] as String?) ?? '',
    artist: (json['artist'] as String?) ?? '',
    source: (json['source'] as String?) ?? '',
    duration: ((json['duration'] as num?) ?? 0).toDouble(),
    hasCover: json['cover'] == true,
    liked: json['liked'] == true,
    hasLyrics: json['lyrics'] == true,
  );

  final String id;
  final String title;
  final String artist;
  final String source;
  final double duration;
  final bool hasCover;
  final bool liked;

  /// 수노에서 가사를 받아 둔 곡입니다. 연주곡이면 false 입니다.
  final bool hasLyrics;

  /// 표지가 없을 때 판 라벨에 크게 쓰는 첫 글자입니다.
  String get letter => title.isEmpty
      ? '?'
      : String.fromCharCode(title.runes.first).toUpperCase();

  Track withLiked(bool value) => Track(
    id: id,
    title: title,
    artist: artist,
    source: source,
    duration: duration,
    hasCover: hasCover,
    liked: value,
    hasLyrics: hasLyrics,
  );
}

/// 곡 정보 화면에 띄울 내용입니다. 서버가 곡 파일의 태그에서 읽어 줍니다.
@immutable
class TrackInfo {
  const TrackInfo({
    this.genre = '',
    this.album = '',
    this.year = '',
    this.lyrics = '',
    this.duration = 0,
    this.added = 0,
    this.sunoUrl = '',
    this.sunoModel = '',
  });

  factory TrackInfo.fromJson(Map<String, dynamic> json) {
    String text(String key) => (json[key] as String?) ?? '';
    return TrackInfo(
      genre: text('genre'),
      album: text('album'),
      year: text('year'),
      lyrics: text('lyrics'),
      duration: ((json['duration'] as num?) ?? 0).toDouble(),
      added: ((json['added'] as num?) ?? 0).toInt(),
      sunoUrl: text('suno_url'),
      sunoModel: text('suno_model'),
    );
  }

  final String genre;
  final String album;
  final String year;
  final String lyrics;
  final double duration;

  /// 보관함에 들어온 시각(유닉스 초)입니다. 모르면 0 입니다.
  final int added;
  final String sunoUrl;
  final String sunoModel;
}

/// 녹음이나 받기 작업 하나입니다. 서버 `/api/jobs` 의 모양입니다.
@immutable
class Job {
  const Job({
    required this.id,
    required this.kind,
    required this.status,
    required this.title,
    required this.url,
    required this.detail,
    required this.progress,
    this.hasCover = false,
    this.duration,
  });

  factory Job.fromJson(Map<String, dynamic> json) => Job(
    id: json['id'] as String,
    kind: (json['kind'] as String?) ?? '',
    status: (json['status'] as String?) ?? '',
    title: (json['title'] as String?) ?? '',
    url: (json['url'] as String?) ?? '',
    detail: (json['detail'] as String?) ?? '',
    progress: ((json['progress'] as num?) ?? 0).toDouble(),
    hasCover: json['cover'] == true,
    duration: switch (json['duration']) {
      final num d when d > 0 => d.toDouble(),
      _ => null,
    },
  );

  static const active = {'queued', 'recording'};

  final String id;
  final String kind;
  final String status;
  final String title;
  final String url;
  final String detail;
  final double progress;

  /// 녹음을 기다리는 동안 미리 받아 둔 수노 표지가 있는지입니다.
  final bool hasCover;

  /// 수노가 알려 준 곡 길이(초)입니다. 모르면 비어 있습니다.
  final double? duration;

  bool get isActive => active.contains(status);
  bool get isRunning => status == 'recording';
  String get label => title.isNotEmpty ? title : url;
}

/// 어떤 요청이 실패했는지입니다. 화면 문구는 [S.apiFail] 이 언어별로 만듭니다.
enum ApiFail {
  tracks,
  like,
  add,
  upload,
  jobs,
  cancel,
  retry,
  remove,
  restore,
  archive,
  app,
  me,
  pair,
  devices,
  info,
}

/// 서버가 이 요청을 누구로 보는지입니다.
class Me {
  const Me({required this.via, required this.owner, this.email = ''});

  factory Me.fromJson(Map j) => Me(
    via: j['via'] as String? ?? '',
    owner: j['owner'] == true,
    email: j['email'] as String? ?? '',
  );

  final String via;
  final bool owner;
  final String email;
}

/// QR 에 담을 짝짓기 주소와 그 만료 시각입니다.
class PairOffer {
  const PairOffer({required this.uri, required this.expires});

  factory PairOffer.fromJson(Map j) => PairOffer(
    uri: j['uri'] as String,
    expires: DateTime.fromMillisecondsSinceEpoch(
      ((j['expires'] as num) * 1000).round(),
    ),
  );

  final String uri;
  final DateTime expires;
}

/// QR 로 짝지은 기기 한 대입니다.
class Device {
  const Device({
    required this.id,
    required this.name,
    required this.platform,
    this.lastSeen,
  });

  factory Device.fromJson(Map j) => Device(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    platform: j['platform'] as String? ?? '',
    lastSeen: j['last_seen'] is num
        ? DateTime.fromMillisecondsSinceEpoch(
            ((j['last_seen'] as num) * 1000).round(),
          )
        : null,
  );

  final String id;
  final String name;
  final String platform;
  final DateTime? lastSeen;
}

/// QR 에서 읽은 짝짓기 주소입니다. `solo://pair?server=…&code=…` 만 받습니다.
class PairLink {
  const PairLink(this.server, this.code);

  final Uri server;
  final String code;

  static PairLink? parse(String text) {
    final u = Uri.tryParse(text.trim());
    if (u == null || u.scheme != 'solo' || u.host != 'pair') return null;
    final server = Uri.tryParse(u.queryParameters['server'] ?? '');
    final code = u.queryParameters['code'] ?? '';
    if (server == null || server.host.isEmpty || code.isEmpty) return null;
    if (server.scheme != 'http' && server.scheme != 'https') return null;
    return PairLink(server, code);
  }
}

/// 서버가 내주는 안드로이드 앱 한 벌입니다.
class AppBuild {
  const AppBuild({required this.version, required this.size});

  factory AppBuild.fromJson(Map<String, dynamic> j) => AppBuild(
    version: j['version'] as String? ?? '',
    size: (j['size'] as num?)?.toInt() ?? 0,
  );

  final String version;
  final int size;

  String get sizeLabel => '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class ApiException implements Exception {
  ApiException(this.what, {this.status, this.detail});
  final ApiFail what;
  final int? status;

  /// 서버가 화면 언어로 보낸 사유입니다.
  final String? detail;

  @override
  String toString() => 'ApiException($what, $status, $detail)';
}

/// Solo 서버와 이야기합니다. 어느 서버를 쓸지는 main.dart 가 정합니다.
class Api {
  Api(this.base, {this.password = '', this.token = '', http.Client? client}) {
    _client = _Speaking(client ?? http.Client(), () => language, () => headers);
  }

  /// 서버에 SOLO_PASSWORD 가 걸려 있을 때 쓰는 비밀번호입니다. 웹은 브라우저가 대신 들고 있어 비워 둡니다.
  final String password;

  /// 웹에서 QR 로 짝지어 받은 기기 토큰입니다. 있으면 비밀번호보다 먼저 씁니다.
  final String token;

  /// 오디오와 표지 요청에도 같은 인증을 붙입니다. 서버는 사용자 이름을 보지 않습니다.
  Map<String, String> get headers {
    if (token.isNotEmpty) return {'authorization': 'Bearer $token'};
    if (password.isEmpty) return const {};
    return {
      'authorization': 'Basic ${base64Encode(utf8.encode('solo:$password'))}',
    };
  }

  /// 서버 문구를 받을 언어입니다. 화면이 기기 언어를 정한 뒤 맞춰 둡니다.
  String language = 'en';

  final Uri base;
  late final http.Client _client;

  Uri _at(String path) => base.resolve(path);

  Uri audioUri(String id) => _at('/api/audio/${Uri.encodeComponent(id)}');
  Uri coverUri(String id) => _at('/api/cover/${Uri.encodeComponent(id)}');
  Uri jobCoverUri(String id) =>
      _at('/api/jobs/${Uri.encodeComponent(id)}/cover');
  Uri get apkUri => _at('/solo.apk');

  /// 서버에 안드로이드 앱이 있으면 버전과 크기를, 없으면 null 을 돌려줍니다.
  Future<AppBuild?> androidBuild() async {
    final res = await _client.get(_at('/api/app'));
    if (res.statusCode != 200) {
      throw ApiException(ApiFail.app, status: res.statusCode);
    }
    final android = (jsonDecode(res.body) as Map<String, dynamic>)['android'];
    return android is Map<String, dynamic> ? AppBuild.fromJson(android) : null;
  }

  Uri downloadUri(String id) => _at('/api/download/${Uri.encodeComponent(id)}');

  /// 곡 하나의 가사입니다. 못 받으면 빈 글로 돌려줘서 가사 칸이 조용히 숨습니다.
  Future<String> lyrics(String id) async {
    try {
      final res = await _client.get(
        _at('/api/lyrics/${Uri.encodeComponent(id)}'),
      );
      if (res.statusCode != 200) return '';
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      return body is Map && body['lyrics'] is String
          ? body['lyrics'] as String
          : '';
    } on Exception {
      return '';
    }
  }

  Future<TrackInfo> info(String id) async {
    final body = await _json(
      _client.get(_at('/api/info/${Uri.encodeComponent(id)}')),
      ApiFail.info,
    );
    if (body is! Map<String, dynamic>) throw ApiException(ApiFail.info);
    return TrackInfo.fromJson(body);
  }

  Future<List<Track>> tracks() async {
    final res = await _client.get(_at('/api/tracks'));
    if (res.statusCode != 200) {
      throw ApiException(ApiFail.tracks, status: res.statusCode);
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! List) throw ApiException(ApiFail.tracks);
    return body
        .whereType<Map<String, dynamic>>()
        .map(Track.fromJson)
        .toList(growable: false);
  }

  Future<bool> toggleLike(String id) async {
    final res = await _client.post(_at('/api/like/${Uri.encodeComponent(id)}'));
    if (res.statusCode != 200) {
      throw ApiException(ApiFail.like, status: res.statusCode);
    }
    return (jsonDecode(res.body) as Map<String, dynamic>)['liked'] == true;
  }

  Future<dynamic> _json(Future<http.Response> call, ApiFail what) async {
    final res = await call;
    final body = res.bodyBytes.isEmpty
        ? null
        : jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode >= 400) {
      final detail = body is Map ? body['detail'] : null;
      throw ApiException(
        what,
        status: res.statusCode,
        detail: detail is String ? detail : null,
      );
    }
    return body;
  }

  static const _jsonHeaders = {'content-type': 'application/json'};

  /// 내가 만든 수노 곡 주소를 대기열에 넣고, 새로 들어간 작업 수를 돌려줍니다.
  Future<int> add(List<String> urls) async {
    final body = await _json(
      _client.post(
        _at('/api/add'),
        headers: _jsonHeaders,
        body: jsonEncode({'urls': urls}),
      ),
      ApiFail.add,
    );
    return ((body as Map)['queued'] as num?)?.toInt() ?? 0;
  }

  /// 가진 곡 파일 하나를 올립니다. 새로 담았으면 true, 이미 있던 파일이면 false 입니다.
  Future<bool> upload(String name, List<int> bytes) async {
    final body = await _json(
      _client.put(
        _at('/api/upload').replace(queryParameters: {'name': name}),
        headers: {'content-type': 'application/octet-stream'},
        body: bytes,
      ),
      ApiFail.upload,
    );
    return (body as Map)['added'] == true;
  }

  Future<List<Job>> jobs() async {
    final body = await _json(_client.get(_at('/api/jobs')), ApiFail.jobs);
    return body is List
        ? body.whereType<Map<String, dynamic>>().map(Job.fromJson).toList()
        : const [];
  }

  Future<void> retry(String jobId) => _json(
    _client.post(_at('/api/jobs/${Uri.encodeComponent(jobId)}/retry')),
    ApiFail.retry,
  );

  Future<void> cancel(String jobId) => _json(
    _client.post(_at('/api/jobs/${Uri.encodeComponent(jobId)}/cancel')),
    ApiFail.cancel,
  );

  /// 목록에서만 뺍니다. 파일은 서버의 archive 폴더에 남아 되살릴 수 있습니다.
  Future<void> remove(String id) => _json(
    _client.delete(_at('/api/tracks/${Uri.encodeComponent(id)}')),
    ApiFail.remove,
  );

  Future<void> restore(String id) => _json(
    _client.post(_at('/api/archive/${Uri.encodeComponent(id)}/restore')),
    ApiFail.restore,
  );

  Future<List<Track>> archived() async {
    final body = await _json(_client.get(_at('/api/archive')), ApiFail.archive);
    return body is List
        ? body.whereType<Map<String, dynamic>>().map(Track.fromJson).toList()
        : const [];
  }

  /// 지금 요청을 서버가 누구로 보는지입니다. owner 만 기기를 짝짓고 지웁니다.
  Future<Me> me() async =>
      Me.fromJson(await _json(_client.get(_at('/api/me')), ApiFail.me) as Map);

  /// 웹이 QR 로 띄울 1회용 짝짓기 주소를 받습니다.
  Future<PairOffer> pair() async => PairOffer.fromJson(
    await _json(_client.post(_at('/api/pair')), ApiFail.pair) as Map,
  );

  /// QR 의 코드를 이 기기의 토큰으로 바꿉니다. 아직 인증이 없는 요청입니다.
  static Future<String> claim(
    Uri server,
    String code, {
    required String name,
    required String platform,
    http.Client? client,
  }) async {
    final api = Api(server, client: client);
    final body = await api._json(
      api._client.post(
        api._at('/api/pair/claim'),
        headers: _jsonHeaders,
        body: jsonEncode({'code': code, 'name': name, 'platform': platform}),
      ),
      ApiFail.pair,
    );
    return (body as Map)['token'] as String;
  }

  Future<List<Device>> devices() async {
    final body = await _json(_client.get(_at('/api/devices')), ApiFail.devices);
    return body is List
        ? body.whereType<Map>().map(Device.fromJson).toList()
        : const [];
  }

  Future<void> removeDevice(String id) => _json(
    _client.delete(_at('/api/devices/${Uri.encodeComponent(id)}')),
    ApiFail.devices,
  );
}

/// 모든 요청에 화면 언어를 실어 보냅니다. 서버가 실패 사유를 그 언어로 답합니다.
class _Speaking extends http.BaseClient {
  _Speaking(this._inner, this._language, this._auth);
  final http.Client _inner;
  final String Function() _language;
  final Map<String, String> Function() _auth;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['accept-language'] = _language();
    request.headers.addAll(_auth());
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

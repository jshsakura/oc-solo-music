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
  });

  factory Track.fromJson(Map<String, dynamic> json) => Track(
    id: json['id'] as String,
    title: (json['title'] as String?) ?? '',
    artist: (json['artist'] as String?) ?? '',
    source: (json['source'] as String?) ?? '',
    duration: ((json['duration'] as num?) ?? 0).toDouble(),
    hasCover: json['cover'] == true,
    liked: json['liked'] == true,
  );

  final String id;
  final String title;
  final String artist;
  final String source;
  final double duration;
  final bool hasCover;
  final bool liked;

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
  );
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
  });

  factory Job.fromJson(Map<String, dynamic> json) => Job(
    id: json['id'] as String,
    kind: (json['kind'] as String?) ?? '',
    status: (json['status'] as String?) ?? '',
    title: (json['title'] as String?) ?? '',
    url: (json['url'] as String?) ?? '',
    detail: (json['detail'] as String?) ?? '',
    progress: ((json['progress'] as num?) ?? 0).toDouble(),
  );

  static const active = {'queued', 'recording', 'downloading'};

  final String id;
  final String kind;
  final String status;
  final String title;
  final String url;
  final String detail;
  final double progress;

  bool get isActive => active.contains(status);
  bool get isRunning => status == 'recording' || status == 'downloading';
  String get label => title.isNotEmpty ? title : url;
}

/// 유튜브 검색 결과 한 곡입니다. 받기를 누르면 이 모양 그대로 서버에 돌려줍니다.
@immutable
class Found {
  const Found(this.raw);
  final Map<String, dynamic> raw;

  String get videoId => raw['videoId'] as String;
  String get title => (raw['title'] as String?) ?? '';
  String get artist => (raw['artist'] as String?) ?? '';
  String get art => (raw['art'] as String?) ?? '';
  double get duration => ((raw['duration'] as num?) ?? 0).toDouble();
  bool get owned => raw['owned'] == true;
}

/// 어떤 요청이 실패했는지입니다. 화면 문구는 [S.apiFail] 이 언어별로 만듭니다.
enum ApiFail {
  tracks,
  like,
  add,
  search,
  get,
  jobs,
  cancel,
  remove,
  restore,
  archive,
  youtubeStatus,
  app,
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
  Api(this.base, {this.password = '', http.Client? client}) {
    _client = _Speaking(client ?? http.Client(), () => language, () => headers);
  }

  /// 서버에 SOLO_PASSWORD 가 걸려 있을 때 쓰는 비밀번호입니다. 웹은 브라우저가 대신 들고 있어 비워 둡니다.
  final String password;

  /// 오디오와 표지 요청에도 같은 인증을 붙입니다. 서버는 사용자 이름을 보지 않습니다.
  Map<String, String> get headers => password.isEmpty
      ? const {}
      : {
          'authorization':
              'Basic ${base64Encode(utf8.encode('solo:$password'))}',
        };

  /// 서버 문구를 받을 언어입니다. 화면이 기기 언어를 정한 뒤 맞춰 둡니다.
  String language = 'en';

  final Uri base;
  late final http.Client _client;

  Uri _at(String path) => base.resolve(path);

  Uri audioUri(String id) => _at('/api/audio/${Uri.encodeComponent(id)}');
  Uri coverUri(String id) => _at('/api/cover/${Uri.encodeComponent(id)}');
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

  /// 수노·유튜브 주소를 대기열에 넣고, 새로 들어간 작업 수를 돌려줍니다.
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

  Future<List<Found>> search(String query) async {
    final body = await _json(
      _client.get(_at('/api/search').replace(queryParameters: {'q': query})),
      ApiFail.search,
    );
    final tracks = (body as Map)['tracks'];
    return tracks is List
        ? tracks.whereType<Map<String, dynamic>>().map(Found.new).toList()
        : const [];
  }

  Future<int> get(Found track) async {
    final body = await _json(
      _client.post(
        _at('/api/youtube/get'),
        headers: _jsonHeaders,
        body: jsonEncode(track.raw),
      ),
      ApiFail.get,
    );
    return ((body as Map)['queued'] as num?)?.toInt() ?? 0;
  }

  Future<List<Job>> jobs() async {
    final body = await _json(_client.get(_at('/api/jobs')), ApiFail.jobs);
    return body is List
        ? body.whereType<Map<String, dynamic>>().map(Job.fromJson).toList()
        : const [];
  }

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

  Future<bool> youtubeLoggedIn() async {
    final body = await _json(
      _client.get(_at('/api/youtube/status')),
      ApiFail.youtubeStatus,
    );
    return (body as Map)['loggedIn'] == true;
  }
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

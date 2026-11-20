import 'package:flutter/widgets.dart';

import 'api.dart';

/// 화면 문구입니다. 기기 언어가 한국어, 영어, 일본어면 그 말로, 아니면 영어로 보여줍니다.
/// 문구를 더할 때는 [S] 에 선언하고 세 언어 클래스에 모두 채웁니다. 하나라도 빠지면 컴파일이 멈춥니다.
abstract class S {
  const S();

  static const supported = [Locale('ko'), Locale('en'), Locale('ja')];

  static S forLanguage(String code) => switch (code) {
    'ko' => const _Ko(),
    'ja' => const _Ja(),
    _ => const _En(),
  };

  static S of(BuildContext context) =>
      forLanguage(Localizations.localeOf(context).languageCode);

  /// 기기 언어 목록에서 지원하는 첫 언어를 고릅니다. 없으면 영어입니다.
  static Locale resolve(List<Locale>? wanted, Iterable<Locale> _) {
    for (final l in wanted ?? const <Locale>[]) {
      final hit = supported.where((s) => s.languageCode == l.languageCode);
      if (hit.isNotEmpty) return hit.first;
    }
    return const Locale('en');
  }

  // 탭
  String get tabHome;
  String get tabLibrary;
  String get tabPlayer;
  String get tabAdd;
  String get tabConnect;

  // 보관함
  String get crateAll;
  String get crateLiked;
  String get crateSuno;
  String get crateYoutube;
  String libraryCount(int records, int likes);
  String get reload;
  String get emptyCrate;

  // 재생
  String get nowPlaying;
  String get hintStart;
  String get hintRestart;
  String get hintPrevRecord;
  String get hintNextRecord;
  String get noTrack;
  String get pickFromLibrary;
  String get prevTrack;
  String get nextTrack;
  String get rewinding;
  String get forwarding;
  String get spunFast;
  String get playing;
  String get paused;
  String get tapToPlay;
  String get playFromHere;
  String get offRecord;
  String get armLifted;
  String get cannotOpen;

  // 아래 조작 줄
  String get downloadStarted;
  String get downloadFailed;
  String get shuffle;
  String get shuffleOff;
  String get shuffleOnHint;
  String get shuffleOffHint;
  List<String> get repeatLabels;
  List<String> get repeatHints;
  String get like;
  String get saved;
  String get download;
  String get sleepTimer;
  String minutesTag(int m);
  String stopsIn(int m);
  String get timerOff;

  // 추가
  String get history;
  String get inputHint;
  String get submit;
  String queued(int n);
  String get alreadyHave;
  String get noneFound;
  String foundOnYoutube(int n);
  String get getQueued;
  String get get;
  String get jobDone;
  String get jobFailed;
  String get jobStopped;
  String get jobWaiting;
  String get youtube;
  String get suno;
  String get removeFromQueue;
  String get preparingNext;
  String get idle;
  String downloadingPct(int p);
  String recordingPct(int p);
  String nextCount(int n);
  String get tapeHint;
  String get stopJob;

  // 아직 없는 화면
  String get homeLater;
  String get connectLater;

  // 서버 오류
  String get unreachable;

  // 서버 연결과 앱 받기
  String get serverTitle;
  String get serverIntro;
  String get serverAddress;
  String get serverPassword;
  String get serverConnect;
  String get serverBadAddress;
  String get serverWrongPassword;
  String get serverNow;
  String get serverChange;
  String get androidApp;
  String get androidAppNote;
  String get androidGet;
  String androidBuild(String version, String size);
  // 기기 연결과 관리
  String get pairScan;
  String get pairScanHint;
  String get pairManual;
  String get pairCameraDenied;
  String get pairBadCode;
  String get pairConnecting;
  String get pairShowTitle;
  String get pairNew;
  String get devicesTitle;
  String get devicesNote;
  String get devicesNone;
  String get deviceAdd;
  String get deviceRemove;
  String get cancel;
  String get accountTitle;
  String get youtubeTitle;
  String get youtubeOn;
  String get youtubeOff;
  String get justNow;
  String get serverSection;
  String get appSection;
  String pairExpiresIn(int secs);
  String pairDone(String name);
  String deviceRemoveAsk(String name);
  String seenAgo(String when);
  String minutesAgo(int n);
  String hoursAgo(int n);
  String daysAgo(int n);
  String signedInAs(String who);
  String apiFail(ApiFail what);

  /// 오류를 한 줄로 바꿉니다. 서버가 화면 언어로 사유를 보냈으면 그 사유를 그대로 씁니다.
  String describe(Object error) {
    if (error is! ApiException) return unreachable;
    final head = apiFail(error.what);
    final detail = error.detail;
    if (detail != null && detail.isNotEmpty) return detail;
    return error.status == null ? head : '$head (${error.status})';
  }
}

class _Ko extends S {
  const _Ko();
  @override
  String get tabHome => '홈';
  @override
  String get tabLibrary => '보관함';
  @override
  String get tabPlayer => '재생';
  @override
  String get tabAdd => '추가';
  @override
  String get tabConnect => '연결';
  @override
  String get crateAll => '전체';
  @override
  String get crateLiked => '좋아요';
  @override
  String get crateSuno => '수노';
  @override
  String get crateYoutube => '유튜브';
  @override
  String libraryCount(int records, int likes) => '판 $records장 · 좋아요 $likes';
  @override
  String get reload => '다시 불러옵니다';
  @override
  String get emptyCrate => '이 분류에는 판이 없습니다';
  @override
  String get nowPlaying => '지금 재생';
  @override
  String get hintStart => '판을 톡 치거나 바늘을 내려 재생합니다';
  @override
  String get hintRestart => '처음으로 돌렸습니다';
  @override
  String get hintPrevRecord => '이전 판을 다시 올립니다';
  @override
  String get hintNextRecord => '다음 판을 올립니다';
  @override
  String get noTrack => '곡이 없습니다';
  @override
  String get pickFromLibrary => '보관함에서 곡을 고르면 여기 올라갑니다';
  @override
  String get prevTrack => '이전 곡';
  @override
  String get nextTrack => '다음 곡';
  @override
  String get rewinding => '뒤로 감는 중';
  @override
  String get forwarding => '앞으로 감는 중';
  @override
  String get spunFast => '빨리 돌렸습니다';
  @override
  String get playing => '재생 중';
  @override
  String get paused => '멈췄습니다';
  @override
  String get tapToPlay => '판을 톡 치면 재생합니다';
  @override
  String get playFromHere => '여기부터 재생합니다';
  @override
  String get offRecord => '판 밖입니다';
  @override
  String get armLifted => '바늘을 올렸습니다';
  @override
  String get cannotOpen => '곡을 열지 못했습니다';
  @override
  String get downloadStarted => '파일을 받습니다';
  @override
  String get downloadFailed => '파일을 받지 못했습니다';
  @override
  String get shuffle => '섞어 듣기';
  @override
  String get shuffleOff => '섞어 듣기 끄기';
  @override
  String get shuffleOnHint => '섞어 듣습니다';
  @override
  String get shuffleOffHint => '순서대로 듣습니다';
  @override
  List<String> get repeatLabels => const ['반복 끔', '전체 반복', '한 곡 반복'];
  @override
  List<String> get repeatHints => const [
    '반복하지 않습니다',
    '전체를 반복합니다',
    '이 곡만 반복합니다',
  ];
  @override
  String get like => '좋아요';
  @override
  String get saved => '받아 두었습니다';
  @override
  String get download => '파일 받기';
  @override
  String get sleepTimer => '잠들기 타이머';
  @override
  String minutesTag(int m) => '$m분';
  @override
  String stopsIn(int m) => '$m분 뒤에 멈춥니다';
  @override
  String get timerOff => '타이머를 껐습니다';
  @override
  String get history => '작업 기록';
  @override
  String get inputHint => '주소 또는 곡 이름';
  @override
  String get submit => '넣기';
  @override
  String queued(int n) => '$n곡을 대기열에 넣었습니다';
  @override
  String get alreadyHave => '이미 받았거나 대기 중인 곡입니다';
  @override
  String get noneFound => '찾은 곡이 없습니다';
  @override
  String foundOnYoutube(int n) => '유튜브에서 $n곡을 찾았습니다';
  @override
  String get getQueued => '받기를 걸었습니다';
  @override
  String get get => '받기';
  @override
  String get jobDone => '담았습니다';
  @override
  String get jobFailed => '실패했습니다';
  @override
  String get jobStopped => '멈췄습니다';
  @override
  String get jobWaiting => '기다리는 중';
  @override
  String get youtube => '유튜브';
  @override
  String get suno => '수노';
  @override
  String get removeFromQueue => '대기열에서 빼기';
  @override
  String get preparingNext => '다음 곡을 준비합니다';
  @override
  String get idle => '대기 중';
  @override
  String downloadingPct(int p) => '받는 중 $p%';
  @override
  String recordingPct(int p) => '녹음 중 $p%';
  @override
  String nextCount(int n) => '다음 $n곡';
  @override
  String get tapeHint => '주소를 넣으면 테이프가 들어갑니다';
  @override
  String get stopJob => '이 작업 멈추기';
  @override
  String get homeLater => '판 상자를 위아래로 넘기는 화면을 다음 단계에서 만듭니다';
  @override
  String get connectLater => '유튜브와 구글 드라이브 연결을 다음 단계에서 붙입니다';
  @override
  String get unreachable => '서버에 닿지 못했습니다';

  @override
  String get serverTitle => '서버 연결';
  @override
  String get serverIntro => 'Solo 서버 주소를 넣으면 이 기기에서 보관함을 듣습니다';
  @override
  String get serverAddress => '서버 주소';
  @override
  String get serverPassword => '비밀번호 (없으면 비워 둡니다)';
  @override
  String get serverConnect => '연결';
  @override
  String get serverBadAddress => '주소가 올바르지 않습니다';
  @override
  String get serverWrongPassword => '비밀번호가 맞지 않습니다';
  @override
  String get serverNow => '연결된 서버';
  @override
  String get serverChange => '서버 바꾸기';
  @override
  String get androidApp => '안드로이드 앱';
  @override
  String get androidAppNote => '앱으로 들으면 화면을 꺼도 재생이 이어집니다';
  @override
  String get androidGet => '앱 받기';
  @override
  String androidBuild(String version, String size) => '버전 $version · $size';
  // 기기 연결과 관리
  @override
  String get pairScan => 'QR로 연결';
  @override
  String get pairScanHint => '웹의 연결 탭에 뜬 QR을 비춥니다';
  @override
  String get pairManual => '주소로 직접 연결';
  @override
  String get pairCameraDenied => '카메라를 쓸 수 없습니다. 설정에서 카메라 권한을 켜 주세요';
  @override
  String get pairBadCode => 'Solo 연결 QR이 아닙니다';
  @override
  String get pairConnecting => '연결하는 중입니다';
  @override
  String get pairShowTitle => '앱에서 이 QR을 찍습니다';
  @override
  String get pairNew => '새 QR';
  @override
  String get devicesTitle => '기기';
  @override
  String get devicesNote => 'QR로 연결한 폰과 컴퓨터입니다';
  @override
  String get devicesNone => '아직 연결한 기기가 없습니다';
  @override
  String get deviceAdd => '새 기기 연결';
  @override
  String get deviceRemove => '연결 끊기';
  @override
  String get cancel => '취소';
  @override
  String get accountTitle => '계정';
  @override
  String get youtubeTitle => '유튜브 계정';
  @override
  String get youtubeOn => '로그인되어 있어 막힌 곡도 받습니다';
  @override
  String get youtubeOff => '로그인하지 않아 일부 곡은 받지 못합니다';
  @override
  String get justNow => '방금';
  @override
  String get serverSection => '서버';
  @override
  String get appSection => '앱';
  @override
  String pairExpiresIn(int secs) => '$secs초 뒤에 사라집니다';
  @override
  String pairDone(String name) => '$name 을(를) 연결했습니다';
  @override
  String deviceRemoveAsk(String name) =>
      '$name 의 연결을 끊습니다. 다시 쓰려면 QR로 새로 연결해야 합니다';
  @override
  String seenAgo(String when) => '마지막 접속 $when';
  @override
  String minutesAgo(int n) => '$n분 전';
  @override
  String hoursAgo(int n) => '$n시간 전';
  @override
  String daysAgo(int n) => '$n일 전';
  @override
  String signedInAs(String who) => '$who 로 들어와 있습니다';
  @override
  String apiFail(ApiFail what) => switch (what) {
    ApiFail.tracks => '곡 목록을 받지 못했습니다',
    ApiFail.like => '좋아요를 바꾸지 못했습니다',
    ApiFail.add => '주소를 넣지 못했습니다',
    ApiFail.search => '유튜브에서 찾지 못했습니다',
    ApiFail.get => '받기를 걸지 못했습니다',
    ApiFail.jobs => '작업 목록을 받지 못했습니다',
    ApiFail.cancel => '작업을 멈추지 못했습니다',
    ApiFail.remove => '곡을 빼지 못했습니다',
    ApiFail.restore => '곡을 되살리지 못했습니다',
    ApiFail.archive => '뺀 곡 목록을 받지 못했습니다',
    ApiFail.youtubeStatus => '유튜브 상태를 받지 못했습니다',
    ApiFail.app => '앱 정보를 받지 못했습니다',
    ApiFail.me => '로그인 정보를 받지 못했습니다',
    ApiFail.pair => '기기를 연결하지 못했습니다',
    ApiFail.devices => '기기 목록을 받지 못했습니다',
  };
}

class _En extends S {
  const _En();
  @override
  String get tabHome => 'Home';
  @override
  String get tabLibrary => 'Library';
  @override
  String get tabPlayer => 'Play';
  @override
  String get tabAdd => 'Add';
  @override
  String get tabConnect => 'Connect';
  @override
  String get crateAll => 'All';
  @override
  String get crateLiked => 'Liked';
  @override
  String get crateSuno => 'Suno';
  @override
  String get crateYoutube => 'YouTube';
  @override
  String libraryCount(int records, int likes) =>
      '$records ${records == 1 ? 'record' : 'records'} · $likes liked';
  @override
  String get reload => 'Try again';
  @override
  String get emptyCrate => 'No records here yet';
  @override
  String get nowPlaying => 'Now playing';
  @override
  String get hintStart => 'Tap the record or drop the needle to play';
  @override
  String get hintRestart => 'Back to the start';
  @override
  String get hintPrevRecord => 'Putting the last record back on';
  @override
  String get hintNextRecord => 'Putting on the next record';
  @override
  String get noTrack => 'Nothing to play';
  @override
  String get pickFromLibrary => 'Pick a song in your library to put it here';
  @override
  String get prevTrack => 'Previous song';
  @override
  String get nextTrack => 'Next song';
  @override
  String get rewinding => 'Rewinding';
  @override
  String get forwarding => 'Fast forwarding';
  @override
  String get spunFast => 'Spun it fast';
  @override
  String get playing => 'Playing';
  @override
  String get paused => 'Paused';
  @override
  String get tapToPlay => 'Tap the record to play';
  @override
  String get playFromHere => 'Playing from here';
  @override
  String get offRecord => 'Off the record';
  @override
  String get armLifted => 'Needle lifted';
  @override
  String get cannotOpen => 'Could not open this song';
  @override
  String get downloadStarted => 'Downloading the file';
  @override
  String get downloadFailed => 'Could not download the file';
  @override
  String get shuffle => 'Shuffle';
  @override
  String get shuffleOff => 'Turn off shuffle';
  @override
  String get shuffleOnHint => 'Shuffling';
  @override
  String get shuffleOffHint => 'Playing in order';
  @override
  List<String> get repeatLabels => const [
    'Repeat off',
    'Repeat all',
    'Repeat one',
  ];
  @override
  List<String> get repeatHints => const [
    'Not repeating',
    'Repeating everything',
    'Repeating this song',
  ];
  @override
  String get like => 'Like';
  @override
  String get saved => 'Saved';
  @override
  String get download => 'Download';
  @override
  String get sleepTimer => 'Sleep timer';
  @override
  String minutesTag(int m) => '${m}m';
  @override
  String stopsIn(int m) => 'Stops in $m minutes';
  @override
  String get timerOff => 'Timer off';
  @override
  String get history => 'History';
  @override
  String get inputHint => 'Link or song name';
  @override
  String get submit => 'Add';
  @override
  String queued(int n) =>
      n == 1 ? 'Added 1 song to the queue' : 'Added $n songs to the queue';
  @override
  String get alreadyHave => 'Already saved or in the queue';
  @override
  String get noneFound => 'No songs found';
  @override
  String foundOnYoutube(int n) =>
      n == 1 ? 'Found 1 song on YouTube' : 'Found $n songs on YouTube';
  @override
  String get getQueued => 'Download queued';
  @override
  String get get => 'Get';
  @override
  String get jobDone => 'Saved';
  @override
  String get jobFailed => 'Failed';
  @override
  String get jobStopped => 'Stopped';
  @override
  String get jobWaiting => 'Waiting';
  @override
  String get youtube => 'YouTube';
  @override
  String get suno => 'Suno';
  @override
  String get removeFromQueue => 'Remove from queue';
  @override
  String get preparingNext => 'Getting the next song ready';
  @override
  String get idle => 'Idle';
  @override
  String downloadingPct(int p) => 'Downloading $p%';
  @override
  String recordingPct(int p) => 'Recording $p%';
  @override
  String nextCount(int n) => '$n up next';
  @override
  String get tapeHint => 'Add a link and a tape goes in';
  @override
  String get stopJob => 'Stop this job';
  @override
  String get homeLater =>
      'The record crate you flip through comes in the next step';
  @override
  String get connectLater => 'YouTube and Google Drive come in the next step';
  @override
  String get unreachable => 'Could not reach the server';

  @override
  String get serverTitle => 'Connect to a server';
  @override
  String get serverIntro =>
      'Enter your Solo server address to play your shelf on this device';
  @override
  String get serverAddress => 'Server address';
  @override
  String get serverPassword => 'Password (leave empty if none)';
  @override
  String get serverConnect => 'Connect';
  @override
  String get serverBadAddress => 'That address does not look right';
  @override
  String get serverWrongPassword => 'Wrong password';
  @override
  String get serverNow => 'Connected server';
  @override
  String get serverChange => 'Change server';
  @override
  String get androidApp => 'Android app';
  @override
  String get androidAppNote => 'The app keeps playing with the screen off';
  @override
  String get androidGet => 'Get the app';
  @override
  String androidBuild(String version, String size) =>
      'Version $version · $size';
  // 기기 연결과 관리
  @override
  String get pairScan => 'Connect with QR';
  @override
  String get pairScanHint => 'Point at the QR on the web Connect tab';
  @override
  String get pairManual => 'Connect by address';
  @override
  String get pairCameraDenied =>
      'Camera is unavailable. Allow camera access in settings';
  @override
  String get pairBadCode => 'This is not a Solo pairing QR';
  @override
  String get pairConnecting => 'Connecting';
  @override
  String get pairShowTitle => 'Scan this QR in the app';
  @override
  String get pairNew => 'New QR';
  @override
  String get devicesTitle => 'Devices';
  @override
  String get devicesNote => 'Phones and computers paired with a QR';
  @override
  String get devicesNone => 'No devices paired yet';
  @override
  String get deviceAdd => 'Pair a device';
  @override
  String get deviceRemove => 'Unpair';
  @override
  String get cancel => 'Cancel';
  @override
  String get accountTitle => 'Account';
  @override
  String get youtubeTitle => 'YouTube account';
  @override
  String get youtubeOn => 'Signed in, so restricted songs download too';
  @override
  String get youtubeOff => 'Not signed in, so some songs cannot be downloaded';
  @override
  String get justNow => 'just now';
  @override
  String get serverSection => 'Server';
  @override
  String get appSection => 'App';
  @override
  String pairExpiresIn(int secs) => 'Expires in ${secs}s';
  @override
  String pairDone(String name) => 'Paired $name';
  @override
  String deviceRemoveAsk(String name) =>
      'Unpair $name? It will need a new QR to connect again';
  @override
  String seenAgo(String when) => 'Last seen $when';
  @override
  String minutesAgo(int n) => '${n}m ago';
  @override
  String hoursAgo(int n) => '${n}h ago';
  @override
  String daysAgo(int n) => '${n}d ago';
  @override
  String signedInAs(String who) => 'Signed in as $who';
  @override
  String apiFail(ApiFail what) => switch (what) {
    ApiFail.tracks => 'Could not load your songs',
    ApiFail.like => 'Could not change the like',
    ApiFail.add => 'Could not add that link',
    ApiFail.search => 'YouTube search failed',
    ApiFail.get => 'Could not queue the download',
    ApiFail.jobs => 'Could not load the jobs',
    ApiFail.cancel => 'Could not stop the job',
    ApiFail.remove => 'Could not remove the song',
    ApiFail.restore => 'Could not restore the song',
    ApiFail.archive => 'Could not load removed songs',
    ApiFail.youtubeStatus => 'Could not check YouTube',
    ApiFail.app => 'Could not load the app details',
    ApiFail.me => 'Could not check who is signed in',
    ApiFail.pair => 'Could not pair the device',
    ApiFail.devices => 'Could not load the devices',
  };
}

class _Ja extends S {
  const _Ja();
  @override
  String get tabHome => 'ホーム';
  @override
  String get tabLibrary => 'ライブラリ';
  @override
  String get tabPlayer => '再生';
  @override
  String get tabAdd => '追加';
  @override
  String get tabConnect => '連携';
  @override
  String get crateAll => 'すべて';
  @override
  String get crateLiked => 'いいね';
  @override
  String get crateSuno => 'Suno';
  @override
  String get crateYoutube => 'YouTube';
  @override
  String libraryCount(int records, int likes) => 'レコード $records枚 · いいね $likes';
  @override
  String get reload => 'もう一度読み込む';
  @override
  String get emptyCrate => 'ここにはまだレコードがありません';
  @override
  String get nowPlaying => '再生中';
  @override
  String get hintStart => 'レコードをタップするか針を落とすと再生します';
  @override
  String get hintRestart => '最初に戻しました';
  @override
  String get hintPrevRecord => '前のレコードを戻します';
  @override
  String get hintNextRecord => '次のレコードをのせます';
  @override
  String get noTrack => '曲がありません';
  @override
  String get pickFromLibrary => 'ライブラリで曲を選ぶとここにのります';
  @override
  String get prevTrack => '前の曲';
  @override
  String get nextTrack => '次の曲';
  @override
  String get rewinding => '巻き戻し中';
  @override
  String get forwarding => '早送り中';
  @override
  String get spunFast => '勢いよく回しました';
  @override
  String get playing => '再生中';
  @override
  String get paused => '止めました';
  @override
  String get tapToPlay => 'レコードをタップすると再生します';
  @override
  String get playFromHere => 'ここから再生します';
  @override
  String get offRecord => 'レコードの外です';
  @override
  String get armLifted => '針を上げました';
  @override
  String get cannotOpen => '曲を開けませんでした';
  @override
  String get downloadStarted => 'ファイルを保存します';
  @override
  String get downloadFailed => 'ファイルを保存できませんでした';
  @override
  String get shuffle => 'シャッフル';
  @override
  String get shuffleOff => 'シャッフルをオフ';
  @override
  String get shuffleOnHint => 'シャッフルで再生します';
  @override
  String get shuffleOffHint => '順番に再生します';
  @override
  List<String> get repeatLabels => const ['リピートオフ', '全曲リピート', '1曲リピート'];
  @override
  List<String> get repeatHints => const [
    'リピートしません',
    '全曲をリピートします',
    'この曲だけリピートします',
  ];
  @override
  String get like => 'いいね';
  @override
  String get saved => '保存済み';
  @override
  String get download => 'ファイルを保存';
  @override
  String get sleepTimer => 'スリープタイマー';
  @override
  String minutesTag(int m) => '$m分';
  @override
  String stopsIn(int m) => '$m分後に止まります';
  @override
  String get timerOff => 'タイマーをオフにしました';
  @override
  String get history => '履歴';
  @override
  String get inputHint => 'リンクまたは曲名';
  @override
  String get submit => '追加';
  @override
  String queued(int n) => '$n曲をキューに入れました';
  @override
  String get alreadyHave => '保存済みか、すでにキューにある曲です';
  @override
  String get noneFound => '曲が見つかりませんでした';
  @override
  String foundOnYoutube(int n) => 'YouTubeで$n曲見つかりました';
  @override
  String get getQueued => '保存を予約しました';
  @override
  String get get => '保存';
  @override
  String get jobDone => '保存しました';
  @override
  String get jobFailed => '失敗しました';
  @override
  String get jobStopped => '止めました';
  @override
  String get jobWaiting => '待機中';
  @override
  String get youtube => 'YouTube';
  @override
  String get suno => 'Suno';
  @override
  String get removeFromQueue => 'キューから外す';
  @override
  String get preparingNext => '次の曲を準備しています';
  @override
  String get idle => '待機中';
  @override
  String downloadingPct(int p) => '保存中 $p%';
  @override
  String recordingPct(int p) => '録音中 $p%';
  @override
  String nextCount(int n) => '次の$n曲';
  @override
  String get tapeHint => 'リンクを入れるとテープが入ります';
  @override
  String get stopJob => 'この作業を止める';
  @override
  String get homeLater => 'レコード箱をめくる画面は次の段階で作ります';
  @override
  String get connectLater => 'YouTube と Google ドライブの連携は次の段階で付けます';
  @override
  String get unreachable => 'サーバーにつながりませんでした';

  @override
  String get serverTitle => 'サーバーに接続';
  @override
  String get serverIntro => 'Solo サーバーのアドレスを入れると、この端末でライブラリを聴けます';
  @override
  String get serverAddress => 'サーバーのアドレス';
  @override
  String get serverPassword => 'パスワード (なければ空のまま)';
  @override
  String get serverConnect => '接続';
  @override
  String get serverBadAddress => 'アドレスが正しくありません';
  @override
  String get serverWrongPassword => 'パスワードが違います';
  @override
  String get serverNow => '接続中のサーバー';
  @override
  String get serverChange => 'サーバーを変える';
  @override
  String get androidApp => 'Android アプリ';
  @override
  String get androidAppNote => 'アプリなら画面を消しても再生が続きます';
  @override
  String get androidGet => 'アプリを入手';
  @override
  String androidBuild(String version, String size) => 'バージョン $version · $size';
  // 기기 연결과 관리
  @override
  String get pairScan => 'QR で接続';
  @override
  String get pairScanHint => 'Web の連携タブに出た QR を映します';
  @override
  String get pairManual => 'アドレスで接続';
  @override
  String get pairCameraDenied => 'カメラを使えません。設定でカメラを許可してください';
  @override
  String get pairBadCode => 'Solo の接続 QR ではありません';
  @override
  String get pairConnecting => '接続しています';
  @override
  String get pairShowTitle => 'アプリでこの QR を読み取ります';
  @override
  String get pairNew => '新しい QR';
  @override
  String get devicesTitle => '端末';
  @override
  String get devicesNote => 'QR で接続したスマホとパソコンです';
  @override
  String get devicesNone => '接続した端末はまだありません';
  @override
  String get deviceAdd => '端末を追加';
  @override
  String get deviceRemove => '接続を解除';
  @override
  String get cancel => 'キャンセル';
  @override
  String get accountTitle => 'アカウント';
  @override
  String get youtubeTitle => 'YouTube アカウント';
  @override
  String get youtubeOn => 'ログイン済みなので制限のある曲も保存できます';
  @override
  String get youtubeOff => 'ログインしていないため一部の曲は保存できません';
  @override
  String get justNow => 'たった今';
  @override
  String get serverSection => 'サーバー';
  @override
  String get appSection => 'アプリ';
  @override
  String pairExpiresIn(int secs) => '$secs 秒後に消えます';
  @override
  String pairDone(String name) => '$name を接続しました';
  @override
  String deviceRemoveAsk(String name) => '$name の接続を解除します。再び使うには QR で接続し直します';
  @override
  String seenAgo(String when) => '最終接続 $when';
  @override
  String minutesAgo(int n) => '$n 分前';
  @override
  String hoursAgo(int n) => '$n 時間前';
  @override
  String daysAgo(int n) => '$n 日前';
  @override
  String signedInAs(String who) => '$who でログインしています';
  @override
  String apiFail(ApiFail what) => switch (what) {
    ApiFail.tracks => '曲の一覧を読み込めませんでした',
    ApiFail.like => 'いいねを変更できませんでした',
    ApiFail.add => 'リンクを追加できませんでした',
    ApiFail.search => 'YouTube の検索に失敗しました',
    ApiFail.get => '保存を予約できませんでした',
    ApiFail.jobs => '作業の一覧を読み込めませんでした',
    ApiFail.cancel => '作業を止められませんでした',
    ApiFail.remove => '曲を外せませんでした',
    ApiFail.restore => '曲を戻せませんでした',
    ApiFail.archive => '外した曲の一覧を読み込めませんでした',
    ApiFail.youtubeStatus => 'YouTube の状態を確認できませんでした',
    ApiFail.app => 'アプリの情報を取得できませんでした',
    ApiFail.me => 'ログイン情報を取得できませんでした',
    ApiFail.pair => '端末を接続できませんでした',
    ApiFail.devices => '端末の一覧を取得できませんでした',
  };
}

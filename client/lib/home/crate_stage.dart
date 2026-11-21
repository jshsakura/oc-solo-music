import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api.dart';
import '../widgets/artist_tag.dart';
import '../theme.dart';
import '../widgets/skeleton.dart';
import '../widgets/sleeve.dart';
import 'crate_math.dart';
import 'crate_parts.dart';

/// 판 상자를 그리는 기준 크기입니다. 화면에 맞춰 통째로 줄어듭니다.
const stageWidth = 390.0;
const stageHeight = 470.0;
const _size = 270.0;
const _left = (stageWidth - _size) / 2;
const _top = stageHeight - 40 - _size;
const _discSize = 240.0;
const _discRise = 150.0;
const _perspective = 900.0;

/// 불러오는 동안 상자에 세워 둘 빈 판의 수입니다.
const _skeletonCount = 4;

/// 이 커브들은 시안의 CSS 전이를 그대로 옮긴 것입니다. 끝에서 살짝 튕깁니다.
const discCurve = Cubic(.3, 1.3, .5, 1);
const _pillCurve = Cubic(.3, 1.8, .5, 1);

/// 상자 안의 판들과 상자, 꺼낸 판 위의 올리기 버튼입니다. 상태는 갖지 않습니다.
class CrateStage extends StatelessWidget {
  const CrateStage({
    super.key,
    required this.api,
    required this.tracks,
    required this.position,
    required this.pulled,
    required this.isOut,
    required this.hint,
    required this.loadLabel,
    required this.loadSemantics,
    required this.onLoad,
    this.message,
    this.skeleton = false,
  });

  final Api api;
  final List<Track> tracks;
  final double position;

  /// 맨 앞 판에서 레코드가 빠져나온 정도입니다. 0 이면 슬리브 안, 1 이면 다 나온 상태입니다.
  final double pulled;
  final bool isOut;
  final String hint;
  final String loadLabel;
  final String loadSemantics;
  final VoidCallback onLoad;

  /// 상자가 비었을 때 판 대신 보여줄 문장입니다.
  final String? message;

  /// 곡 목록을 받는 동안입니다. 판 대신 같은 자리에 빈 판을 세우고 안내 문장은 막대로 둡니다.
  final bool skeleton;

  @override
  Widget build(BuildContext context) {
    final n = skeleton ? _skeletonCount : tracks.length;
    final pos = n == 0 ? 0.0 : position.clamp(-0.3, n - 0.7);
    final front = frontIndex(pos, n);
    final from = math.max(0, (pos - 1.6).floor());
    final to = math.min(n - 1, (pos + 6).ceil());
    final sleeves = [
      for (var i = from; i <= to; i++) (i, sleevePose(i - pos, i)),
    ]..sort((a, b) => a.$2.layer.compareTo(b.$2.layer));

    return SizedBox(
      width: stageWidth,
      height: stageHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 넘겨서 앞으로 쓰러진 판이 상자 아래로 삐져나오지 않게 판들만 자릅니다.
          // Stack 의 clipBehavior 는 변환을 보지 않으므로 ClipRect 로 직접 자릅니다.
          Positioned.fill(
            child: ClipRect(
              child: Stack(
                children: [
                  const Positioned(
                    left: (stageWidth - 314) / 2,
                    bottom: 66,
                    width: 314,
                    height: 26,
                    child: CrateBackLip(),
                  ),
                  for (final (i, pose) in sleeves)
                    if (pose.opacity > 0)
                      _placed(
                        i,
                        pose,
                        i == front && (i - pos).abs() < 0.3 ? pulled : 0,
                      ),
                ],
              ),
            ),
          ),
          const Positioned(
            left: (stageWidth - 330) / 2,
            bottom: 0,
            width: 330,
            height: 84,
            child: CrateBox(),
          ),
          if (skeleton)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 22,
              child: Center(
                child: TextBone(
                  style: TextStyle(fontSize: 12),
                  width: 150,
                  color: Palette.line,
                ),
              ),
            )
          else if (message == null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 22,
              child: Text(
                hint,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Palette.faint),
              ),
            )
          else
            Positioned(
              left: 50,
              right: 50,
              top: 0,
              bottom: 110,
              child: Center(
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Palette.secondary,
                  ),
                ),
              ),
            ),
          Positioned(
            left: (stageWidth - _discSize) / 2,
            top: _top + 15 - _discRise,
            width: _discSize,
            height: _discSize,
            child: IgnorePointer(
              ignoring: !isOut,
              child: Semantics(
                button: true,
                label: loadSemantics,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onLoad,
                    child: Center(child: _pill(context)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(BuildContext context) {
    final still = MediaQuery.disableAnimationsOf(context);
    final d = still ? Duration.zero : const Duration(milliseconds: 350);
    return AnimatedOpacity(
      opacity: isOut ? 1 : 0,
      duration: still ? Duration.zero : const Duration(milliseconds: 200),
      child: AnimatedScale(
        scale: isOut ? 1 : 0.4,
        duration: d,
        curve: _pillCurve,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Palette.butter,
            borderRadius: BorderRadius.circular(100),
            boxShadow: [
              BoxShadow(
                color: Palette.ink.withValues(alpha: .25),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.play_arrow_rounded,
                size: 16,
                color: Palette.ink,
              ),
              const SizedBox(width: 6),
              Text(
                loadLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Palette.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placed(int i, SleevePose pose, double pulled) {
    final body = Transform(
      transform: _matrix(pose),
      child: skeleton
          ? const _SleeveBone()
          : _SleeveBody(track: tracks[i], api: api, pulled: pulled),
    );
    return Positioned(
      left: _left,
      top: _top,
      width: _size,
      height: _size,
      child: pose.opacity >= 1
          ? body
          : Opacity(opacity: pose.opacity, child: body),
    );
  }
}

/// 시안의 `perspective: 900px` 은 상자 한가운데가 시점이고, 판은 아래쪽 가운데를 축으로 돕니다.
/// 둘 다 판 자신의 좌표로 옮겨서 한 행렬로 합칩니다.
Matrix4 _matrix(SleevePose pose) {
  const px = stageWidth / 2 - _left;
  const py = stageHeight / 2 - _top;
  const ox = _size / 2;
  const oy = _size;
  return Matrix4.translationValues(px, py, 0)
    ..multiply(Matrix4.identity()..setEntry(3, 2, -1 / _perspective))
    ..multiply(Matrix4.translationValues(ox - px, oy - py + pose.dy, pose.dz))
    ..multiply(Matrix4.rotationX(pose.tilt * math.pi / 180))
    ..multiply(Matrix4.translationValues(-ox, -oy, 0));
}

class _SleeveBody extends StatelessWidget {
  const _SleeveBody({
    required this.track,
    required this.api,
    required this.pulled,
  });
  final Track track;
  final Api api;
  final double pulled;

  @override
  Widget build(BuildContext context) {
    final onCover = track.hasCover;
    final ink = onCover ? Palette.surface : Palette.ink;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 15,
          top: 15,
          width: _discSize,
          height: _discSize,
          child: Transform.translate(
            offset: Offset(0, -_discRise * pulled),
            child: Transform.rotate(
              angle: 40 * math.pi / 180 * pulled,
              child: const RecordDisc(),
            ),
          ),
        ),
        Sleeve(track: track, api: api, size: _size, radius: 12),
        if (onCover)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [.4, .85],
                  colors: [
                    Palette.ink.withValues(alpha: 0),
                    Palette.ink.withValues(alpha: .6),
                  ],
                ),
              ),
            ),
          ),
        // 판 아랫부분 44px 은 상자 앞판에 가리므로 제목은 그 위에 둡니다.
        Positioned(
          left: 18,
          right: 18,
          bottom: 54,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              const SizedBox(height: 4),
              ArtistTag(track.artist, color: ink),
            ],
          ),
        ),
      ],
    );
  }
}

/// 곡 목록을 받는 동안 상자에 세워 두는 빈 판입니다. 제목과 이름 자리에 막대를 둡니다.
/// 빛줄기는 상자 전체를 감싼 [Skeleton] 이 한 번에 지나가게 합니다.
class _SleeveBone extends StatelessWidget {
  const _SleeveBone();

  @override
  Widget build(BuildContext context) => Container(
    width: _size,
    height: _size,
    decoration: BoxDecoration(
      color: Palette.sunk,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Palette.line),
    ),
    padding: const EdgeInsets.fromLTRB(18, 0, 18, 54),
    alignment: Alignment.bottomLeft,
    child: const Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextBone(
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          width: 150,
          color: Palette.line,
        ),
        TextBone(
          style: TextStyle(fontSize: 12),
          width: 90,
          color: Palette.line,
        ),
      ],
    ),
  );
}

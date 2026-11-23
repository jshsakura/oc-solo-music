import 'package:flutter/material.dart';

import '../api.dart';
import '../l10n.dart';
import '../theme.dart';
import 'sleeve.dart';

/// 곡 하나를 길게 누르거나 오른쪽 클릭하면 고를 수 있는 동작입니다.
enum TrackAction { play, like, download, remove }

/// 화면이 곡의 메뉴를 열어 달라고 위로 알리는 콜백입니다. [at] 이 있으면 마우스 클릭 위치입니다.
typedef TrackMenuCallback = void Function(Track track, Offset? at);

/// 고른 동작만 돌려줍니다. 실행은 부른 쪽이 합니다.
/// [at] 이 없으면(손가락 길게 누르기) 아래에서 올라오는 시트를, 있으면(마우스 오른쪽 클릭) 그 자리에 팝업을 엽니다.
Future<TrackAction?> showTrackMenu(
  BuildContext context, {
  required Track track,
  required Api api,
  Offset? at,
}) {
  final s = S.of(context);
  final items = [
    (TrackAction.play, Icons.play_arrow_rounded, s.menuPlay),
    (
      TrackAction.like,
      track.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      track.liked ? s.menuUnlike : s.like,
    ),
    (TrackAction.download, Icons.download_rounded, s.download),
    (TrackAction.remove, Icons.remove_circle_outline_rounded, s.menuRemove),
  ];
  Color colorOf(TrackAction a) =>
      a == TrackAction.remove ? Palette.bad : Palette.ink;

  if (at != null) {
    final box = Overlay.of(context).context.findRenderObject()! as RenderBox;
    return showMenu<TrackAction>(
      context: context,
      color: Palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Palette.line),
      ),
      position: RelativeRect.fromRect(
        Rect.fromPoints(at, at),
        Offset.zero & box.size,
      ),
      items: [
        for (final (a, icon, label) in items)
          PopupMenuItem(
            value: a,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: colorOf(a)),
                const SizedBox(width: 12),
                Flexible(
                  child: Text(label, style: TextStyle(color: colorOf(a))),
                ),
              ],
            ),
          ),
      ],
    );
  }

  return showModalBottomSheet<TrackAction>(
    context: context,
    backgroundColor: Palette.surface,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                Sleeve(track: track, api: api, size: 48, radius: 8),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (track.artist.isNotEmpty)
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Palette.secondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Palette.sunk),
          // 낮은 화면(가로 휴대폰)에서는 줄만 스크롤됩니다.
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final (a, icon, label) in items)
                    ListTile(
                      leading: Icon(icon, color: colorOf(a)),
                      title: Text(
                        label,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colorOf(a),
                        ),
                      ),
                      onTap: () => Navigator.pop(sheet, a),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

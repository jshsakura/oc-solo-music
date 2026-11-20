import 'package:flutter/material.dart';

import '../theme.dart';

// 판 상자의 그림 조각들입니다. 크기와 자리는 `CrateStage` 가 정합니다.

/// 슬리브에서 빠져나오는 검은 레코드입니다.
class RecordDisc extends StatelessWidget {
  const RecordDisc({super.key});

  @override
  Widget build(BuildContext context) {
    final groove = Border.all(color: Palette.surface.withValues(alpha: .08));
    return DecoratedBox(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Palette.ink,
      ),
      child: Stack(
        children: [
          for (final inset in const [30.0, 60.0])
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.all(inset),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: groove,
                  ),
                ),
              ),
            ),
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Palette.butter,
              ),
              alignment: Alignment.center,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Palette.ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CrateBackLip extends StatelessWidget {
  const CrateBackLip({super.key});

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Palette.line, Palette.sunk],
      ),
    ),
  );
}

class CrateBox extends StatelessWidget {
  const CrateBox({super.key});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(22),
        bottom: Radius.circular(24),
      ),
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0, .6, 1],
        colors: [
          Palette.surface,
          Palette.surface,
          Color.lerp(Palette.surface, Palette.ground, .7)!,
        ],
      ),
      border: Border.all(color: Palette.line),
      boxShadow: [
        BoxShadow(
          color: Palette.ink.withValues(alpha: .18),
          blurRadius: 18,
          spreadRadius: -10,
          offset: const Offset(0, -10),
        ),
        BoxShadow(
          color: Palette.ink.withValues(alpha: .08),
          blurRadius: 26,
          offset: const Offset(0, 12),
        ),
      ],
    ),
    child: Align(
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.only(top: 14),
        width: 72,
        height: 12,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0, .4],
            colors: [Color.lerp(Palette.sunk, Palette.ink, .14)!, Palette.sunk],
          ),
        ),
      ),
    ),
  );
}

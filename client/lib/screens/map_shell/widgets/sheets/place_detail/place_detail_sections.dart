import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import 'korean_line_break.dart';

/// 한 줄 소개 섹션.
///
/// 흰 시트 위에 흰 카드를 얹으면 테두리가 구분하는 대상이 없어 상자만 늘어난다.
/// 소개는 본문 문단 그대로 두고 여백으로만 앞뒤와 떨어뜨린다.
class PlaceSummarySection extends StatelessWidget {
  const PlaceSummarySection({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const style = RoutexTypography.body;
      return Text(
        balancedKoreanLines(
          text,
          style: style,
          maxWidth: constraints.maxWidth,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        ),
        style: style,
      );
    },
  );
}

/// 특징 표시 묶음.
///
/// **누르는 것이 아니다.** 예전에는 Material `Chip`이라 알약 모양이었는데, 바로 위
/// 지도의 분류 칩과 같은 모양이라 눌러 보고 아무 일도 없는 것을 겪게 된다. 읽기만
/// 하는 표시는 배지로 그린다.
class PlaceTagsSection extends StatelessWidget {
  const PlaceTagsSection({super.key, required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: RoutexSpacing.controlGap,
    runSpacing: RoutexSpacing.controlGap,
    children: [
      for (final tag in tags)
        RoutexBadge(label: tag, tone: RoutexBadgeTone.info),
    ],
  );
}

/// 기간이 명시된 안내. 서버 검증기가 만료된 notice를 막기 때문에 여기서는
/// 날짜를 판단하지 않고 API가 준 문자열을 그대로 표시한다.
class PlaceNoticeSection extends StatelessWidget {
  const PlaceNoticeSection({super.key, required this.text, this.until});

  final String text;
  final String? until;

  @override
  Widget build(BuildContext context) => RoutexSurface(
    role: RoutexSurfaceRole.flat,
    child: RoutexInset(
      role: RoutexInsetRole.component,
      child: RoutexInfoRow(
        // 라벨은 확성기 아이콘이 대신한다. 값이 곧 공지 문장이라 그 위에 '공지'를
        // 한 번 더 적으면 같은 말이 두 줄을 쓴다.
        label: '공지',
        value: text,
        icon: Icons.campaign_outlined,
        caption: until == null ? null : '$until까지',
      ),
    ),
  );
}

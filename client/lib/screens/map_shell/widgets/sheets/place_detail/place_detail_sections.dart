import 'package:flutter/material.dart';
import 'package:routex_design_system/routex_design_system.dart';

import '../../../../../theme/app_theme.dart';
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

/// MapLibre 미리보기는 첫 프레임에 별도 지도·타일 요청을 만들기 때문에 이 Wave에서
/// 넣지 않는다. 이 섹션은 위치가 있다는 사실만 가볍게 알려 주고, 실제 지도 이동은
/// 기존 지도 화면과 후속 상호작용에 맡긴다.
///
/// **눌리는 것처럼 보이면 안 된다.** 탭 핸들러가 없으므로 화살표 같은 버튼
/// 기표를 두지 않는다. 지도 이동을 붙이는 날 그때 버튼으로 바꾼다.
class PlaceMapSection extends StatelessWidget {
  const PlaceMapSection({super.key, this.floorLabel});

  final String? floorLabel;

  @override
  Widget build(BuildContext context) {
    final label = floorLabel == null || floorLabel!.isEmpty
        ? '지도에서 위치 확인'
        : '${floorLabel!} 위치';
    return _TintedBlock(
      child: Row(
        children: [
          const Icon(Icons.place_outlined, color: AppColors.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 배경색으로만 구분하는 블록. 공지·지도 바로가기처럼 "본문이 아니라 하나의
/// 덩어리"인 것에만 쓴다. 테두리는 두지 않는다 — 배경색만으로 이미 구분된다.
class _TintedBlock extends StatelessWidget {
  const _TintedBlock({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppColors.blue50,
      borderRadius: BorderRadius.circular(12),
    ),
    child: child,
  );
}

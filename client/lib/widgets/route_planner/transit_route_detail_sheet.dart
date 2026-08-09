import 'package:flutter/material.dart';

import '../../models/transit_route.dart';
import '../../theme/app_theme.dart';
import '../sheet_grab_handle.dart';
import '../transit_style.dart';

/// 고른 대중교통 경로 하나를 지도와 함께 보여 주는 **끌어 올릴 수 있는** 시트.
///
/// 크기를 바꿀 수 있어야 하는 이유는 이 화면이 두 가지를 동시에 답하기
/// 때문이다 — "어디로 가는 길인가"(지도)와 "무엇을 타고 어디서 갈아타는가"
/// (구간 목록). 고정 높이면 둘 중 하나는 항상 잘린다. 손잡이를 끌어 지도를 더
/// 보거나 구간을 끝까지 읽을 수 있게 둔다.
///
/// 머리의 X는 **닫기가 아니라 목록으로 되돌아가기**다. 사용자가 여기까지 온
/// 경위가 "후보 목록에서 하나를 골랐다"이므로, 돌아갈 곳은 지도가 아니라 그
/// 목록이다 — 지도로 닫아 버리면 다른 후보를 보려고 처음부터 다시 조회하게 된다.
class TransitRouteDetailSheet extends StatelessWidget {
  const TransitRouteDetailSheet({
    super.key,
    required this.itinerary,
    required this.originLabel,
    required this.destinationLabel,
    required this.onBackToList,
    required this.onStart,
    this.departAt,
  });

  final TransitItinerary itinerary;
  final String originLabel;
  final String destinationLabel;

  /// X — 대중교통 후보 목록 화면으로 되돌아간다.
  final VoidCallback onBackToList;

  /// "안내시작" — 길찾기 화면을 닫고 지도 위 안내로 넘어간다.
  final VoidCallback onStart;

  /// 출발 기준 시각. 후보를 조회한 시각을 그대로 쓰므로, 시트를 열어 둔 채
  /// 시간이 흘러도 숫자가 저 혼자 바뀌지 않는다. null이면 시각 줄을 뺀다.
  final DateTime? departAt;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.18,
      maxChildSize: 0.92,
      builder: (context, scrollController) => Material(
        color: Colors.white,
        elevation: 12,
        shadowColor: Colors.black.withValues(alpha: 0.2),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListView(
          controller: scrollController,
          padding: EdgeInsets.only(
            bottom: 16 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            // 손잡이는 반드시 스크롤 콘텐츠 안에 있어야 실제로 끌린다
            // ([SheetGrabHandle] 주석).
            const SheetGrabHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 8, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _Summary(itinerary: itinerary, departAt: departAt),
                  ),
                  IconButton(
                    key: const Key('transit-detail-back'),
                    onPressed: onBackToList,
                    icon: const Icon(Icons.close, color: AppColors.muted),
                    tooltip: '대중교통 목록으로',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
              child: _LegBar(legs: itinerary.legs),
            ),
            const Divider(height: 1),
            _Steps(
              itinerary: itinerary,
              originLabel: originLabel,
              destinationLabel: destinationLabel,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('transit-detail-start'),
                  onPressed: onStart,
                  icon: const Icon(Icons.navigation_rounded, size: 18),
                  label: const Text('안내시작'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.itinerary, required this.departAt});

  final TransitItinerary itinerary;
  final DateTime? departAt;

  @override
  Widget build(BuildContext context) {
    final depart = departAt;
    final fare = itinerary.fare;
    final facts = [
      if (depart != null)
        '${_clock(depart)} - '
            '${_clock(depart.add(Duration(seconds: itinerary.totalTimeSeconds)))}',
      if (fare != null && fare > 0) formatTransitFare(fare),
      itinerary.transferCount == 0 ? '환승 없음' : '환승 ${itinerary.transferCount}회',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatTransitDuration(itinerary.totalTimeSeconds),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: AppColors.text,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          facts.join(' · '),
          style: const TextStyle(fontSize: 13, color: AppColors.muted),
        ),
      ],
    );
  }

  /// "오후 9:53". 24시간제 숫자만 적으면 밤 9시와 아침 9시가 같아 보인다.
  static String _clock(DateTime time) {
    final isMorning = time.hour < 12;
    final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    return '${isMorning ? '오전' : '오후'} $hour12:$minute';
  }
}

/// 구간을 소요 시간 **비율대로** 늘어놓는 가로 막대.
///
/// 칩을 나란히 놓는 것과 다르다. 칩은 "무엇을 타는가"만 말하고, 이 막대는
/// "그중 어디에 시간이 쏠려 있는가"까지 말한다 — 53분 버스 한 번과 5분 도보를
/// 같은 크기로 그리면 그 여정이 사실상 버스 한 번이라는 게 안 읽힌다.
class _LegBar extends StatelessWidget {
  const _LegBar({required this.legs});

  final List<TransitLeg> legs;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 26,
      child: Row(
        children: [
          for (final leg in legs)
            Expanded(
              // 0초 구간이 섞이면 flex가 0이 되어 아예 안 그려진다. 최소 1을
              // 줘서 짧은 구간도 실선으로는 남게 한다.
              flex: leg.sectionTimeSeconds.clamp(1, 24 * 60 * 60).toInt(),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: leg.mode.isWalk
                      ? const Color(0xFFE9ECEF)
                      : transitLegColor(leg),
                  borderRadius: BorderRadius.circular(6),
                ),
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      formatTransitDuration(leg.sectionTimeSeconds),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: leg.mode.isWalk
                            ? const Color(0xFF5F6B76)
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 출발지 → 구간 → 도착지를 세로로 잇는 목록.
class _Steps extends StatelessWidget {
  const _Steps({
    required this.itinerary,
    required this.originLabel,
    required this.destinationLabel,
  });

  final TransitItinerary itinerary;
  final String originLabel;
  final String destinationLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Endpoint(label: originLabel, isStart: true),
        for (final leg in itinerary.legs) _LegRow(leg: leg),
        _Endpoint(label: destinationLabel, isStart: false),
      ],
    );
  }
}

class _Endpoint extends StatelessWidget {
  const _Endpoint({required this.label, required this.isStart});

  final String label;
  final bool isStart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          Icon(
            isStart ? Icons.trip_origin : Icons.place,
            size: 18,
            color: isStart ? AppColors.primary : AppColors.dest,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegRow extends StatelessWidget {
  const _LegRow({required this.leg});

  final TransitLeg leg;

  @override
  Widget build(BuildContext context) {
    final duration = formatTransitDuration(leg.sectionTimeSeconds);
    if (leg.mode.isWalk) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 6),
        child: Row(
          children: [
            const Icon(
              Icons.directions_walk_rounded,
              size: 18,
              color: AppColors.muted,
            ),
            const SizedBox(width: 10),
            Text(
              '도보 ${formatTransitDistance(leg.distanceMeters)} ($duration)',
              style: const TextStyle(fontSize: 13.5, color: AppColors.muted),
            ),
          ],
        ),
      );
    }
    // 탈것 구간은 **어디서 타고 어디서 내리는지**가 핵심이다. 노선명만 적으면
    // 사용자가 정류장 이름을 다시 찾아야 한다.
    final stops = leg.stationCount > 0
        ? '${leg.stationCount}개 정류장 · $duration'
        : duration;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                transitModeIcon(leg.mode),
                size: 18,
                color: transitLegColor(leg),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  leg.startName ?? leg.modeLabel,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 28, top: 4),
            child: Row(
              children: [
                TransitLegChip(leg: leg),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    stops,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.muted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (leg.endName != null)
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 6),
              child: Text(
                '${leg.endName} 하차',
                style: const TextStyle(
                  fontSize: 13.5,
                  color: AppColors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

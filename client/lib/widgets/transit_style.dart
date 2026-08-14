import 'package:flutter/material.dart';

import '../models/route/transit_route.dart';

/// 대중교통 화면(경로 목록 시트·요약 카드·지도 경로선)이 공유하는 표현 규칙.
///
/// 한곳에 모으는 이유는 **같은 노선이 세 군데에 동시에 보이기 때문**이다.
/// 시트의 칩, 하단 요약 카드, 지도 위 선이 서로 다른 색이면 사용자는 그것이
/// 같은 구간인지 알 수 없다.

/// 수단별 기본색. 노선 고유색이 없을 때만 쓴다.
///
/// 서울 기준 관습색을 따른다 — 버스는 파랑(간선), 지하철은 남색 계열. 어떤
/// 노선인지 모를 때도 "탈것"과 "도보"가 한눈에 갈리는 게 목적이다.
Color transitModeColor(TransitMode mode) => switch (mode) {
  TransitMode.walk => const Color(0xFF7A8794),
  TransitMode.bus => const Color(0xFF0068B7),
  TransitMode.subway => const Color(0xFF3A5DAE),
  TransitMode.train => const Color(0xFF4B6A2E),
  TransitMode.expressBus => const Color(0xFF8A5A2B),
  TransitMode.airplane => const Color(0xFF2E7D8F),
  TransitMode.ferry => const Color(0xFF1B7A6B),
  TransitMode.unknown => const Color(0xFF5F6B76),
};

/// 이 구간을 그릴 색. TMAP이 준 노선 고유색이 있으면 그것을 우선한다 —
/// 사용자가 역 안내판에서 보는 색과 같아야 "그 파란 버스"가 맞는지 안다.
Color transitLegColor(TransitLeg leg) {
  final hex = leg.routeColorHex;
  if (hex == null) return transitModeColor(leg.mode);
  final value = int.tryParse(hex.substring(1), radix: 16);
  if (value == null) return transitModeColor(leg.mode);
  return Color(0xFF000000 | value);
}

/// 지도 소스에 실어 보낼 `#RRGGBB` 문자열. MapLibre 표현식이 문자열만 받는다.
String transitLegColorHex(TransitLeg leg) {
  final hex = leg.routeColorHex;
  if (hex != null) return hex;
  final color = transitModeColor(leg.mode);
  final rgb = color.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

IconData transitModeIcon(TransitMode mode) => switch (mode) {
  TransitMode.walk => Icons.directions_walk_rounded,
  TransitMode.bus => Icons.directions_bus_rounded,
  TransitMode.subway => Icons.subway_rounded,
  TransitMode.train => Icons.train_rounded,
  TransitMode.expressBus => Icons.airport_shuttle_rounded,
  TransitMode.airplane => Icons.flight_rounded,
  TransitMode.ferry => Icons.directions_boat_rounded,
  TransitMode.unknown => Icons.alt_route_rounded,
};

/// 초 → "1시간 12분" / "24분".
///
/// 0분으로 내려가지 않게 최소 1분으로 올린다. "0분"은 사용자에게 "안 걸린다"가
/// 아니라 "계산이 안 됐다"로 읽힌다.
String formatTransitDuration(int seconds) {
  final minutes = (seconds / 60).ceil().clamp(1, 24 * 60);
  if (minutes < 60) return '$minutes분';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours시간' : '$hours시간 $rest분';
}

/// m → "480m" / "12.4km".
String formatTransitDistance(double meters) {
  if (meters < 1000) return '${meters.round()}m';
  return '${(meters / 1000).toStringAsFixed(1)}km';
}

/// 요금 → "1,500원". 천 단위 구분자를 직접 넣는다(intl 의존 없이).
String formatTransitFare(int fare) {
  final digits = fare.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '$buffer원';
}

/// 경로 한 줄 요약의 수단 칩. 목록·요약 카드가 같은 모양을 쓴다.
class TransitLegChip extends StatelessWidget {
  const TransitLegChip({super.key, required this.leg, this.compact = false});

  final TransitLeg leg;

  /// 좁은 자리(요약 카드)에서는 시간 표기를 뺀다.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = transitLegColor(leg);
    // 도보는 노선명이 없으므로 소요 시간을 라벨로 쓴다 — "도보"만 적으면
    // 몇 분을 걷는지가 목록에서 사라진다.
    final label = leg.mode.isWalk
        ? formatTransitDuration(leg.sectionTimeSeconds)
        : leg.shortLabel;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 7 : 9, vertical: 4),
      decoration: BoxDecoration(
        color: leg.mode.isWalk ? const Color(0xFFF1F3F5) : color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            transitModeIcon(leg.mode),
            size: compact ? 13 : 14,
            color: leg.mode.isWalk ? const Color(0xFF5F6B76) : Colors.white,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
              color: leg.mode.isWalk ? const Color(0xFF5F6B76) : Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

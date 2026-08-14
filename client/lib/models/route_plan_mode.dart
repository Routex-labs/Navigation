import 'package:flutter/material.dart';

/// 목적지까지 **어떻게 갈지**.
///
/// 순서가 화면 순서다 — 자동차 · 대중교통 · 도보. 국내 지도 앱들이 쓰는 순서와
/// 같게 두어야 사용자가 아이콘 위치를 기억한 대로 누를 수 있다.
///
/// **자전거는 없다.** TMAP에 자전거 경로 API가 없어서, 탭만 만들어 두면 눌러도
/// 아무 일이 없는 죽은 버튼이 된다 — 사용자는 그것을 "고장"으로 읽지
/// "지원 안 함"으로 읽지 않는다.
enum RoutePlanMode {
  car,
  transit,
  walk;

  String get label => switch (this) {
    RoutePlanMode.car => '자동차',
    RoutePlanMode.transit => '대중교통',
    RoutePlanMode.walk => '도보',
  };

  IconData get icon => switch (this) {
    RoutePlanMode.car => Icons.directions_car_rounded,
    RoutePlanMode.transit => Icons.directions_bus_rounded,
    RoutePlanMode.walk => Icons.directions_walk_rounded,
  };
}

/// 상단 길찾기 바에서 지금 글자를 치고 있는 칸.
enum RoutePlanField { origin, destination }

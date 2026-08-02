import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// 경로선 스타일. 실내 화면([FloorPlanView])과 야외 지도가 같은 경로를 그리므로
/// 두 곳이 같은 값을 써야 한다.
///
/// 예전에는 두 파일이 각자 값을 갖고 있었고 실제로 어긋나 있었다 — 야외는
/// 흰 casing 8px + 불투명 본선, 실내는 casing 없이 `lineOpacity: 0.6`. 같은 경로가
/// 화면을 옮길 때마다 다르게 보였다.
///
/// ## casing이 흰색이면 안 되는 이유
///
/// 실내 도면 바닥이 `#FFFFFF`다. 흰 선 위의 흰 테두리는 보이지 않는다. 네이버·
/// 카카오가 경로선에 **진한 파랑 테두리**를 쓰는 것도 같은 이유다 — 밝은 배경이든
/// 어두운 배경이든 선이 배경에서 떠 보이게 만드는 건 색조가 아니라 명도 차다.
/// 흰색은 그 안에서 화살표가 맡는다.

/// 경로선 테두리. 본선보다 어두운 같은 계열이다.
const kRouteCasingColor = '#1B57C4';

/// 지나온 구간. 남은 거리를 직관적으로 보여 준다.
const kRouteCompletedColor = '#9AA0A6';

/// 본선·테두리 두께. zoom을 따라 같이 커진다 — 고정 두께면 축소했을 때 선이
/// 도면을 덮고 확대했을 때는 실처럼 가늘어 보인다.
const kRouteCasingWidthExpr = [
  'interpolate',
  ['linear'],
  ['zoom'],
  16,
  7.0,
  20,
  11.0,
];

const kRouteLineWidthExpr = [
  'interpolate',
  ['linear'],
  ['zoom'],
  16,
  4.5,
  20,
  7.0,
];

/// 층 전환 구간은 본선보다 얇게 둔다. 수평 이동이 아니라서 같은 무게로 그리면
/// 실제로 걸어가는 구간과 구분이 안 된다.
const kRouteTransferWidthExpr = [
  'interpolate',
  ['linear'],
  ['zoom'],
  16,
  4.0,
  20,
  6.0,
];

/// 진행 방향 화살표 비트맵의 addImage 등록 키. 디자인을 바꾸면 버전을 올린다 —
/// 웹 addImage는 같은 이름이 이미 있으면 새 비트맵을 버린다.
const kRouteArrowImageName = 'route-direction-arrow-v2';

/// 축소할수록 진행 방향 화살표를 더 자주 배치하기 위한 화면 픽셀 간격.
///
/// `symbol-spacing`은 지도 길이가 아니라 화면 픽셀 기준이다. 고정값이면 경로를
/// 화면에 맞추며 축소했을 때 경로의 투영 길이만 짧아져 화살표가 너무 적어진다.
/// z16의 40px은 가장 작은 화살표(약 13px)의 세 배라 서로 겹치지 않고, z20에서는
/// 72px까지 넓혀 확대 화면에서 선을 덮지 않는다.
const kRouteArrowSpacingExpr = [
  'interpolate',
  ['linear'],
  ['zoom'],
  16,
  40.0,
  18,
  56.0,
  20,
  72.0,
];

/// 화살표를 얹는 심볼 레이어 속성.
///
/// `symbolPlacement: 'line'`이면 MapLibre가 선을 따라 일정 간격으로 아이콘을
/// 배치하고 진행 방향으로 회전시킨다. 이게 선을 "그려진 선"에서 "가야 할 길"로
/// 바꾸는 지점이다 — 구글·네이버·카카오가 모두 쓰는 표현이다.
///
/// ⚠️ **층 전환 구간에는 얹지 않는다.** 그 구간은 이미 점선이고, 수평 이동이
/// 아니라 층 이동이라 방향 화살표의 의미가 다르다.
SymbolLayerProperties routeArrowProps() => const SymbolLayerProperties(
  iconImage: kRouteArrowImageName,
  iconSize: [
    'interpolate',
    ['linear'],
    ['zoom'],
    16,
    0.28,
    20,
    0.42,
  ],
  symbolPlacement: 'line',
  symbolSpacing: kRouteArrowSpacingExpr,
  // 회전은 지도 기준이어야 선을 따라 눕는다. viewport 기준이면 화면이 회전할 때
  // 화살표만 제자리에 서서 선과 어긋난다.
  iconRotationAlignment: 'map',
  iconAllowOverlap: true,
  iconIgnorePlacement: true,
);

/// 흰 chevron 비트맵. 글씨가 아니라 도형이라 캔버스에 구워도 안전하다
/// (한글 글리프 문제는 텍스트에만 해당한다).
///
/// **오른쪽을 향하도록** 그린다. `symbolPlacement: 'line'`은 아이콘의 +x축(오른쪽)
/// 을 선의 진행 방향에 맞춰 회전시킨다 — 위를 향하게 그리면 90° 틀어져 보인다.
/// Mapbox·MapLibre 기본 스타일의 일방통행 화살표가 모두 오른쪽을 보는 이유다.
Future<Uint8List> renderRouteArrowIcon() async {
  const size = 48.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));

  final paint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 7
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  canvas.drawPath(
    Path()
      ..moveTo(18, 12)
      ..lineTo(32, size / 2)
      ..lineTo(18, 36),
    paint,
  );

  final image = await recorder.endRecording().toImage(
    size.toInt(),
    size.toInt(),
  );
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

/// 본선 색. [AppColors.primary]와 같은 값이다.
///
/// 지도 스타일은 hex 문자열만 받는데 Color를 문자열로 바꾸는 확장이 화면 계층
/// (`indoor_overlay_layers.dart`)에 있어, core에서 쓰면 의존 방향이 뒤집힌다.
/// 그래서 값을 고정한다 — [AppColors.primary]를 바꾸면 여기도 같이 바꾼다.
const kRouteLineColor = '#4A87F1';

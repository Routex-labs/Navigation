import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// 경로선 스타일. 실내·야외가 **한 벌을 공유한다** — 각자 값을 갖고 있어 같은
/// 경로가 화면을 옮길 때마다 다르게 보였다.
///
/// **casing은 흰색이면 안 된다** — 실내 도면 바닥이 `#FFFFFF`다. 근거는
/// `docs/client/map-ui-redesign-plan.md` 5번 항목.

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

/// 화살표 간격(화면 px). `symbol-spacing`은 지도 길이가 아니라 화면 픽셀 기준이라,
/// 고정값이면 축소했을 때 화살표가 너무 적어진다.
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

/// 화살표를 얹는 심볼 레이어 속성. `symbolPlacement: 'line'`이 선을 따라 배치하고
/// 진행 방향으로 회전시킨다.
///
/// ⚠️ **층 전환 구간에는 얹지 않는다** — 이미 점선이고 방향의 의미가 다르다.
SymbolLayerProperties routeArrowProps() => const SymbolLayerProperties(
  iconImage: kRouteArrowImageName,
  iconSize: [
    'interpolate',
    ['linear'],
    ['zoom'],
    16,
    0.36,
    20,
    0.52,
  ],
  symbolPlacement: 'line',
  symbolSpacing: kRouteArrowSpacingExpr,
  // 회전은 지도 기준이어야 선을 따라 눕는다. viewport 기준이면 화면이 회전할 때
  // 화살표만 제자리에 서서 선과 어긋난다.
  iconRotationAlignment: 'map',
  iconAllowOverlap: true,
  iconIgnorePlacement: true,
);

/// 흰 chevron 비트맵. 도형이라 캔버스에 구워도 안전하다(한글 글리프 문제는
/// 텍스트에만 해당한다).
///
/// **오른쪽을 향하도록** 그린다 — `line` 배치는 아이콘의 +x축을 진행 방향에 맞춰
/// 회전시키므로, 위를 향하게 그리면 90° 틀어져 보인다.
Future<Uint8List> renderRouteArrowIcon() async {
  const size = 48.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));

  final paint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeWidth = 9
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

/// **걷는 구간**의 선 색. 회색 점선으로 그린다.
///
/// 타고 가는 구간(파란 실선)과 색부터 갈라 둔다. 정류장까지 걸어가는 길과
/// 버스를 타고 가는 길이 같은 파란 선이면, 사용자는 어디서 내려 걸어야 하는지
/// 를 선 굵기나 점선 여부로 추론해야 한다 — 색이 다르면 그냥 보인다.
const kRouteWalkColor = '#8A9199';

/// 걷는 구간의 점선 패턴. 회색 선과 함께 "여기는 정해진 길이 아니라 대략
/// 이쪽"이라는 뜻을 전한다.
const kRouteWalkDashArray = [1.4, 1.1];

/// 구간 시작점에 얹는 수단 배지의 addImage 등록 키.
///
/// 이름에 버전을 달아 둔다. 웹 addImage는 같은 이름이 이미 있으면 새 비트맵을
/// 버리므로, 모양을 바꿀 때 이름도 함께 올려야 살아 있는 지도에 반영된다.
/// (v2에서 [kRouteModeBadgeCanvasSize]를 두 배로 키웠다.)
const kRouteWalkBadgeImageName = 'route-badge-walk-v2';
const kRouteBusBadgeImageName = 'route-badge-bus-v2';
const kRouteSubwayBadgeImageName = 'route-badge-subway-v2';

/// 수단 배지 비트맵 한 변의 길이(px).
///
/// **화면 크기는 이 값 × [routeModeBadgeProps]의 `iconSize`다.** 키울 때는 iconSize가
/// 아니라 이 값을 올린다 — iconSize > 1이면 원본을 늘려 그려 획이 뭉개진다.
/// 아래 반지름·글자 크기가 전부 여기서 파생되므로 위 이름의 버전도 함께 올린다.
const kRouteModeBadgeCanvasSize = 112.0;

/// 수단 배지 한 장을 굽는다 — 색 원판 위에 흰 아이콘. 선 색만으로는 "어디까지
/// 걷고 어디서 타는지"의 경계가 몇 픽셀이라 안 보인다.
Future<Uint8List> renderModeBadgeIcon(IconData icon, Color background) async {
  const size = kRouteModeBadgeCanvasSize;
  // 흰 테두리 두께와 글자 크기는 한 변 길이에서 비례로 뽑는다. 상수로 박아 두면
  // [kRouteModeBadgeCanvasSize]를 바꿀 때 테두리만 얇아지거나 아이콘만 작아진다.
  const rimWidth = size * 3 / 56;
  const glyphSize = size * 30 / 56;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, size, size));

  // 흰 테두리를 두른 원판. 지도 배경이 밝든 어둡든 배지가 떠 보이게 한다.
  canvas.drawCircle(
    const Offset(size / 2, size / 2),
    size / 2 - size / 56,
    Paint()..color = Colors.white,
  );
  canvas.drawCircle(
    const Offset(size / 2, size / 2),
    size / 2 - size / 56 - rimWidth,
    Paint()..color = background,
  );

  final painter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: glyphSize,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: Colors.white,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(
    canvas,
    Offset((size - painter.width) / 2, (size - painter.height) / 2),
  );

  final image = await recorder.endRecording().toImage(
    size.toInt(),
    size.toInt(),
  );
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

/// 구간 시작 배지 레이어. [imageName]을 상수로 박고 어떤 feature를 그릴지는
/// 호출부가 필터로 정한다 — `iconImage` 표현식은 이 바인딩에서 조용히 실패한다
/// (아이콘이 안 뜨는데 오류도 없다). `iconSize`는 [kRouteModeBadgeCanvasSize] 대비
/// 배율이다.
SymbolLayerProperties routeModeBadgeProps(String imageName) =>
    SymbolLayerProperties(
      iconImage: imageName,
      iconSize: const [
        'interpolate',
        ['linear'],
        ['zoom'],
        13,
        0.34,
        18,
        0.52,
      ],
      // 화살표와 달리 **화면 기준**이다. 배지는 선을 따라 눕는 것이 아니라 늘
      // 똑바로 서 있어야 아이콘이 읽힌다.
      iconRotationAlignment: 'viewport',
      iconAllowOverlap: true,
      iconIgnorePlacement: true,
    );

/// 건물 **안** 구간의 선 색. 야외 본선([kRouteLineColor])과 **같은 색**이다.
///
/// 한때 연한 파랑으로 뺐다가 되돌렸다 — 실내 바닥이 밝아 배경에 묻히고, 실내
/// 구간만 남으면 비교 대상도 사라진다. 두 구간을 가르는 일은 색이 아니라
/// **점선/실선**([kRouteWalkDashArray])이 맡는다.
const kRouteIndoorLineColor = kRouteLineColor;

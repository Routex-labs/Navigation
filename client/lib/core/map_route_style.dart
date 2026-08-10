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
/// **화면에 찍히는 크기는 이 값 × [routeModeBadgeProps]의 `iconSize`다.** 처음엔
/// 56px로 구웠는데, iconSize가 0.34~0.52라 실제로는 19~29px밖에 안 됐다 — 옆에
/// 적히는 매장 이름 글자보다 작아서 "여기서 내려 걷는다"는 경계가 눈에 안 들어
/// 왔다. iconSize는 그대로 두고 비트맵만 두 배로 키워 화면 크기를 두 배로 만든다.
///
/// iconSize를 올리지 않고 비트맵을 키우는 이유: iconSize > 1이면 MapLibre가 원본
/// 보다 큰 크기로 늘려 그려서 원 테두리와 아이콘 획이 뭉개진다. 아래 모든 반지름·
/// 글자 크기가 이 값에서 비례로 파생되므로, 크기를 다시 조정할 때는 여기만 바꾸고
/// 위 이름의 버전을 올린다.
const kRouteModeBadgeCanvasSize = 112.0;

/// 수단 배지 한 장을 굽는다 — 색 원판 위에 흰 아이콘.
///
/// 선 색만으로는 "어디까지 걷고 어디서 타는지"의 **경계**가 안 보인다. 색이
/// 바뀌는 지점을 눈으로 찾아야 하는데, 구간이 짧으면 그 지점이 몇 픽셀이다.
/// 시작점에 아이콘을 하나 찍으면 경계가 점이 되어 바로 읽힌다.
///
/// 아이콘은 Material 글리프를 그대로 굽는다. 한글 글리프 문제는 텍스트에만
/// 해당하고([renderRouteArrowIcon] 주석), 아이콘 폰트는 앱에 함께 실린다.
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

/// 구간 시작 배지 레이어. [imageName] 하나만 그리고, 어떤 feature를 그릴지는
/// 호출부가 필터로 정한다 — `iconImage`에 표현식을 넣는 방식은 이 바인딩에서
/// 조용히 실패할 수 있어(아이콘이 안 뜨는데 오류도 없다) 이름을 상수로 박는다.
///
/// `iconSize`는 **비트맵 대비 배율**이라 이 값만으로는 화면 크기를 알 수 없다.
/// 실제 크기는 [kRouteModeBadgeCanvasSize] × 아래 배율이다 — 배지를 키우려면
/// 그 상수를 올린다(1을 넘는 배율은 비트맵을 늘려 그려서 뭉개진다).
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
/// 한때 연한 파랑(`#A8C6F6`)으로 뺐다. "지금 걸을 길은 진하고 나중에 걸을 길은
/// 연하다"는 규칙이었는데, 실기기에서는 그 규칙이 읽히기 전에 선이 먼저 안 보였다
/// — 실내 도면 바닥이 밝은 회백색이라 연한 파랑이 배경에 묻히고, 건물에 들어가
/// 실내 구간만 남은 뒤에는 비교 대상이 사라져 그냥 흐린 선 하나가 된다.
///
/// 밖에서 두 구간을 가르는 일은 색이 아니라 **점선/실선**이 맡는다(야외 도보는
/// [kRouteWalkDashArray] 점선, 실내는 실선). 진하기는 "보이느냐"의 문제라
/// 구분에 쓰기에는 대가가 너무 크다.
const kRouteIndoorLineColor = kRouteLineColor;

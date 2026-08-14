import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// 수직이동 구조물 폴리곤을 초록톤으로 덧칠하기 위한 name 매칭 값. 벡터 타일에
/// category 속성이 없어 name으로 매칭하고, 어긋나면 하이라이트만 빠진다.
///
/// fill·라벨·아이콘 레이어가 각자 이 이름을 보므로 한 곳에 있어야 한다.
const kVerticalTransportStoreNames = <String>[
  '에스컬레이터',
  '엘리베이터',
  '유아차 전용 E/V',
];

/// 매장명 라벨에서 **아이콘이 이미 말해 주는 것**을 걸러내는 필터. 둘을 뺀다.
///
/// **수직이동 시설**(에스컬레이터 152·엘리베이터 68개)은 이름 자체가 중복이라
/// 도면을 도배했다. **편의시설**은 이름을 살려야 하지만(「ATM (하나은행)」) 전용
/// 아이콘 레이어가 이미 있어, 여기서 빼고 텍스트 전용 레이어가 이름만 그린다.
///
/// fill 필터(`any` + `==`)와 정확히 반대 집합이라 한쪽을 고치면 다른 쪽도 본다.
List<Object> storeLabelWithCategoryIconFilter() => [
  'all',
  for (final name in kVerticalTransportStoreNames)
    [
      '!=',
      ['get', 'name'],
      name,
    ],
  for (final name in kStoreFacilityStyleByName.keys)
    [
      '!=',
      ['get', 'name'],
      name,
    ],
];

/// 편의시설의 **텍스트 전용** 라벨 필터. [storeLabelWithCategoryIconFilter]가
/// 뺀 집합을 정확히 되받아, 아이콘 없이 이름만 그리는 레이어에 건다.
/// 아이콘은 `floor-store-facility-icons`(야외는 대응 레이어)가 그린다.
List<Object> facilityStoreLabelFilter() => [
  'any',
  for (final name in kStoreFacilityStyleByName.keys)
    [
      '==',
      ['get', 'name'],
      name,
    ],
];

/// 이름을 **그리면 안 되는** POI `type`. 이들의 `name`은 노드 식별자 그대로라
/// (`ES1-DN(FR3F)`) 한 층에 영문 코드가 200개 넘게 떠 있었다.
///
/// **아이콘은 남긴다** — 위치는 필요하고 종류는 [kPoiIconByType]이 말한다.
const kVerticalTransportPoiTypes = <String>[
  'elevator',
  'escalator',
  'vertical-connection',
];

/// POI 이름 라벨 필터. [kVerticalTransportPoiTypes]를 뺀 나머지만 이름을 그린다.
///
/// `!=`의 `all`을 쓴다 — `match`·`in`이 native에서 예외도 로그도 없이 매치 0건이
/// 되던 전례가 있다(map-style-rules.md 0절).
List<Object> poiLabelFilter() => [
  'all',
  for (final type in kVerticalTransportPoiTypes)
    [
      '!=',
      ['get', 'type'],
      type,
    ],
];

/// POI `type` 속성(백엔드 실데이터 값)을 지도 위 아이콘에 매핑한다. 건물마다
/// 명명이 조금씩 달라(더현대는 elevator/escalator/toilet/exit, 다른 데이터셋은
/// vertical-connection/core-entrance 등) 여러 값을 같은 아이콘으로 묶는다.
/// 매핑에 없는 값(facility/poi 등)은 [kDefaultPoiIcon]으로 그린다.
const kPoiIconByType = <String, IconData>{
  'elevator': Icons.elevator,
  'vertical-connection': Icons.elevator,
  'escalator': Icons.escalator,
  'toilet': Icons.wc,
  'exit': Icons.exit_to_app,
  'core-entrance': Icons.exit_to_app,
  'facility': Icons.info_outline,
};
const kDefaultPoiIcon = Icons.place;
const kPoiIconBackgroundColor = Color(0xFF76AE6D);

/// 실내 지도 위 **모든 마커의 지름(논리 px)**. 편의시설·POI·대분류 배지가 전부
/// 이 하나를 쓴다 — 두 벌로 두면 한쪽만 조정할 때마다 다시 갈라진다.
///
/// 값의 근거와 "더 키우려면 캔버스도 함께 올린다"는 제약은
/// `docs/client/map-style-rules.md` 7절.
const kIndoorMarkerLogicalPx = 12.0;

/// 아이콘 비트맵 캔버스 한 변(px). [renderPoiIconPng] 등이 굽는 크기이자
/// `icon-size` 1.0일 때 화면에 그려지는 **물리** 픽셀 수다.
const kIconCanvasPx = 96.0;

/// [kIndoorMarkerLogicalPx]를 `icon-size` 값으로 환산한다.
///
/// **네이티브에서만 배율을 곱한다** — 웹은 비트맵을 `pixelRatio: 1`로 등록해
/// `icon-size`가 이미 논리 픽셀이다(근거·실측: map-style-rules.md 7절).
///
/// [isWeb]은 테스트가 두 갈래를 고정할 수 있게 뚫어 둔 구멍이다.
double indoorMarkerIconSize(double devicePixelRatio, {bool? isWeb}) =>
    kIndoorMarkerLogicalPx *
    ((isWeb ?? kIsWeb) ? 1.0 : devicePixelRatio) /
    kIconCanvasPx;

/// 이름이 이 표에 있는 시설(화장실·정수기 등)은 라벨 옆에 종류별 아이콘을 얹는다.
/// 이 시설들은 `pois`가 아니라 `stores` 레이어로 들어와 POI 매핑에 안 걸린다.
///
/// **subcategory가 아니라 name으로 매칭한다** — 화장실과 장애인화장실은
/// subcategory가 같은 `생활편의`인데 아이콘은 달라야 한다.
///
/// duo 스타일에서 left/rightBackground는 배경색이 아니라 **좌/우 아이콘 색**이다.
const kStoreFacilityStyleByName = <String, FacilityIconStyle>{
  '화장실': FacilityIconStyle.duo(
    leftIcon: Icons.man,
    leftBackground: Color(0xFF1E88E5),
    rightIcon: Icons.woman,
    rightBackground: Color(0xFFEC407A),
  ),
  '장애인화장실': FacilityIconStyle(
    icon: Icons.accessible,
    background: Color(0xFF1565C0),
  ),
  '정수기': FacilityIconStyle(
    icon: Icons.water_drop_outlined,
    background: kPoiIconBackgroundColor,
  ),
  '수유실': FacilityIconStyle(
    icon: Icons.child_friendly,
    background: kPoiIconBackgroundColor,
  ),
  '흡연실 (전자담배 전용)': FacilityIconStyle(
    icon: Icons.smoking_rooms,
    background: kPoiIconBackgroundColor,
  ),
  'ATM (하나은행)': FacilityIconStyle(
    icon: Icons.local_atm,
    background: kPoiIconBackgroundColor,
  ),
  '취식 가능장소': FacilityIconStyle(
    icon: Icons.dining_outlined,
    background: kPoiIconBackgroundColor,
  ),
};

/// 편의시설 아이콘 스타일. 단일 아이콘 모드와 좌/우 반원을 서로 다른 색으로
/// 나눠 두 아이콘을 얹는 duo 모드를 지원한다(화장실 남/여 표현용).
class FacilityIconStyle {
  const FacilityIconStyle({required this.icon, required this.background})
    : leftIcon = null,
      leftBackground = null,
      rightIcon = null,
      rightBackground = null;

  const FacilityIconStyle.duo({
    required IconData this.leftIcon,
    required Color this.leftBackground,
    required IconData this.rightIcon,
    required Color this.rightBackground,
  }) : icon = Icons.wc,
       background = const Color(0xFF9E9E9E);

  final IconData icon;
  final Color background;
  final IconData? leftIcon;
  final Color? leftBackground;
  final IconData? rightIcon;
  final Color? rightBackground;

  bool get isDuo => leftIcon != null;
}

/// [MapLibreMapController.addImage]에 등록할 때 쓰는 이름. 같은 아이콘을 여러
/// type이 공유할 수 있으므로 type이 아니라 아이콘 자체를 키로 삼아 중복
/// 렌더링/등록을 피한다.
String poiIconImageName(IconData icon) => 'poi-icon-${icon.codePoint}';

/// 편의시설 아이콘은 이름별로 배경색/구성이 달라(화장실 duo, 장애인화장실 파랑
/// 등) 아이콘 codePoint만으로는 구분되지 않는다. 시설 이름을 그대로 키로 삼아
/// addImage에 등록한다.
String facilityIconImageName(String facilityName) =>
    'facility-icon-$facilityName';

/// Material 아이콘 글리프를 흰 테두리 + 초록 원 배경 위에 흰색으로 그려 PNG
/// 바이트로 오프스크린 렌더링한다. MapLibre 심볼 레이어는 미리 등록된 비트맵
/// 이미지만 참조할 수 있어서, 폰트 글리프를 직접 캔버스에 그려 이미지로 바꿔야
/// 한다.
Future<Uint8List> renderPoiIconPng(IconData icon) async {
  const canvasSize = 96.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    const Rect.fromLTWH(0, 0, canvasSize, canvasSize),
  );
  const center = Offset(canvasSize / 2, canvasSize / 2);

  canvas.drawCircle(center, canvasSize / 2, Paint()..color = Colors.white);
  canvas.drawCircle(
    center,
    canvasSize / 2 - 5,
    Paint()..color = kPoiIconBackgroundColor,
  );

  paintIconGlyph(
    canvas,
    icon: icon,
    color: Colors.white,
    fontSize: canvasSize * 0.55,
    center: center,
  );

  final image = await recorder.endRecording().toImage(
    canvasSize.toInt(),
    canvasSize.toInt(),
  );
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

/// 편의시설(화장실·정수기·수유실 등)용 아이콘 렌더러. 단일 배경색 모드와 좌/우
/// 반원을 다른 색으로 나눠 아이콘을 두 개 얹는 duo 모드를 지원한다. duo 모드는
/// 화장실을 파랑(남)·분홍(여)으로 한눈에 구분되게 만들 때 쓴다.
Future<Uint8List> renderFacilityIconPng(FacilityIconStyle style) async {
  const canvasSize = 96.0;
  const radius = canvasSize / 2;
  const innerRadius = canvasSize / 2 - 5;
  const center = Offset(canvasSize / 2, canvasSize / 2);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    const Rect.fromLTWH(0, 0, canvasSize, canvasSize),
  );

  canvas.drawCircle(center, radius, Paint()..color = Colors.white);

  if (style.isDuo) {
    canvas.drawCircle(center, innerRadius, Paint()..color = Colors.white);
    paintIconGlyph(
      canvas,
      icon: style.leftIcon!,
      color: style.leftBackground!,
      fontSize: canvasSize * 0.48,
      center: const Offset(canvasSize * 0.29, canvasSize / 2),
    );
    paintIconGlyph(
      canvas,
      icon: style.rightIcon!,
      color: style.rightBackground!,
      fontSize: canvasSize * 0.48,
      center: const Offset(canvasSize * 0.71, canvasSize / 2),
    );
  } else {
    canvas.drawCircle(center, innerRadius, Paint()..color = style.background);
    paintIconGlyph(
      canvas,
      icon: style.icon,
      color: Colors.white,
      fontSize: canvasSize * 0.55,
      center: center,
    );
  }

  final image = await recorder.endRecording().toImage(
    canvasSize.toInt(),
    canvasSize.toInt(),
  );
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

/// Material 아이콘 글리프를 캔버스 임의 위치에 그린다. POI·편의시설·대분류
/// ([category_map_icon.dart]) 아이콘이 모두 같은 방식으로 비트맵을 만들기 때문에
/// 이 함수만 공유한다.
void paintIconGlyph(
  Canvas canvas, {
  required IconData icon,
  required Color color,
  required double fontSize,
  required Offset center,
}) {
  final textPainter = TextPainter(textDirection: TextDirection.ltr)
    ..text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: fontSize,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: color,
      ),
    )
    ..layout();
  textPainter.paint(
    canvas,
    center - Offset(textPainter.width / 2, textPainter.height / 2),
  );
}

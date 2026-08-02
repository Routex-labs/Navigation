import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// 에스컬레이터/엘리베이터/유아차 전용 E/V — 수직이동 구조물 폴리곤을 초록톤으로
/// 덧칠해 주변 매장에서 눈에 띄게 하기 위한 name 매칭 값. 백엔드 벡터 타일에는
/// category 속성이 없어 name으로 매칭한다. 매칭이 어긋나면(백엔드 name 변경 등)
/// 초록 하이라이트만 빠지고 일반 매장 스타일로 폴백된다.
///
/// 실내 지도(`FloorPlanView`)와 야외 오버레이(`OutdoorMapBody`)가 같은 이름을 써야
/// 두 화면 사이에서 수직이동 폴리곤이 일관되게 강조된다.
const kVerticalTransportStoreNames = <String>[
  '에스컬레이터',
  '엘리베이터',
  '유아차 전용 E/V',
];

/// 매장명 라벨 레이어에서 수직이동 시설을 걸러내는 MapLibre 필터.
///
/// 이 건물에는 에스컬레이터 152개, 엘리베이터 68개가 있고 전부 매장과 **같은
/// 무게의 텍스트 라벨**을 달고 있었다. 도면이 "에스컬레이터"로 도배되어 정작
/// 읽어야 할 매장명이 그 사이에 묻혔다. 아이콘이 이미 무슨 시설인지 말하므로
/// 이름은 중복이다 — 구글·네이버도 에스컬레이터에 텍스트를 붙이지 않는다.
///
/// `==`를 뒤집은 `!=`의 `all`이다. 같은 파일의 fill 필터가 `any` + `==`로
/// 시설물만 고르는 것과 정확히 반대 집합이라, 한쪽을 고치면 다른 쪽도 본다.
List<Object> storeLabelExcludingFacilitiesFilter() => [
  'all',
  for (final name in kVerticalTransportStoreNames)
    [
      '!=',
      ['get', 'name'],
      name,
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

/// 실내 지도에서 POI·편의시설 아이콘을 그릴 배율. 아이콘 비트맵이 96px 캔버스라
/// 화면 지름은 `96 * 이 값`(=약 42px)이다. 처음 0.28(약 27px)로 뒀더니 화장실·
/// 장애인화장실·정수기 같은 시설이 매장 라벨에 묻혀 안 보인다는 피드백을 받아
/// 1.5배로 올렸다. 원본이 96px이므로 이 값까지는 확대가 아니라 축소 렌더링이라
/// 아이콘이 흐려지지 않는다. 더 키우려면 [renderPoiIconPng]·
/// [renderFacilityIconPng]의 캔버스 크기도 같이 올려야 한다.
const kIndoorPoiIconSize = 0.42;

/// 매장 폴리곤이지만 이름이 이 표에 있는 시설(화장실·정수기 등)은 라벨 옆에
/// 종류별 아이콘을 함께 얹는다. POI(엘리베이터·에스컬레이터 등)와 달리 이
/// 시설들은 백엔드에서 `pois` 레이어가 아니라 `stores` 레이어에 들어오기 때문에
/// POI 아이콘 매핑만으로는 눈에 띄지 않는다. 벡터 타일에는 subcategory 속성이
/// 없어(name/id/kind만 노출) name으로 매칭한다.
///
/// 화장실은 흰 원 안에 파란 Icons.man과 분홍 Icons.woman을 나란히 얹어 남/여
/// 화장실임이 한눈에 읽히도록 한다(duo 스타일에서 left/rightBackground 값은
/// 배경색이 아니라 좌/우 아이콘 색으로 쓰인다). 장애인화장실은 접근성 파랑 원에
/// 휠체어 아이콘(Icons.accessible)을 얹고, 나머지 시설은 다른 POI와 동일하게
/// 초록 원 위에 흰 아이콘으로 그린다.
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

  _paintIconGlyph(
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
    _paintIconGlyph(
      canvas,
      icon: style.leftIcon!,
      color: style.leftBackground!,
      fontSize: canvasSize * 0.48,
      center: const Offset(canvasSize * 0.29, canvasSize / 2),
    );
    _paintIconGlyph(
      canvas,
      icon: style.rightIcon!,
      color: style.rightBackground!,
      fontSize: canvasSize * 0.48,
      center: const Offset(canvasSize * 0.71, canvasSize / 2),
    );
  } else {
    canvas.drawCircle(center, innerRadius, Paint()..color = style.background);
    _paintIconGlyph(
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

void _paintIconGlyph(
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

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// 에스컬레이터/엘리베이터/유아차 전용 E/V — 수직이동 구조물 폴리곤을 초록톤으로
/// 덧칠해 주변 매장에서 눈에 띄게 하기 위한 name 매칭 값. 백엔드 벡터 타일에는
/// category 속성이 없어 name으로 매칭한다. 매칭이 어긋나면(백엔드 name 변경 등)
/// 초록 하이라이트만 빠지고 일반 매장 스타일로 폴백된다.
///
/// 야외 오버레이(`OutdoorMapBody`)가 층을 오갈 때 수직이동 폴리곤이 일관되게
/// 강조되려면 이 목록이 한 곳에 있어야 한다 — fill·라벨·아이콘 레이어가 각자
/// 이 이름을 보기 때문이다.
const kVerticalTransportStoreNames = <String>[
  '에스컬레이터',
  '엘리베이터',
  '유아차 전용 E/V',
];

/// 매장명 라벨 레이어에서 **아이콘이 이미 말해 주는 것**을 걸러내는 MapLibre 필터.
///
/// 두 종류를 뺀다.
///
/// **수직이동 시설** — 이 건물에는 에스컬레이터 152개, 엘리베이터 68개가 있고
/// 전부 매장과 같은 무게의 텍스트 라벨을 달고 있었다. 도면이 "에스컬레이터"로
/// 도배되어 정작 읽어야 할 매장명이 그 사이에 묻혔다. 아이콘이 이미 무슨
/// 시설인지 말하므로 이름은 중복이다 — 구글·네이버도 에스컬레이터에 텍스트를
/// 붙이지 않는다.
///
/// **[kStoreFacilityStyleByName]의 편의시설** — 이쪽은 이름을 **살려야 한다**
/// (「ATM (하나은행)」은 이름이 정보다). 다만 전용 아이콘 레이어가 이미 아이콘을
/// 그리고 있어서, 이 레이어까지 카테고리 아이콘을 붙이면 같은 폴리곤에 아이콘이
/// 두 개 뜬다. 그래서 여기서 빼고 [facilityStoreLabelFilter]가 고른 **텍스트
/// 전용** 레이어가 이름만 그린다.
///
/// `==`를 뒤집은 `!=`의 `all`이다. 같은 파일의 fill 필터가 `any` + `==`로
/// 시설물만 고르는 것과 정확히 반대 집합이라, 한쪽을 고치면 다른 쪽도 본다.
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

/// 이름을 **그리면 안 되는** POI `type`.
///
/// ## 왜 필요한가 — 이 이름들은 사람에게 보여 줄 이름이 아니다
///
/// POI는 Studio 원본의 `elevator`/`escalator` 노드를 마커로 승격한 것이라
/// (`backend/scripts/seed/studio_adapter.py`의 `_generate_pois`), `name`이 노드
/// 식별자 그대로다. 더현대 서울 실데이터를 세어 보면:
///
/// | type | 개수 | 이름 예시 |
/// |---|---|---|
/// | `escalator` | 152 | `ES1-DN(FR3F)` · `ES3-UP(TO2F)` · `ES2-UP(FRB1)` |
/// | `elevator` | 59 | `EV1` · `EV2` · `EV3` |
///
/// 즉 실내 도면 한 층에 **매장명과 같은 무게의 영문 내부 코드가 수십 개** 떠
/// 있었다. 이름 자체가 뜻을 전하지 못할 뿐 아니라, 한글 매장명 사이에 섞인
/// 영문 대문자 코드라 시선을 먼저 끌어 정작 읽어야 할 매장명이 묻혔다.
///
/// ## 왜 층 매장 라벨에서는 안 보였나
///
/// `stores` 레이어 쪽 에스컬레이터·엘리베이터는 이미 걸러지고 있다
/// ([storeLabelWithCategoryIconFilter] — 이름이 정확히 `에스컬레이터`·
/// `엘리베이터`인 폴리곤). 같은 시설이 **폴리곤(stores)과 마커(pois) 두 소스로**
/// 들어오는데 한쪽만 막혀 있었던 것이다. 야외 오버레이는 POI를 아이콘으로만
/// 그리고 이름 레이어가 아예 없어서(`outdoor_map_screen.dart`) 실내 화면에서만
/// 증상이 보였다.
///
/// ## 아이콘은 남긴다
///
/// 위치 자체는 필요한 정보다. `floor-pois-icon`이 계속 그리고, 무슨 시설인지는
/// 아이콘([kPoiIconByType])이 말한다 — [storeLabelWithCategoryIconFilter]가
/// 폴리곤 쪽에서 내린 것과 같은 판단이다.
///
/// `vertical-connection`은 더현대 데이터에는 없지만 [kPoiIconByType]이 다른
/// 데이터셋을 위해 이미 받고 있는 값이라 같이 막는다. 새 건물이 들어올 때
/// 아이콘은 붙는데 이름만 새는 상태가 되지 않게 한다.
const kVerticalTransportPoiTypes = <String>[
  'elevator',
  'escalator',
  'vertical-connection',
];

/// POI 이름 라벨 필터. [kVerticalTransportPoiTypes]를 뺀 나머지(화장실·출구 등)만
/// 이름을 그린다.
///
/// `!=`의 `all`이다 — [storeLabelWithCategoryIconFilter]와 같은 형태를 쓴다.
/// `['match', ...]`나 `['!', ['in', ...]]`가 MapLibre GL Native에서 예외도
/// 로그도 없이 매치 0건이 되던 전례가 있어 검증된 쪽으로 통일한다
/// (근거는 [category_map_filter.dart]에 적어 뒀다).
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

/// 실내 지도 위 **모든 마커의 지름(논리 px)**. 화장실·정수기 같은 편의시설,
/// POI, 그리고 매장 라벨 옆 대분류 배지가 전부 이 하나를 쓴다.
///
/// ## 왜 하나로 묶었나
///
/// "대분류 아이콘을 화장실만큼 해 달라"는 피드백이다. 값을 두 벌로 두면 한쪽만
/// 조정할 때마다 다시 갈라진다 — 실제로 그렇게 갈라져 있었다. 배지는 화면 배율을
/// 곱해 논리 px으로 잡혀 있었고([storeCategoryIconSize]) 시설 아이콘은 배율 없는
/// 스칼라(0.42)라, 같은 숫자를 써도 기기마다 다른 비율로 벌어졌다.
///
/// ## 값의 근거
///
/// 12는 **시설 아이콘이 지금 보이는 크기 그대로**다. 예전 값 0.42는 비트맵
/// 96px에 곱하는 배율이라 화면에서 40 물리 px이었고, 이 기기(배율 3.5)에서
/// 약 11.5 논리 px이다. 그 크기는 두 번의 피드백을 통과한 값이라(0.28은 "안
/// 보인다", 0.6은 "너무 크다") 기준으로 삼을 만하다.
///
/// **바뀐 것은 기기 간 일관성이다.** 예전엔 어느 기기에서나 40 **물리** px이라
/// 고밀도 화면일수록 작아 보였는데, 이제 어느 기기에서나 12 **논리** px으로
/// 같은 크기로 보인다.
///
/// 더 키우려면 [renderPoiIconPng]·[renderFacilityIconPng]의 캔버스(96px)도 같이
/// 올려야 한다 — 그보다 크게 그리면 확대 렌더링이라 아이콘이 흐려진다.
const kIndoorMarkerLogicalPx = 12.0;

/// 아이콘 비트맵 캔버스 한 변(px). [renderPoiIconPng] 등이 굽는 크기이자
/// `icon-size` 1.0일 때 화면에 그려지는 **물리** 픽셀 수다.
const kIconCanvasPx = 96.0;

/// [kIndoorMarkerLogicalPx]를 `icon-size` 값으로 환산한다.
///
/// `icon-size`는 비트맵의 **물리** 픽셀에 곱해지는데 `text-size`는 논리 픽셀이라,
/// 배율을 곱하지 않으면 고밀도 화면에서 아이콘만 배율만큼 작아진다. 이 저장소가
/// 실제로 그 버그를 겪었다(`category_map_icon.dart`의 실측표).
///
/// ## 웹에서는 배율을 곱하면 안 된다
///
/// 위 "물리 픽셀" 전제는 **네이티브(Android·iOS)에만** 해당한다. 웹 구현은
/// 비트맵을 `pixelRatio: 1`로 등록하기 때문에(`maplibre_gl_web` 0.26.2의
/// `MapLibreWebGlPlatform.addImage`) `icon-size`가 곱해지는 대상이 CSS 픽셀,
/// 즉 논리 픽셀이다. 여기서 배율까지 곱하면 아이콘만 배율배로 커진다 —
/// Chrome 기기 에뮬레이션(iPhone 12, 배율 3)에서 12 논리 px짜리 배지가 36 px으로
/// 떴고, 폰에서는 멀쩡한데 웹에서만 크다는 제보가 이것이다.
///
/// [isWeb]은 테스트가 두 갈래를 모두 고정할 수 있게 뚫어 둔 구멍이다. 실행
/// 경로에서는 넘기지 않는다(`service_locator.dart`가 쓰는 방식과 같다).
double indoorMarkerIconSize(double devicePixelRatio, {bool? isWeb}) =>
    kIndoorMarkerLogicalPx *
    ((isWeb ?? kIsWeb) ? 1.0 : devicePixelRatio) /
    kIconCanvasPx;

/// 매장 폴리곤이지만 이름이 이 표에 있는 시설(화장실·정수기 등)은 라벨 옆에
/// 종류별 아이콘을 함께 얹는다. POI(엘리베이터·에스컬레이터 등)와 달리 이
/// 시설들은 백엔드에서 `pois` 레이어가 아니라 `stores` 레이어에 들어오기 때문에
/// POI 아이콘 매핑만으로는 눈에 띄지 않는다.
///
/// **subcategory가 아니라 name으로 매칭하는 이유**는 세밀함이다. 벡터 타일은
/// `category`·`subcategory`를 싣지만(`backend/app/geo/tiling.py`의
/// `_store_properties`), 이 표가 구분하려는 것은 소분류보다 잘다 — 화장실과
/// 장애인화장실은 subcategory가 같은 `생활편의`인데 아이콘은 달라야 한다.
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

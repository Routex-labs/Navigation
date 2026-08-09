/// 지도 위 매장명 라벨에 붙는 **대분류 아이콘**과, 이름이 아이콘 좌/우 중 어느
/// 쪽에 놓일지 정하는 규칙.
///
/// ## 왜 붙이는가
///
/// 도면에 이름만 떠 있으면 그 매장이 무엇을 파는 곳인지 알 수 없다. 이 건물의
/// 매장 이름은 대부분 브랜드명이라 업종이 전혀 읽히지 않는다 — 「오에라」·
/// 「YPHAUS」·「스컬프」를 보고 뷰티인지 패션인지 라운지인지 아는 사용자는 없다.
/// 이름 옆에 대분류 아이콘을 붙이면 그 판단이 한 번에 끝난다.
///
/// ## 아이콘은 앱이 이미 쓰던 것을 그대로 쓴다
///
/// 글리프와 색은 [categoryIconFor]·[categoryColorFor]에서 가져온다. 카테고리
/// chip과 매장 목록 시트가 쓰는 것과 **같은 표**라, 시트에서 본 아이콘이 지도에서
/// 같은 모양·같은 색으로 나온다. 지도만 자기 표를 갖게 두면 둘은 반드시 어긋난다.
///
/// 배지 모양(흰 테두리 + 색 원 + 흰 글리프)도 이미 지도에 떠 있는 POI·편의시설
/// 아이콘([renderPoiIconPng])과 같은 언어를 쓴다.
///
/// ## 이름이 아이콘 앞/뒤로 뒤집히는 방식
///
/// MapLibre의 `text-variable-anchor`에 맡긴다. `['left', 'right']`를 주면 심볼을
/// 배치할 때 **앞에서부터 차례로 시도**한다 — `left` 앵커는 아이콘 오른쪽에
/// 이름을 놓고, 그 자리가 이미 찬 곳이면 `right`로 넘어가 왼쪽에 놓는다.
///
/// **폴리곤의 실제 가로 길이를 재는 것이 아니다.** 스타일 표현식은 폴리곤 치수를
/// 볼 수 없다. 대신 "그 자리에 글자가 들어가는가"를 충돌 판정으로 본다. 좁은
/// 매장에서는 오른쪽이 옆 매장 라벨에 막혀 왼쪽으로 넘어가므로, 결과적으로 매장이
/// 좁을수록 반대편으로 뒤집힌다.
///
/// 이 기능은 `text-allow-overlap`이 false일 때만 동작한다. 라벨이 겹쳐도
/// 그리도록 바꾸면 충돌 판정 자체가 사라져 앵커는 **항상 첫 번째 값**이 되고,
/// 뒤집기가 조용히 죽는다.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'category_icon.dart';
import 'floor_facility_style.dart';

/// 대분류가 없는 매장에 쓰는 폴백 키.
///
/// 타일은 `category`가 null이면 **키 자체를 싣지 않으므로**(`tiling.py`의
/// `_store_properties`) `['get', 'category']`가 null이 되고 `match`의 default로
/// 떨어진다. 이 키를 [categoryIconFor]에 넘기면 표에 없는 값이라 storefront +
/// primary로 폴백한다 — 매장 목록 시트가 같은 상황에서 쓰는 것과 같은 아이콘이다.
const kStoreCategoryFallbackKey = '__분류없음__';

/// [MapLibreMapController.addImage]에 등록할 이름. 카테고리마다 색이 달라
/// 글리프 codePoint만으로는 구분되지 않으므로 대분류 이름을 키로 삼는다
/// ([facilityIconImageName]과 같은 이유).
String storeCategoryIconImageName(String category) =>
    'store-category-icon-$category';

/// 지도에 등록해야 하는 대분류 아이콘 전체. 폴백까지 포함한다.
Iterable<String> get storeCategoryIconKeys => [
  ...categoryIconCategories,
  kStoreCategoryFallbackKey,
];

/// `stores` feature의 `category`로 아이콘 비트맵을 고르는 표현식.
///
/// `match`의 label 자리에 **문자열만** 들어간다. 배열을 label로 쓰는 형태는
/// MapLibre GL Native에서 조용히 매치 0건이 되는 경로가 있어 이 저장소가 이미
/// 한 번 데였다(`category_map_filter.dart` 주석). 이 형태는 POI·편의시설 아이콘이
/// 실기기에서 검증한 경로와 같다.
List<Object> storeCategoryIconExpression() => [
  'match',
  ['get', 'category'],
  for (final category in categoryIconCategories) ...[
    category,
    storeCategoryIconImageName(category),
  ],
  storeCategoryIconImageName(kStoreCategoryFallbackKey),
];

/// 이름을 아이콘의 오른쪽(`left` 앵커) → 왼쪽(`right` 앵커) 순으로 시도한다.
/// 순서가 곧 선호도다 — 자리가 있으면 항상 오른쪽에 놓여 읽는 방향과 맞는다.
const kStoreLabelVariableAnchor = <String>['left', 'right'];

/// 아이콘과 글자 사이 여백(em, 글자 크기 기준).
///
/// **이 값은 심볼 중심에서의 거리가 아니라 아이콘 가장자리부터의 여백이다.**
/// 스펙 문구("offset from the anchor")만 읽으면 중심 거리로 오해하기 쉬워서
/// 처음 아이콘 반지름을 글자 크기로 나눈 값(0.85)을 넣었다가 간격이 27px까지
/// 벌어졌다. MapLibre가 아이콘 상자를 이미 감안하고 그 바깥에 이 값을 더한다.
///
/// 에뮬레이터 실측(B1, z≈19 · 아이콘 15px · 글자 약 13px):
///
/// | 설정값 | 아이콘 가장자리~글자 |
/// |---|---|
/// | 0.85 | 27px — 아이콘과 이름이 따로 노는 것으로 읽힌다 |
/// | 0.25 | 8px |
/// | 0.18 | 약 6px — 지금 값 |
///
/// 간격은 설정값에 거의 정비례한다(약 31.7px/em). 0으로 두면 글자가 아이콘에
/// 붙어 halo끼리 겹치므로 0보다는 커야 한다.
///
/// ## 0.18 → 0.55 (2026-08-09)
///
/// 위 실측표는 **아이콘이 5.5 논리 px이던 시절**의 값이다. 화면 배율 버그를
/// 고치면서 배지가 11~16 논리 px으로 커졌는데([storeCategoryIconSizeIndoor])
/// 여백은 그대로라, 커진 배지에 글자가 파묻혀 보였다.
///
/// 이 값은 **글자 크기에 대한 비율**이라 배지가 커져도 자동으로 따라오지 않는다.
/// 실측표의 환산(약 31.7 물리px/em, 글자 13 논리px 기준)으로 다시 잡으면
/// 0.32em은 z19에서 약 3.8 논리 px — 배지 지름의 1/4밖에 안 된다. 배지 반지름
/// 남짓(약 6~7 논리 px)은 띄워야 둘이 붙은 한 덩어리로 읽히면서도 글자가 살아서,
/// 0.55로 잡는다.
///
/// 더 키우면 "아이콘과 이름이 따로 논다"는 반대쪽 함정이 있다(위 0.85 사례).
/// 다만 그 사례도 아이콘이 15 물리px이던 시절이라, 지금 배지 기준으로는
/// 여유가 조금 더 있다.
const kStoreLabelRadialOffset = 0.55;

/// 아이콘 비트맵 캔버스 한 변(px). [renderStoreCategoryIconPng]가 굽는 크기이자
/// `icon-size` 1.0일 때 화면에 그려지는 크기다.
const kIconCanvasPx = 96.0;

/// 대분류 배지를 **논리 픽셀**로 얼마나 크게 그릴지 (z16 축소 ~ z20 확대).
///
/// 매장명 글자가 12~17 논리 px이므로([kStoreLabelMinPx]~[kStoreLabelMaxPx])
/// 배지는 글자의 1.17~1.18배다.
///
/// **비율로 붙잡아 둔다.** 배율 버그를 고친 직후 12~18로 잡았다가 도면이 배지에
/// 눌려 보여 11~16으로 내렸고, 그 뒤 글자 밴드가 접근성 피드백으로 올라가면서
/// 같은 비율을 유지하려고 14~20이 됐다. 글자보다 조금 크기만 하면 "여기 무슨
/// 업종인지"는 전달되므로 **1.2배 언저리**가 기준이고, 절대값은 글자를 따라간다.
const kStoreCategoryIconMinLogicalPx = 14.0;
const kStoreCategoryIconMaxLogicalPx = 20.0;

/// 실내 화면의 대분류 아이콘 `icon-size` 표현식.
///
/// ## 왜 상수가 아니라 함수가 됐나 — 아이콘만 화면 배율을 안 먹고 있었다
///
/// **이 파일의 모든 크기 주석이 3.5배 틀려 있었다.** `icon-size`는 비트맵의
/// **화면(물리) 픽셀** 수에 곱해지는데, `text-size`는 논리 픽셀이라 MapLibre가
/// 화면 배율을 곱해 그린다. 즉 같은 숫자를 둘에 줘도 고밀도 화면에서는 아이콘만
/// 배율만큼 작아진다.
///
/// Galaxy S23(1440×3088, 배율 약 3.5)에서 실측했다.
///
/// | | 설정 | 화면 px | 논리 px |
/// |---|---|---|---|
/// | 매장명 글자 | `text-size: 14` | 약 49 | 14 |
/// | 대분류 배지 (예전 0.20) | `icon-size: 0.20` | 19 | **5.5** |
///
/// 배지가 글자의 1.4배여야 한다고 주석에 적혀 있었지만 실제로는 **0.4배**였다.
/// "동그란 게 너무 작다"는 피드백이 정확했고, 0.20 → 0.24처럼 숫자를 조금
/// 올리는 것으로는 닿을 수 없는 격차였다. 그래서 크기를 **논리 픽셀로 적고**
/// 화면 배율을 여기서 곱한다 — 기기가 바뀌어도 눈에 보이는 크기가 같다.
///
/// 예전 값(0.14~0.20)과 그 주변의 "0.17~0.25로 키웠더니 B1 라벨이 49→38개로
/// 줄었다"는 실측은 **전부 이 버그 위에서 잰 값**이라 더 이상 기준이 아니다.
/// 지금 기준은 아래 [storeCategoryIconLayout]이 만드는 배치 규칙이다.
List<Object> storeCategoryIconSizeIndoor(double devicePixelRatio) {
  double scale(double logicalPx) => logicalPx * devicePixelRatio / kIconCanvasPx;
  return [
    'interpolate',
    ['linear'],
    ['zoom'],
    16,
    scale(kStoreCategoryIconMinLogicalPx),
    20,
    scale(kStoreCategoryIconMaxLogicalPx),
  ];
}

/// 대분류 아이콘 비트맵. 흰 테두리 + 카테고리 색 원 + 흰 글리프.
///
/// MapLibre 심볼 레이어는 사전 등록된 비트맵만 참조할 수 있어서 폰트 글리프를
/// 직접 캔버스에 그려 PNG로 바꾼다([renderPoiIconPng]와 같은 이유).
Future<Uint8List> renderStoreCategoryIconPng(String category) async {
  const canvasSize = 96.0;
  const center = Offset(canvasSize / 2, canvasSize / 2);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    const Rect.fromLTWH(0, 0, canvasSize, canvasSize),
  );

  // 흰 테두리는 도면(연회색)·강조된 매장(연파랑) 어느 배경 위에서도 원의 윤곽이
  // 살아 있게 한다. 배경색만 칠하면 밝은 카테고리 색이 도면에 묻힌다.
  canvas.drawCircle(center, canvasSize / 2, Paint()..color = Colors.white);
  canvas.drawCircle(
    center,
    canvasSize / 2 - 5,
    Paint()..color = categoryColorFor(category),
  );

  paintIconGlyph(
    canvas,
    icon: categoryIconFor(category),
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

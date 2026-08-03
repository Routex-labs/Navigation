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

/// 아이콘 중심에서 글자까지 띄우는 거리(em, 글자 크기 기준).
///
/// 아이콘 반지름을 글자 크기로 나눈 값보다 조금 커야 겹치지 않는다. 실내 기준
/// z16에서 아이콘 16px·글자 9px이라 0.9em이 딱 붙는 선이고, z20에서 24px·14px라
/// 0.86em이다. 양쪽 다 덮고 약간의 여백을 두는 값으로 잡았다.
///
/// **아이콘 크기를 바꾸면 이 값도 함께 본다.** 한쪽만 고치면 글자가 아이콘을
/// 파고들거나(작게 잡을 때) 이름이 매장 밖으로 밀려난다(크게 잡을 때).
const kStoreLabelRadialOffset = 1.0;

/// 실내 화면의 대분류 아이콘 배율. 캔버스 96px 기준이라 화면 지름은 `96 * 값`이다.
///
/// 라벨 옆에 붙는 아이콘이라 시설 아이콘([kIndoorPoiIconSize] = 0.42, 약 40px)과
/// 같은 크기로 두면 이름보다 아이콘이 커져 도면이 아이콘 밭이 된다. 글자 크기의
/// 1.7배 남짓(z16 16px / z20 24px)으로 잡아 이름과 한 덩어리로 읽히게 한다.
///
/// 매장명 라벨의 `text-size`가 z16→z20에서 9→14로 커지므로 같은 구간에서 함께
/// 키운다. **값을 바꿀 때는 z16 축소와 z20 확대를 반드시 함께 확인한다** —
/// 한쪽만 보고 고치면 반대쪽이 회귀한다([kIndoorPoiIconSize] 주석과 같은 함정).
const kStoreCategoryIconSizeIndoor = [
  'interpolate',
  ['linear'],
  ['zoom'],
  16,
  0.17,
  20,
  0.25,
];

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

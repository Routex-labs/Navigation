import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../core/map_fonts.dart';
import '../theme/app_theme.dart';

/// 도착지 핀 아이콘과, 그 위에 "도착" 글씨를 얹는 데 필요한 치수.
///
/// 실내 화면([FloorPlanView])과 야외 지도의 실내 오버레이가 같은 핀을 그린다.
/// 예전에는 두 파일이 각자 렌더러를 갖고 있었고 생김새도 달랐다 — 야외는 단색
/// 빨강, 실내는 흰 원 + 진한 글씨. 같은 목적지를 가리키는 마커가 화면마다
/// 다르게 보일 이유가 없다.
///
/// ## 글씨를 캔버스에 굽지 않는 이유
///
/// Flutter 웹 CanvasKit에서 **오프스크린 캔버스로 렌더링한 이미지**에는 한글
/// 글리프가 있는 폰트가 자동으로 딸려오지 않아 "도착"이 두부(tofu) 박스로
/// 뭉개진다. 반면 MapLibre의 심볼 텍스트는 매장명 라벨과 같은 경로를 타서 한글이
/// 정상이다. 그래서 **도형만 여기서 그리고 글씨는 심볼 레이어의 `textField`로
/// 얹는다.** 이 분리를 깨고 캔버스에 글씨를 그리면 웹에서만 깨진다.

/// 핀 이미지의 원본 크기. 실제 화면 크기는 심볼 레이어의 `iconSize`가 정한다.
const kPinCanvasWidth = 128.0;
const kPinCanvasHeight = 180.0;

/// 머리 원의 반지름과 중심. 글씨는 이 원 안에 들어가야 한다.
const kPinHeadRadius = 54.0;
const kPinHeadCenterY = kPinHeadRadius + 6;

/// 이미지 **밑변에서** 머리 중심까지의 거리. `iconAnchor: bottom`이라 밑변이
/// 실제 좌표에 놓이므로, 글씨를 머리 중심에 맞추려면 이 값만큼 위로 올려야 한다.
const kPinHeadCenterFromBottom = kPinCanvasHeight - kPinHeadCenterY;

/// `iconSize / textSize` 비율. 두 값을 zoom 보간식으로 걸되 이 비율을 고정하면,
/// 확대·축소해도 글씨가 머리 원 안 같은 자리에 남는다.
///
/// **이 값을 내리면 글씨가 커진다**(textSize = iconSize / 비율). 머리 지름은
/// 캔버스 108px이므로 두 글자 "도착"의 폭은 대략 `2 × textSize`, 즉 지름의
/// `2 × 비율 × (128/108)`쯤을 차지한다. 지금 값은 지름의 70% 언저리다 — 더
/// 내리면 글씨가 원을 넘고, 올리면 핀 안에서 작아 보인다.
const kPinIconToTextRatio = 0.026;

/// 심볼 레이어에 줄 `textOffset`의 y값(단위: em).
///
/// 화면상 올려야 할 픽셀은 `kPinHeadCenterFromBottom × iconSize`이고, `textOffset`
/// 단위는 textSize의 배수이므로 `iconSize / textSize`를 곱하면 zoom과 무관한
/// 상수가 된다. 캔버스 치수를 바꾸면 이 값도 함께 움직인다 — 그래서 손으로 적지
/// 않고 계산한다.
const kPinTextOffsetEm = -kPinHeadCenterFromBottom * kPinIconToTextRatio;

/// 글씨 색. 빨간 바탕 위에 얹으므로 흰색이다.
const kPinTextColor = '#FFFFFF';

/// 실루엣 테두리. **흰색이 아니다** — 실내 도면 바닥이 `#FFFFFF`라 흰 테두리는
/// 흰 배경 위에서 아무 일도 하지 않는다(경로선의 흰 casing이 안 보이는 것과 같은
/// 문제다). 같은 색조를 어둡게 쓰면 흰 도면 위에서도, 회색 매장 폴리곤 위에서도,
/// 야외 지도 위에서도 경계가 살아난다.
const _pinOutlineColor = Color(0xFFA81B18);
const _pinOutlineWidth = 7.0;
// 끝점이 외곽선 반두께와 정확히 맞닿으면 antialiasing이 마지막 행을 잘라낸다.
const _pinCanvasBottomInset = 1.0;

/// 도착 핀 심볼 레이어의 **완성된** 속성 묶음.
///
/// 실내 화면과 야외 오버레이가 각자 같은 정의를 베껴 들고 있었고, **두 곳 모두
/// `textFont`를 빠뜨렸다.** 생략하면 MapLibre 스펙 기본값(Open Sans / Arial
/// Unicode MS)을 요청하는데 백엔드는 `Pretendard Regular` 하나만 서빙하므로
/// 글리프를 못 받는다. 네이티브(Android/iOS)는 글리프가 없으면 심볼 레이아웃을
/// 끝내지 못해 **글씨뿐 아니라 핀 아이콘까지 통째로 사라진다.** 웹은 CJK를
/// 시스템 폰트로 로컬 렌더해서 멀쩡해 보이므로 Chrome에서만 확인하면 못 잡는다.
///
/// 그래서 정의를 여기 하나로 모은다 — 한 곳만 고쳐 두 화면이 어긋나는 일을
/// 구조적으로 막는 게 이 함수의 목적이다(indoor_overlay_layers.dart의 "등록과
/// 갱신이 같은 함수를 쓴다" 규칙과 같은 이유).
///
/// 화면마다 다른 것은 두 가지뿐이다.
/// - [imageName]: addImage 등록 키. 웹 addImage는 같은 이름이 있으면 새 비트맵을
///   버리므로 화면별로 따로 둔다.
/// - [iconSizeZ16]·[iconSizeZ20]: 화면이 잡는 zoom 보간 구간. 야외 오버레이는
///   시야가 넓어 실내보다 크게 잡는다.
SymbolLayerProperties destinationPinSymbolProps({
  required String imageName,
  required double iconSizeZ16,
  required double iconSizeZ20,
}) => SymbolLayerProperties(
  iconImage: imageName,
  iconSize: [
    'interpolate',
    ['linear'],
    ['zoom'],
    16,
    iconSizeZ16,
    20,
    iconSizeZ20,
  ],
  // 핀 바닥(tip)이 실제 좌표에 오도록.
  iconAnchor: 'bottom',
  iconAllowOverlap: true,
  iconIgnorePlacement: true,
  textField: '도착',
  textFont: const [mapFontStackRegular],
  // 손으로 적지 않고 iconSize에서 나눈다 — 비율이 어긋나면 글씨가 머리 원을
  // 벗어나고 textOffset도 같이 틀어진다.
  textSize: [
    'interpolate',
    ['linear'],
    ['zoom'],
    16,
    iconSizeZ16 / kPinIconToTextRatio,
    20,
    iconSizeZ20 / kPinIconToTextRatio,
  ],
  textColor: kPinTextColor,
  textAnchor: 'center',
  textOffset: const [0, kPinTextOffsetEm],
  textAllowOverlap: true,
  textIgnorePlacement: true,
);

/// 빨간 물방울 핀을 PNG 바이트로 굽는다.
///
/// 꼬리는 직선 탄젠트가 아니라 곡선으로 가늘게 떨어뜨린다. 머리에서 바로 벌어지는
/// 직선 꼬리는 뭉툭해 보이고, 지도에서 정확히 어느 점을 가리키는지도 덜 분명하다.
Future<Uint8List> renderDestinationPinIcon() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    const Rect.fromLTWH(0, 0, kPinCanvasWidth, kPinCanvasHeight),
  );

  const cx = kPinCanvasWidth / 2;
  const cy = kPinHeadCenterY;
  // 테두리가 캔버스 밖으로 잘리지 않도록 반 두께와 1 raw pixel을 남긴다.
  const tipY = kPinCanvasHeight - _pinOutlineWidth / 2 - _pinCanvasBottomInset;

  // 머리 원과 꼬리가 만나는 지점. 원 위의 점이어야 이어붙인 자리가 각지지 않는다.
  const joinDx = 50.4;
  const joinDy = 19.35;

  final silhouette = Path()
    ..moveTo(cx, tipY)
    ..cubicTo(
      cx - 11.25,
      cy + 76.5,
      cx - 42.75,
      cy + 45,
      cx - joinDx,
      cy + joinDy,
    )
    ..arcToPoint(
      const Offset(cx + joinDx, cy + joinDy),
      radius: const Radius.circular(kPinHeadRadius),
      largeArc: true,
    )
    ..cubicTo(cx + 42.75, cy + 45, cx + 11.25, cy + 76.5, cx, tipY)
    ..close();

  canvas.drawPath(silhouette, Paint()..color = AppColors.dest);
  canvas.drawPath(
    silhouette,
    Paint()
      ..color = _pinOutlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = _pinOutlineWidth
      ..strokeJoin = StrokeJoin.round,
  );

  final image = await recorder.endRecording().toImage(
    kPinCanvasWidth.toInt(),
    kPinCanvasHeight.toInt(),
  );
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

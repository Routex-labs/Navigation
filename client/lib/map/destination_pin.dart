import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../theme/app_theme.dart';

/// 도착지 핀 아이콘과, 그 위에 "도착" 글씨를 얹는 데 필요한 치수.
///
/// 야외 지도와 그 위의 실내 오버레이가 같은 핀을 그린다.
///
/// 글씨는 심볼 텍스트가 아니라 **비트맵에 굽는다.** `textOffset`(em·dp 기준)과
/// 아이콘 크기(플랫폼마다 다른 비트맵 자연 크기)가 서로 다른 단위로 커져서, 웹에
/// 맞춘 오프셋이 실기기에서는 글씨를 핀 밖 허공으로 올려 버렸다. 비트맵에 구우면
/// 글씨가 도형과 같은 좌표계에 있어 어떤 밀도·zoom에서도 어긋나지 않는다.
///
/// **단, 폰트 이름을 반드시 명시한다** — 오프스크린 캔버스는 기본 폰트 폴백이
/// 빈약해서(특히 웹 CanvasKit) 비워 두면 한글이 두부(tofu) 박스가 된다.
///
/// 자세한 경위는 `docs/client/map-style-rules.md`.

/// 핀 이미지의 원본 크기. 실제 화면 크기는 심볼 레이어의 `iconSize`가 정한다.
const kPinCanvasWidth = 128.0;
const kPinCanvasHeight = 180.0;

/// 머리 원의 반지름과 중심. 글씨는 이 원 안에 들어가야 한다.
const kPinHeadRadius = 54.0;
const kPinHeadCenterY = kPinHeadRadius + 6;

/// 핀에 굽는 라벨.
const kPinLabelText = '도착';

/// 라벨 글꼴. **비워 두면 안 된다** — 위 주석의 tofu 함정. pubspec에 번들된
/// 앱 글꼴이라 웹·네이티브 모두 폰트 매니저에 등록돼 있다.
const kPinLabelFontFamily = 'Pretendard';

/// 번들 글꼴을 못 잡는 상황에 대비한 한글 폴백. 등록 실패는 예외를 던지지 않고
/// 조용히 두부 박스로 나타나므로, 마지막 방어선을 깔아 둔다.
const kPinLabelFontFallback = <String>[
  'Noto Sans KR',
  'Apple SD Gothic Neo',
  'Malgun Gothic',
  'sans-serif',
];

/// 라벨 글자 크기(캔버스 좌표계). 머리 지름이 108이므로 두 글자 폭이 대략 88이
/// 되어 원 안에 여유 있게 들어간다. 키우면 원을 넘고, 줄이면 축소 시 먼저 뭉개진다.
const kPinLabelFontSize = 44.0;

/// 글씨 색. 빨간 바탕 위에 얹으므로 흰색이다.
const kPinTextColor = Color(0xFFFFFFFF);

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
/// 정의를 여기 하나로 모으는 이유는 실내 화면과 야외 오버레이가 각자 같은 정의를
/// 베껴 들고 있었기 때문이다 — 두 곳이 조용히 어긋나는 일을 구조적으로 막는다
/// (indoor_overlay_layers.dart의 "등록과 갱신이 같은 함수를 쓴다" 규칙과 같은 이유).
///
/// **텍스트 속성은 여기 없다.** 라벨은 비트맵에 굽는다 — 이유는 파일 상단 주석.
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
  // 매장 라벨과 충돌한다고 도착 핀이 숨으면 정작 목적지가 화면에서 사라진다.
  iconAllowOverlap: true,
  iconIgnorePlacement: true,
  // **텍스트 속성이 하나도 없다.** "도착"은 비트맵에 구워져 있다 — 심볼 텍스트로
  // 얹으면 글씨와 그림이 다른 단위로 커져 실기기에서 어긋난다(파일 상단 주석).
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

  // 라벨을 머리 원 중앙에 굽는다. height를 1.0으로 두어 줄 상자에 붙는 여백을
  // 없애야 painter.height의 절반이 실제 글자의 세로 중앙과 맞는다 — 기본값이면
  // 글씨가 원 중심보다 살짝 아래로 앉는다.
  final label = TextPainter(
    text: const TextSpan(
      text: kPinLabelText,
      style: TextStyle(
        color: kPinTextColor,
        fontSize: kPinLabelFontSize,
        fontWeight: FontWeight.w700,
        fontFamily: kPinLabelFontFamily,
        fontFamilyFallback: kPinLabelFontFallback,
        height: 1.0,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  label.paint(
    canvas,
    Offset(cx - label.width / 2, cy - label.height / 2),
  );

  final image = await recorder.endRecording().toImage(
    kPinCanvasWidth.toInt(),
    kPinCanvasHeight.toInt(),
  );
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

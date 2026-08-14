/// 지도(MapLibre) 심볼용 현재 위치 마커 비트맵 렌더러.
///
/// 예전에는 실내 전용 화면과 야외 지도(`outdoor_map_screen.dart`)에 같은 렌더
/// 코드가 한 벌씩 있었고, 주석으로 "바꿀 땐 함께 맞춰야 한다"고 서로를
/// 가리키고 있었다 — 그 약속을 코드로 옮긴 것이 이 파일이다. 실내 전용 화면은
/// 지웠고, 지금 이 그림을 쓰는 곳은 야외 지도 하나다.
///
/// addImage 등록 이름은 화면마다 따로 둔다(웹 addImage는 같은 이름이 이미
/// 있으면 새 비트맵을 버리므로, 이름 정책은 등록하는 쪽 사정이다). 여기는
/// 비트맵 그리기와 그 크기 상수만 소유한다.
library;

import 'dart:math' show pi;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../widgets/location_marker.dart';

/// 현재 위치 심볼을 그릴 때 쓰는 디자인 좌표계의 한 변 길이(px). 아래 렌더
/// 코드의 모든 반지름/오프셋은 이 좌표계 기준이다.
const kLocationMarkerIconDesignSize = 144.0;

/// 디자인 좌표계 대비 실제 비트맵 배율. 아이콘을 크게 키우면 MapLibre가
/// 비트맵을 화면 픽셀 수보다 적은 원본으로 늘려 그리게 되어 흰 테두리가
/// 뭉개진다(특히 devicePixelRatio 2~3인 폰). 비트맵만 이 배율로 크게 렌더하고
/// iconSize는 같은 배율로 나눠서, 화면상 크기는 그대로 두고 해상도만 올린다.
const kLocationMarkerIconPixelRatio = 2.0;

/// 심볼 레이어에 줄 iconSize. 디자인 좌표계 1px = 화면 1px이 되도록 고정한다
/// (비트맵은 [kLocationMarkerIconPixelRatio]배로 렌더하므로 그만큼 나눈다).
///
/// zoom 보간을 쓰지 않는 이유: 야외 GPS 마커는 `CircleLayer`의 상수
/// `circleRadius`로 그려져 zoom과 무관하게 같은 크기를 유지한다
/// (outdoor_map_screen.dart의 `outdoor-accuracy`/`outdoor-current-dot`).
/// 이 마커도 같은 크기로 보여야 하므로 zoom에 따라 커지면 안 된다.
const kLocationMarkerIconSize = 1.0 / kLocationMarkerIconPixelRatio;

/// 파란 코어 원의 반지름(디자인 단위 = 화면 px). 이 마커의 체감 크기를 정하는
/// 값이다(코어 지름 32px — 야외 GPS 도트 18px보다 크고 정확도 원 테두리
/// 44px보다 작다). 크기는 위젯 쪽 상수([kLocationMarkerCoreRadiusPx])에서
/// 파생시켜, 층 전환 덮개가 그리는 같은 그림의 점과 한 곳에서 조정되게 한다.
///
/// 비트맵 등록 이름에 이 값을 박아 두는 쪽(두 화면 모두)은 크기를 바꾸면
/// 이름도 함께 바뀌어, removeImage가 없는 웹에서도 새 비트맵이 등록된다.
const kLocationMarkerIconCoreRadius =
    kLocationMarkerCoreRadiusPx * kLocationMarkerIconPixelRatio;

/// 코어를 감싸는 흰 링의 반지름. 코어보다 5px 두껍게 잡아, 도면 바닥(#FFFFFF)
/// 에서는 묻히더라도 매장 fill이나 경로선 위에서는 코어가 배경과 분리돼
/// 보이게 한다.
const kLocationMarkerIconRimRadius =
    kLocationMarkerRimRadiusPx * kLocationMarkerIconPixelRatio;

/// 상용 지도 앱처럼 흰 테두리의 파란 현재 위치 점 뒤로 반투명 heading cone이
/// 퍼지는 하나의 심볼을 렌더링한다. MapLibre가 이 비트맵 전체를 회전하므로
/// 확대/축소해도 점과 방향 범위의 비율·간격이 흐트러지지 않는다.
///
/// [showHeading]이 true면 파란 도트 위에 방향 원뿔(radial gradient)이 함께
/// 그려진 이미지가 나오고, false면 도트만 있는 이미지가 나온다. MapLibre
/// SymbolLayer는 미리 addImage로 등록된 비트맵만 참조할 수 있어 이렇게 캔버스
/// 렌더가 필요하다.
Future<Uint8List> renderLocationMarkerIcon({required bool showHeading}) async {
  const canvasSize = kLocationMarkerIconDesignSize;
  const center = Offset(canvasSize / 2, canvasSize / 2);
  const pixelSize = canvasSize * kLocationMarkerIconPixelRatio;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    const Rect.fromLTWH(0, 0, pixelSize, pixelSize),
  );
  canvas.scale(kLocationMarkerIconPixelRatio);

  if (showHeading) {
    const coneRadius = 62.0;
    const halfAngle = 31 * pi / 180;
    final coneBounds = Rect.fromCircle(center: center, radius: coneRadius);
    final headingCone = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(coneBounds, -pi / 2 - halfAngle, halfAngle * 2, false)
      ..close();
    canvas.drawPath(
      headingCone,
      Paint()
        ..shader = ui.Gradient.radial(
          center,
          coneRadius,
          const [Color(0x8F1976D2), Color(0x451976D2), Color(0x001976D2)],
          const [0, 0.58, 1],
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );
  }

  canvas.drawCircle(
    center + const Offset(0, 2),
    kLocationMarkerIconRimRadius + 3,
    Paint()
      ..color = const Color(0x33000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
  );
  canvas.drawCircle(
    center,
    kLocationMarkerIconRimRadius,
    Paint()..color = Colors.white,
  );

  canvas.drawCircle(
    center,
    kLocationMarkerIconCoreRadius,
    Paint()..color = kLocationMarkerColor,
  );
  // 코어 왼쪽 위의 광택 점. 코어 크기를 바꿔도 비율이 유지되도록 코어 반지름에서
  // 파생시킨다(원본 디자인의 코어 18 / offset 5 / 반지름 4.5 비율).
  const glossOffset = kLocationMarkerIconCoreRadius * 0.28;
  canvas.drawCircle(
    center - const Offset(glossOffset, glossOffset),
    kLocationMarkerIconCoreRadius * 0.25,
    Paint()..color = const Color(0x66FFFFFF),
  );

  final image = await recorder.endRecording().toImage(
    pixelSize.toInt(),
    pixelSize.toInt(),
  );
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}

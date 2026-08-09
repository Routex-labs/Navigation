import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/outdoor_map/indoor_entry_zoom.dart';

/// 더현대 서울 각 층 도면이 **정북 정렬 화면**에서 차지하는 크기(m).
///
/// DB의 `floors.footprint_local_m`는 건물 로컬 좌표라 B3·B4가 295 x 148 m지만,
/// 이 건물은 정북 기준 약 53도 돌아가 있어 화면에 투영하면 286 x 305 m가 된다.
/// 임계값은 화면에 담기는지로 판정해야 하므로 정북 정렬 값을 쓴다.
/// (`nodes`의 x_m/y_m ↔ lat/lng로 affine을 복원해 산출. 잔차 0.00 m.)
const _floorScreenExtentsM = <String, ({double width, double height})>{
  'B6': (width: 260.0, height: 294.1),
  'B5': (width: 260.0, height: 294.1),
  'B4': (width: 286.1, height: 305.1),
  'B3': (width: 286.1, height: 305.1),
  'B2': (width: 175.7, height: 184.0),
  'B1': (width: 178.3, height: 190.8),
  '1F': (width: 179.3, height: 190.4),
  '6F': (width: 181.7, height: 192.7),
};

/// 화면 좌우에 두는 최소 여백. 도면이 화면 끝에 딱 붙으면 "다 보인다"는
/// 느낌이 안 나므로 여기까지 포함해 fit zoom을 잡는다.
const _fitPaddingPx = 24.0;

double _fitZoomFor(({double width, double height}) extent) => zoomToFitWidth(
  widthMeters: extent.width,
  availablePx: referenceViewportWidthPx - _fitPaddingPx * 2,
  latitude: referenceLatitude,
);

void main() {
  group('zoom↔미터 변환 상수', () {
    test('실제 지도에서 측정한 값(z=17에서 약 0.474 m/px)과 일치한다', () {
      // maplibre_gl(web)에서 toScreenLocation으로 잰 값. 256 타일 규약
      // (156543)을 쓰면 여기서 0.237이 나와 2배 어긋난다.
      final mpp = visibleWidthMeters(
        zoom: 17,
        availablePx: 1,
        latitude: referenceLatitude,
      );
      expect(mpp, closeTo(0.474, 0.005));
    });

    test('zoomToFitWidth와 visibleWidthMeters는 서로의 역함수다', () {
      final z = zoomToFitWidth(
        widthMeters: 286.1,
        availablePx: 312,
        latitude: referenceLatitude,
      );
      final w = visibleWidthMeters(
        zoom: z,
        availablePx: 312,
        latitude: referenceLatitude,
      );
      expect(w, closeTo(286.1, 0.01));
    });
  });

  group('이탈 임계값 — 이번 수정의 핵심 검증 기준', () {
    test('모든 층이 이탈 임계값보다 확대된 상태에서 화면에 다 들어온다', () {
      // "도면이 다 담기지도 않았는데 실내에서 벗어나는" 증상을 막는 조건.
      // fit zoom이 이탈 임계값보다 높아야(=더 확대된 상태여야) 사용자가
      // 도면 전체를 본 뒤에도 아직 실내에 남아 있다.
      for (final entry in _floorScreenExtentsM.entries) {
        final fitZoom = _fitZoomFor(entry.value);
        expect(
          fitZoom,
          greaterThan(indoorExitZoomThreshold),
          reason:
              '${entry.key} 층 전체가 보이는 zoom ${fitZoom.toStringAsFixed(2)}는 '
              '이탈 임계값 $indoorExitZoomThreshold 이하 — 다 보기 전에 튕겨 나간다',
        );
      }
    });

    test('가장 넓은 지하층이 이탈 임계값에서 여유를 두고 들어온다', () {
      final widest = _floorScreenExtentsM.values
          .map((e) => e.width)
          .reduce(math.max);
      final visible = visibleWidthMeters(
        zoom: indoorExitZoomThreshold,
        availablePx: referenceViewportWidthPx,
        latitude: referenceLatitude,
      );
      expect(
        visible,
        greaterThan(widest * 1.2),
        reason:
            '이탈 임계값에서 보이는 폭 ${visible.toStringAsFixed(0)} m가 '
            '가장 넓은 층 ${widest.toStringAsFixed(0)} m + 20% 여유에 못 미친다',
      );
    });

    test('이탈을 도면이 다 보이는 zoom으로 되돌리면 이 기준이 깨진다', () {
      // 회귀 방향을 못박아 둔다 — 예전처럼 이탈을 17.5로 올리면 가장 넓은
      // 지하층은 화면에 다 들어오지 못한다.
      final visibleAtEntry = visibleWidthMeters(
        zoom: indoorFocusZoom,
        availablePx: referenceViewportWidthPx,
        latitude: referenceLatitude,
      );
      expect(visibleAtEntry, lessThan(_floorScreenExtentsM['B4']!.width));
    });
  });

  group('zoom은 이탈만 판정한다', () {
    // 이 그룹이 지키는 규칙: 확대는 "저 건물을 자세히 보고 싶다"는 뜻이지
    // "저 안에 들어왔다"가 아니다. 진입은 도면 탭과 GPS만 맡는다.
    test('아무리 확대해도 이탈이 아니다(=진입도 아니다)', () {
      for (final z in [17.5, 18.0, 19.0, 21.0]) {
        expect(
          shouldExitIndoorForZoom(z),
          isFalse,
          reason: 'zoom $z에서 상태가 바뀌면 안 된다',
        );
      }
    });

    test('층 전체를 보려고 축소하는 구간에서는 남아 있는다', () {
      for (final z in [15.6, 16.0, 16.5, 17.0, 17.49]) {
        expect(
          shouldExitIndoorForZoom(z),
          isFalse,
          reason: 'zoom $z는 층 전체를 보는 구간이라 실내를 유지해야 한다',
        );
      }
    });

    test('이탈 임계값 경계에서 갈린다', () {
      expect(shouldExitIndoorForZoom(indoorExitZoomThreshold - 0.01), isTrue);
      expect(shouldExitIndoorForZoom(indoorExitZoomThreshold), isFalse);
    });

    test('도면이 다 보이는 zoom과 이탈 임계값 사이가 넉넉하다', () {
      // 두 값이 붙어 있으면 층 전체를 보려고 조금만 축소해도 야외로 튕긴다.
      expect(indoorFocusZoom - indoorExitZoomThreshold, greaterThan(1.0));
    });
  });

  group('오버레이 페이드', () {
    test('진입 후에는 층 전체가 보이는 zoom까지 100% 불투명을 유지한다', () {
      for (final entry in _floorScreenExtentsM.entries) {
        final fitZoom = _fitZoomFor(entry.value);
        expect(
          indoorOverlayOpacityAt(zoom: fitZoom, entered: true),
          1.0,
          reason: '${entry.key} 층 전체를 담은 순간 도면이 이미 흐려져 있다',
        );
      }
    });

    test('이탈하는 순간 도면이 툭 끊기지 않는다', () {
      // 이탈 판정이 나면 램프가 진입 램프로 되돌아간다. 그 경계에서 양쪽
      // opacity가 모두 0이어야 시각적 점프가 없다.
      const z = indoorExitZoomThreshold;
      expect(indoorOverlayOpacityAt(zoom: z, entered: true), 0.0);
      expect(indoorOverlayOpacityAt(zoom: z, entered: false), 0.0);
    });

    test('진입 전에는 야외 지도를 훑는 동안 도면이 끼어들지 않는다', () {
      expect(indoorOverlayOpacityAt(zoom: 16.4, entered: false), 0.0);
      expect(
        indoorOverlayOpacityAt(zoom: indoorFocusZoom, entered: false),
        1.0,
      );
    });

    test('두 램프 모두 단조 증가한다', () {
      for (final entered in [true, false]) {
        var prev = -1.0;
        for (var z = 15.0; z <= 18.0; z += 0.05) {
          final o = indoorOverlayOpacityAt(zoom: z, entered: entered);
          expect(o, greaterThanOrEqualTo(prev - 1e-9));
          prev = o;
        }
      }
    });

    test('maxOpacity는 램프 상단만 scale한다 (dim scrim용)', () {
      expect(
        indoorOverlayOpacityAt(zoom: 18, entered: true, maxOpacity: 0.35),
        0.35,
      );
      expect(
        indoorOverlayOpacityAt(zoom: 15.0, entered: true, maxOpacity: 0.35),
        0.0,
      );
    });

    test('페이드 표현식이 미러 함수와 같은 stop을 쓴다', () {
      for (final entered in [true, false]) {
        final expr = indoorOverlayFadeExpr(entered: entered);
        expect(expr[0], 'interpolate');
        final startZoom = expr[3] as double;
        final endZoom = expr[5] as double;
        expect(indoorOverlayOpacityAt(zoom: startZoom, entered: entered), 0.0);
        expect(indoorOverlayOpacityAt(zoom: endZoom, entered: entered), 1.0);
      }
    });
  });

  group('MVT 소스 zoom 범위', () {
    test('도면이 조금이라도 보이는 zoom을 minzoom이 모두 덮는다', () {
      // MapLibre가 요청하는 타일 z는 카메라 zoom의 내림이다. opacity > 0인
      // 최저 카메라 zoom에서의 타일 z가 minzoom 아래로 내려가면, 그 구간에서
      // 도면이 통째로 비어 버린다.
      for (var z = indoorExitZoomThreshold; z <= 19.0; z += 0.05) {
        final visible =
            indoorOverlayOpacityAt(zoom: z, entered: true) > 0 ||
            indoorOverlayOpacityAt(zoom: z, entered: false) > 0;
        if (!visible) continue;
        expect(
          z.floorToDouble(),
          greaterThanOrEqualTo(indoorTilesMinZoom),
          reason:
              'zoom $z에서 도면이 보이는데 타일 z=${z.floor()}는 '
              'minzoom $indoorTilesMinZoom 미만이라 요청되지 않는다',
        );
      }
    });

    test('minzoom은 필요한 만큼만 낮다', () {
      // 불필요하게 낮추면 저-zoom 부모 타일이 캐시돼 over-scale 왜곡이 보인다.
      expect(indoorTilesMinZoom, indoorExitZoomThreshold.floorToDouble());
    });

    test('maxzoom이 포커스 zoom보다 높다', () {
      expect(indoorTilesMaxZoom, greaterThan(indoorFocusZoom));
    });
  });

  group('포커스 zoom의 화면 폭 보정', () {
    // 이 그룹이 지키는 증상: 고정 17.5로 카메라를 맞추면 폰에서는 건물이 화면
    // 밖으로 넘치게 확대돼, 포커스를 맞췄는데 오히려 건물이 안 보인다. 같은 값이
    // 화면 폭에 따라 "얼마나 넓은 땅이 보이는지"를 다르게 의미하기 때문이다.
    const buildingWidthM = 179.3; // 1F 정북 정렬 폭

    double thresholdAt(double viewportPx) => indoorFocusZoomFor(
      buildingWidthMeters: buildingWidthM,
      viewportWidthPx: viewportPx,
      latitude: referenceLatitude,
    );

    test('폰 폭에서는 건물이 화면에 딱 담기는 zoom을 쓴다', () {
      final threshold = thresholdAt(referenceViewportWidthPx);
      // 보정 전에는 17.5라 건물이 화면 밖으로 넘쳤다.
      expect(threshold, lessThan(indoorFocusZoom));
      final visible = visibleWidthMeters(
        zoom: threshold,
        availablePx: referenceViewportWidthPx,
        latitude: referenceLatitude,
      );
      // zoomToFitWidth ↔ visibleWidthMeters 왕복에서 1e-13 수준 오차가 남으므로
      // 경계를 mm 단위로 느슨하게 잡는다.
      expect(
        visible,
        greaterThan(buildingWidthM - 0.001),
        reason:
            '포커스 zoom에서 보이는 폭 ${visible.toStringAsFixed(0)} m가 건물 폭 '
            '$buildingWidthM m보다 좁다 — 건물이 화면 밖으로 넘친다',
      );
    });

    test('넓은 화면에서는 기본값이 그대로 쓰인다(데스크톱 회귀 방지)', () {
      expect(thresholdAt(1400), indoorFocusZoom);
    });

    test('어떤 화면 폭에서도 기본값보다 깊게 확대하지 않는다', () {
      for (var px = 280.0; px <= 2400.0; px += 20) {
        expect(
          thresholdAt(px),
          lessThanOrEqualTo(indoorFocusZoom),
          reason: '화면 폭 $px px에서 포커스 zoom이 기본값보다 높아졌다',
        );
      }
    });

    test('아주 넓은 건물 + 좁은 화면에서도 이탈 임계값 위에 남는다', () {
      // 하한이 없으면 포커스 zoom이 이탈 임계값 아래로 내려가, 카메라를 맞춘
      // 그 자리에서 곧바로 이탈 판정이 난다.
      for (final width in [286.1, 500.0, 1200.0, 5000.0]) {
        final threshold = indoorFocusZoomFor(
          buildingWidthMeters: width,
          viewportWidthPx: 280,
          latitude: referenceLatitude,
        );
        expect(
          threshold,
          greaterThan(indoorExitZoomThreshold),
          reason: '건물 폭 $width m에서 포커스 zoom이 이탈 임계값 이하로 내려갔다',
        );
      }
    });

    test('낮아진 포커스 zoom에서도 도면은 흐리지 않다', () {
      // 하한을 페이드 아웃 램프 끝(16.0)에 맞춘 이유. 실내 상태의 램프가 이미
      // 100%인 zoom에서만 카메라를 멈춰야 한다.
      for (final px in [280.0, 320.0, referenceViewportWidthPx, 430.0, 768.0]) {
        final threshold = thresholdAt(px);
        expect(
          indoorOverlayOpacityAt(zoom: threshold, entered: true),
          1.0,
          reason: '화면 폭 $px px의 포커스 zoom에서 도면이 100% 불투명하지 않다',
        );
      }
    });

    test('건물 폭이나 화면 폭이 없으면 보정하지 않는다', () {
      expect(
        indoorFocusZoomFor(
          buildingWidthMeters: 0,
          viewportWidthPx: referenceViewportWidthPx,
          latitude: referenceLatitude,
        ),
        indoorFocusZoom,
      );
      expect(
        indoorFocusZoomFor(
          buildingWidthMeters: buildingWidthM,
          viewportWidthPx: 0,
          latitude: referenceLatitude,
        ),
        indoorFocusZoom,
      );
    });

    test('보정된 포커스 zoom에서 이탈 판정이 나지 않는다', () {
      // 카메라를 맞춘 자리가 곧 이탈 구간이면, 층 chip을 누를 때마다 화면이
      // 실내로 갔다가 야외로 되돌아온다.
      for (final px in [280.0, referenceViewportWidthPx, 768.0, 1400.0]) {
        expect(shouldExitIndoorForZoom(thresholdAt(px)), isFalse);
      }
    });
  });
}

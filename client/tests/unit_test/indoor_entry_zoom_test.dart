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

    test('예전 동작(진입=이탈)에서는 이 기준이 실제로 깨진다', () {
      // 회귀 방향을 못박아 둔다 — 이탈을 진입 임계값으로 되돌리면 가장 넓은
      // 지하층은 화면에 다 들어오지 못한다.
      final visibleAtEntry = visibleWidthMeters(
        zoom: indoorEntryZoomThreshold,
        availablePx: referenceViewportWidthPx,
        latitude: referenceLatitude,
      );
      expect(visibleAtEntry, lessThan(_floorScreenExtentsM['B4']!.width));
    });
  });

  group('히스테리시스', () {
    test('진입 임계값이 이탈 임계값보다 확실히 높다', () {
      expect(
        indoorEntryZoomThreshold - indoorExitZoomThreshold,
        greaterThan(1.0),
      );
    });

    test('밴드 안에서는 상태를 유지한다', () {
      for (final z in [15.6, 16.0, 16.5, 17.0, 17.49]) {
        expect(
          indoorEntryTransitionForZoom(z),
          IndoorEntryTransition.keep,
          reason: 'zoom $z는 히스테리시스 밴드 안이어야 한다',
        );
      }
    });

    test('임계값 경계에서 진입·이탈이 갈린다', () {
      expect(
        indoorEntryTransitionForZoom(indoorEntryZoomThreshold),
        IndoorEntryTransition.enter,
      );
      expect(
        indoorEntryTransitionForZoom(indoorExitZoomThreshold - 0.01),
        IndoorEntryTransition.exit,
      );
      expect(
        indoorEntryTransitionForZoom(indoorExitZoomThreshold),
        IndoorEntryTransition.keep,
      );
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
        indoorOverlayOpacityAt(zoom: indoorEntryZoomThreshold, entered: false),
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

    test('maxzoom이 진입 임계값보다 높다', () {
      expect(indoorTilesMaxZoom, greaterThan(indoorEntryZoomThreshold));
    });
  });
}

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/outdoor_map/indoor_entry_zoom.dart';
import 'package:navigation_client/map/zoom_math.dart';

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
          indoorEntryTransitionForZoom(
            z,
            buildingNearby: true,
            entryZoom: indoorEntryZoomThreshold,
          ),
          IndoorEntryTransition.keep,
          reason: 'zoom $z는 히스테리시스 밴드 안이어야 한다',
        );
      }
    });

    test('임계값 경계에서 진입·이탈이 갈린다', () {
      expect(
        indoorEntryTransitionForZoom(
          indoorEntryZoomThreshold,
          buildingNearby: true,
          entryZoom: indoorEntryZoomThreshold,
        ),
        IndoorEntryTransition.enter,
      );
      expect(
        indoorEntryTransitionForZoom(
          indoorExitZoomThreshold - 0.01,
          buildingNearby: true,
          entryZoom: indoorEntryZoomThreshold,
        ),
        IndoorEntryTransition.exit,
      );
      expect(
        indoorEntryTransitionForZoom(
          indoorExitZoomThreshold,
          buildingNearby: true,
          entryZoom: indoorEntryZoomThreshold,
        ),
        IndoorEntryTransition.keep,
      );
    });
  });

  group('건물 근접 게이트', () {
    // 이 그룹이 지키는 증상: 실내 도면이 있는 건물이 주변에 없는데도 확대만
    // 하면 실내 모드로 전환돼, 도면 한 장 없이 층 선택기와 위치 지정 버튼만
    // 뜨던 문제.
    test('건물이 주변에 없으면 아무리 확대해도 진입하지 않는다', () {
      for (final z in [17.5, 18.0, 19.0, 21.0]) {
        expect(
          indoorEntryTransitionForZoom(
            z,
            buildingNearby: false,
            entryZoom: indoorEntryZoomThreshold,
          ),
          IndoorEntryTransition.keep,
          reason: 'zoom $z에서 건물 없이 실내로 들어가면 안 된다',
        );
      }
    });

    test('건물이 없어도 이탈 판정은 zoom만으로 유지된다', () {
      // 근접 게이트가 이탈까지 건드리면, 실내에서 도면 끝을 보려고 살짝 패닝한
      // 순간 야외로 튕겨 나간다. 이탈은 축소와 건물 밖 탭만 담당한다.
      expect(
        indoorEntryTransitionForZoom(
          indoorExitZoomThreshold - 0.01,
          buildingNearby: false,
          entryZoom: indoorEntryZoomThreshold,
        ),
        IndoorEntryTransition.exit,
      );
      expect(
        indoorEntryTransitionForZoom(
          17.0,
          buildingNearby: false,
          entryZoom: indoorEntryZoomThreshold,
        ),
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

  group('진입 임계값의 화면 폭 보정', () {
    // 이 그룹이 지키는 증상: 데스크톱 Chrome에서는 확대만으로 실내에 들어가는데
    // 폰 실기기에서는 아무리 확대해도 층 선택기·위치 지정 버튼이 뜨지 않던 문제.
    // 고정 임계값 17.5가 화면 폭에 따라 "얼마나 확대한 상태인지"를 다르게
    // 의미해서 생긴 일이다.
    const buildingWidthM = 179.3; // 1F 정북 정렬 폭

    double thresholdAt(double viewportPx) => indoorEntryZoomThresholdFor(
      buildingWidthMeters: buildingWidthM,
      viewportWidthPx: viewportPx,
      latitude: referenceLatitude,
    );

    test('폰 폭에서는 건물이 화면에 담기는 순간 진입한다', () {
      final threshold = thresholdAt(referenceViewportWidthPx);
      // 보정 전에는 17.5여서, 건물이 화면 밖으로 넘칠 때까지 확대해야 닿았다.
      expect(threshold, lessThan(indoorEntryZoomThreshold));
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
            '진입하는 순간 보이는 폭 ${visible.toStringAsFixed(0)} m가 건물 폭 '
            '$buildingWidthM m보다 좁다 — 건물이 화면 밖으로 넘쳐야만 진입한다',
      );
    });

    test('넓은 화면에서는 기존 임계값이 그대로 쓰인다(데스크톱 회귀 방지)', () {
      expect(thresholdAt(1400), indoorEntryZoomThreshold);
    });

    test('어떤 화면 폭에서도 지금보다 진입이 어려워지지 않는다', () {
      for (var px = 280.0; px <= 2400.0; px += 20) {
        expect(
          thresholdAt(px),
          lessThanOrEqualTo(indoorEntryZoomThreshold),
          reason: '화면 폭 $px px에서 임계값이 기존보다 높아졌다',
        );
      }
    });

    test('아주 넓은 건물 + 좁은 화면에서도 이탈 임계값 위에 남는다', () {
      // 하한이 없으면 진입 임계값이 이탈 임계값 아래로 내려가 같은 zoom에서
      // 진입과 이탈이 동시에 성립하고, 오버레이가 켜졌다 꺼졌다 진동한다.
      for (final width in [286.1, 500.0, 1200.0, 5000.0]) {
        final threshold = indoorEntryZoomThresholdFor(
          buildingWidthMeters: width,
          viewportWidthPx: 280,
          latitude: referenceLatitude,
        );
        expect(
          threshold,
          greaterThan(indoorExitZoomThreshold),
          reason: '건물 폭 $width m에서 진입 임계값이 이탈 임계값 이하로 내려갔다',
        );
      }
    });

    test('낮아진 임계값으로 진입해도 도면은 흐리지 않다', () {
      // 하한을 페이드 아웃 램프 끝(16.0)에 맞춘 이유. 진입 순간 램프가 "진입 후"
      // 램프로 갈아끼워지므로, 그 램프가 이미 100%인 zoom에서만 진입해야 한다.
      for (final px in [280.0, 320.0, referenceViewportWidthPx, 430.0, 768.0]) {
        final threshold = thresholdAt(px);
        expect(
          indoorOverlayOpacityAt(zoom: threshold, entered: true),
          1.0,
          reason: '화면 폭 $px px의 진입 zoom에서 도면이 100% 불투명하지 않다',
        );
      }
    });

    test('건물 폭이나 화면 폭이 없으면 보정하지 않는다', () {
      expect(
        indoorEntryZoomThresholdFor(
          buildingWidthMeters: 0,
          viewportWidthPx: referenceViewportWidthPx,
          latitude: referenceLatitude,
        ),
        indoorEntryZoomThreshold,
      );
      expect(
        indoorEntryZoomThresholdFor(
          buildingWidthMeters: buildingWidthM,
          viewportWidthPx: 0,
          latitude: referenceLatitude,
        ),
        indoorEntryZoomThreshold,
      );
    });

    test('보정된 임계값이 실제 진입 판정에 반영된다', () {
      final threshold = thresholdAt(referenceViewportWidthPx);
      // 보정 전이라면 keep이었을 zoom에서 enter가 나와야 한다.
      expect(threshold, lessThan(indoorEntryZoomThreshold));
      expect(
        indoorEntryTransitionForZoom(
          threshold,
          buildingNearby: true,
          entryZoom: threshold,
        ),
        IndoorEntryTransition.enter,
      );
      // 근접 게이트는 그대로 살아 있다 — 건물이 없으면 여전히 안 들어간다.
      expect(
        indoorEntryTransitionForZoom(
          threshold,
          buildingNearby: false,
          entryZoom: threshold,
        ),
        IndoorEntryTransition.keep,
      );
    });
  });
  group('건물 바깥 보기 — 검색만 했는데 실내가 열리면 안 된다', () {
    // 이 그룹이 지키는 증상: 검색에서 "더현대 서울"을 고르자마자 도면이 열리던
    // 문제. 카메라를 건물 외곽선에 꼭 맞췄는데, 그 배율이 곧 진입 조건이었다
    // (진입 임계값의 정의가 "건물이 화면에 담기는 zoom"이다). 검색은 저 건물이
    // 어디 있는지를 묻는 조작이고, 들어가는 것은 건물을 탭하는 별도 조작이다.

    test('바깥 보기 배율에서는 진입이 발화하지 않는다 — 모든 층·화면 폭에서', () {
      for (final entry in _floorScreenExtentsM.entries) {
        final width = entry.value.width;
        for (var px = 280.0; px <= 2400.0; px += 20) {
          final entryZoom = indoorEntryZoomThresholdFor(
            buildingWidthMeters: width,
            viewportWidthPx: px,
            latitude: referenceLatitude,
          );
          final exterior = exteriorViewZoomFor(
            buildingWidthMeters: width,
            viewportWidthPx: px,
            latitude: referenceLatitude,
          );
          expect(
            indoorEntryTransitionForZoom(
              exterior,
              // 건물을 화면에 놓고 보는 중이니 근접 게이트는 당연히 통과한다.
              // 그 게이트에 기대면 안 된다는 것이 이 테스트의 요점이다.
              buildingNearby: true,
              entryZoom: entryZoom,
            ),
            isNot(IndoorEntryTransition.enter),
            reason:
                '${entry.key}(폭 ${width.toStringAsFixed(0)} m)를 ${px.toStringAsFixed(0)} px '
                '화면에서 바깥 보기로 잡으면 zoom ${exterior.toStringAsFixed(2)}인데 '
                '진입 임계값이 ${entryZoom.toStringAsFixed(2)}라 그대로 실내로 들어간다',
          );
        }
      }
    });

    test('그렇다고 건물이 안 보일 만큼 물러서지는 않는다', () {
      // 너무 많이 빼면 "여기 있다"가 아니라 "어딘가에 있다"가 된다. 건물이
      // 화면 폭의 절반 이상은 차지해야 한다.
      const width = 179.3; // 1F 정북 정렬 폭
      final exterior = exteriorViewZoomFor(
        buildingWidthMeters: width,
        viewportWidthPx: referenceViewportWidthPx,
        latitude: referenceLatitude,
      );
      final visible = visibleWidthMeters(
        zoom: exterior,
        availablePx: referenceViewportWidthPx,
        latitude: referenceLatitude,
      );
      expect(
        width / visible,
        greaterThan(0.5),
        reason:
            '건물이 화면 폭의 ${(width / visible * 100).toStringAsFixed(0)}%밖에 '
            '차지하지 않는다 — 무엇을 고른 것인지 알아보기 어렵다',
      );
    });
  });
  group('돌려 세운 상자 맞추기', () {
    // 세로로 세운 건물을 화면에 담을 때는 가로·세로 두 제약을 **동시에** 지켜야
    // 한다. 한쪽만 보면 나머지 축이 잘린 채로 확대된다.
    const shortM = 148.0; // 짧은 축(화면 가로)
    const longM = 295.0; // 긴 축(화면 세로)

    test('두 축 모두 화면 안에 들어온다', () {
      // 세로로 긴 폰부터 가로로 넓은 태블릿까지 훑는다.
      for (final (wPx, hPx) in [
        (360.0, 640.0),
        (480.0, 1029.0),
        (412.0, 915.0),
        (834.0, 1112.0),
        (1280.0, 800.0),
      ]) {
        final zoom = zoomToFitRotatedBox(
          widthMeters: shortM,
          heightMeters: longM,
          viewportWidthPx: wPx,
          viewportHeightPx: hPx,
          latitude: referenceLatitude,
        );
        final visibleW = visibleWidthMeters(
          zoom: zoom,
          availablePx: wPx,
          latitude: referenceLatitude,
        );
        final visibleH = visibleWidthMeters(
          zoom: zoom,
          availablePx: hPx,
          latitude: referenceLatitude,
        );
        expect(
          visibleW,
          greaterThan(shortM - 0.001),
          reason:
              '${wPx.toStringAsFixed(0)}x${hPx.toStringAsFixed(0)}에서 가로가 잘린다',
        );
        expect(
          visibleH,
          greaterThan(longM - 0.001),
          reason:
              '${wPx.toStringAsFixed(0)}x${hPx.toStringAsFixed(0)}에서 세로가 잘린다',
        );
      }
    });

    test('가로로 넓은 화면에서는 세로가 제약이 된다', () {
      // 태블릿 가로 모드처럼 폭이 넉넉하면 긴 축이 먼저 화면을 채운다.
      final zoom = zoomToFitRotatedBox(
        widthMeters: shortM,
        heightMeters: longM,
        viewportWidthPx: 1280,
        viewportHeightPx: 800,
        latitude: referenceLatitude,
      );
      final byHeightOnly = zoomToFitWidth(
        widthMeters: longM,
        availablePx: 800,
        latitude: referenceLatitude,
      );
      expect(zoom, closeTo(byHeightOnly, 1e-9));
    });

    test('세로로 긴 폰에서는 가로가 제약이 된다', () {
      final zoom = zoomToFitRotatedBox(
        widthMeters: shortM,
        heightMeters: longM,
        viewportWidthPx: 480,
        viewportHeightPx: 1029,
        latitude: referenceLatitude,
      );
      final byWidthOnly = zoomToFitWidth(
        widthMeters: shortM,
        availablePx: 480,
        latitude: referenceLatitude,
      );
      expect(zoom, closeTo(byWidthOnly, 1e-9));
    });

    test('세로로 세우면 정북 정렬보다 더 확대할 수 있다', () {
      // 이 기능의 목적 자체다 — 같은 화면에서 도면이 더 크게 들어온다.
      // 정북 정렬 폭은 53도 돌아앉은 148x295 건물의 축 정렬 상자 폭이다.
      final northAlignedWidth =
          shortM * math.cos(53 * math.pi / 180).abs() +
          longM * math.sin(53 * math.pi / 180).abs();
      final upright = zoomToFitRotatedBox(
        widthMeters: shortM,
        heightMeters: longM,
        viewportWidthPx: 480,
        viewportHeightPx: 1029,
        latitude: referenceLatitude,
      );
      final northUp = zoomToFitWidth(
        widthMeters: northAlignedWidth,
        availablePx: 480,
        latitude: referenceLatitude,
      );
      expect(
        upright,
        greaterThan(northUp),
        reason:
            '세로로 세웠는데도 정북 정렬($northUp)보다 확대가 안 된다면 '
            '돌릴 이유가 없다',
      );
    });
  });

  group('층 전환 크로스페이드 opacity 표현식', () {
    // 실기기 회귀: ['*', factor, interpolate]로 감싸면 MapLibre native가
    // "zoom expression may only be used as input to a top-level step or
    // interpolate"로 속성을 거부하고, opacity가 스펙 기본값 1로 굳어 새 도면이
    // 투명하게 얹히지도, 페이드인되지도 않았다. 표현식은 어떤 계수에서도
    // zoom을 입력으로 갖는 **최상위 interpolate**여야 한다.
    test('어떤 계수에서도 최상위 interpolate를 유지한다(곱셈 래핑 금지)', () {
      for (final factor in [0.0, 0.25, 0.62, 1.0]) {
        final expr = indoorOverlayCrossfadeExpr(
          entered: true,
          crossfadeFactor: factor,
        );
        expect(
          expr.first,
          'interpolate',
          reason: '계수 $factor에서 표현식이 최상위 interpolate가 아니면 '
              'native가 opacity 설정을 거부한다',
        );
        expect(
          expr[2],
          ['zoom'],
          reason: 'zoom은 최상위 interpolate의 입력 자리에 있어야 한다',
        );
      }
    });

    test('계수는 램프 끝 스톱에 곱해져 곱셈과 같은 값을 낸다', () {
      const factor = 0.4;
      final expr = indoorOverlayCrossfadeExpr(
        entered: true,
        crossfadeFactor: factor,
      );
      // 시작 스톱 값은 0(곱해도 0), 끝 스톱 값은 factor여야 모든 zoom에서
      // "원래 램프 × factor"와 일치한다.
      expect(expr[4], 0);
      expect(expr[6], factor);
      // 미러 함수로도 확인: 램프 끝(z=17)에서 0.4, 램프 시작 아래에서 0.
      expect(
        indoorOverlayOpacityAt(zoom: 17, entered: true, maxOpacity: factor),
        factor,
      );
      expect(
        indoorOverlayOpacityAt(zoom: 15, entered: true, maxOpacity: factor),
        0,
      );
    });

    test('계수 1이면 원래 페이드 램프와 같다', () {
      expect(
        indoorOverlayCrossfadeExpr(entered: true, crossfadeFactor: 1),
        indoorOverlayFadeExpr(entered: true),
      );
      expect(
        indoorOverlayCrossfadeExpr(entered: false, crossfadeFactor: 1),
        indoorOverlayFadeExpr(entered: false),
      );
    });

    test('범위를 벗어난 계수는 0~1로 잘린다', () {
      expect(
        indoorOverlayCrossfadeExpr(entered: true, crossfadeFactor: -0.2),
        indoorOverlayFadeExpr(entered: true, maxOpacity: 0),
      );
      expect(
        indoorOverlayCrossfadeExpr(entered: true, crossfadeFactor: 1.7),
        indoorOverlayFadeExpr(entered: true, maxOpacity: 1),
      );
    });
  });
}

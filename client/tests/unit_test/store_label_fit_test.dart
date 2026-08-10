import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_client/screens/outdoor_map/indoor_entry_zoom.dart';
import 'package:navigation_client/widgets/store_label_fit.dart';

/// 서울 기준 위도. 도면 하나 안에서는 상수로 봐도 되는 값이다.
const _lat = 37.5;

double _pixelsPerMeter(double zoom) =>
    pow(2, zoom) / (metersPerPixelAtZoom0Equator * cos(_lat * pi / 180));

/// [storeLabelTextSizeExpression]이 만든 stop 하나를 실제로 계산해 본다.
///
/// 표현식 모양: `['max', min, ['min', max, ['*', ['get', prop], pxPerMeter]]]`.
/// 구조를 그대로 따라가야 "표현식이 의도한 계산을 담고 있다"를 확인할 수 있다.
double _evalStop(Object stop, double emMeters) {
  final clampLow = stop as List<Object>;
  expect(clampLow[0], 'max');
  final minPx = clampLow[1] as double;
  final clampHigh = clampLow[2] as List<Object>;
  expect(clampHigh[0], 'min');
  final maxPx = clampHigh[1] as double;
  final product = clampHigh[2] as List<Object>;
  expect(product[0], '*');
  expect(product[1], <Object>['get', kStoreLabelEmMetersProperty]);
  final pixelsPerMeter = product[2] as double;
  return max(minPx, min(maxPx, emMeters * pixelsPerMeter));
}

/// zoom → 그 stop을 꺼낸다. 표현식은 `[interpolate, [exponential,2], [zoom], z, v, ...]`.
Map<double, Object> _stops(List<Object> expression) {
  expect(expression[0], 'interpolate');
  expect(expression[1], <Object>['exponential', 2]);
  expect(expression[2], <Object>['zoom']);
  final stops = <double, Object>{};
  for (var i = 3; i < expression.length; i += 2) {
    stops[expression[i] as double] = expression[i + 1];
  }
  return stops;
}

/// 위경도 사각형을 만든다. [widthM]은 동서(경도) 방향, [heightM]은 남북 방향.
List<LatLng> _rectangle({required double widthM, required double heightM}) {
  const metersPerDegreeLat = 111320.0;
  final dLat = heightM / metersPerDegreeLat;
  final dLng = widthM / (metersPerDegreeLat * cos(_lat * pi / 180));
  return [
    LatLng(_lat, 127.0),
    LatLng(_lat, 127.0 + dLng),
    LatLng(_lat + dLat, 127.0 + dLng),
    LatLng(_lat + dLat, 127.0),
  ];
}

void main() {
  group('storeLabelEmWidth', () {
    test('한글은 전각, 라틴은 그 절반 남짓으로 잰다', () {
      expect(storeLabelEmWidth('루이비통'), closeTo(4.0, 1e-9));
      // 라틴 4글자가 한글 4글자보다 뚜렷하게 좁아야 줄바꿈 계산이 뒤집히지 않는다.
      expect(storeLabelEmWidth('ZARA'), lessThan(storeLabelEmWidth('루이비통')));
    });

    test('빈 이름은 0이다', () {
      expect(storeLabelEmWidth(''), 0);
    });
  });

  group('storeLabelLineWidths', () {
    test('공백 없는 한글 이름도 글자 사이에서 접힌다', () {
      // 이 규칙이 없으면 한글 매장명은 절대 접히지 않아 가로로만 길어진다.
      final lines = storeLabelLineWidths('루이비통', 2.0);
      expect(lines, hasLength(2));
      expect(lines.every((w) => w <= 2.0 + 1e-9), isTrue);
    });

    test('쪼갤 수 없는 라틴 단어는 넘치더라도 한 줄로 둔다', () {
      final lines = storeLabelLineWidths('BURBERRY', 1.0);
      expect(lines, hasLength(1));
      expect(lines.first, greaterThan(1.0));
    });

    test('공백에서 끊고 그 공백은 줄 끝에 남기지 않는다', () {
      final lines = storeLabelLineWidths('TAX REFUND', 4.0);
      expect(lines, hasLength(2));
      expect(lines[0], closeTo(storeLabelEmWidth('TAX'), 1e-9));
      expect(lines[1], closeTo(storeLabelEmWidth('REFUND'), 1e-9));
    });
  });

  group('storeLabelWrapWidth', () {
    test('목표 줄 수가 실제로 나오는 폭을 돌려준다', () {
      // 회귀 대상: 예전 근사식 `totalEm / target`은 평균 폭이라 한글 이름에서
      // 목표보다 많은 줄을 만들었다. `조 말론 런던`을 2줄로 접으려다 3줄이 되어
      // 화면에 「조 / 말론 / 런던」이 떴다.
      for (final name in ['조 말론 런던', '루이비통', '리치몬드 과자점', '올리브영']) {
        for (final target in [1, 2, 3]) {
          final lines = storeLabelLineWidths(
            name,
            storeLabelWrapWidth(name, target),
          );
          expect(
            lines.length,
            lessThanOrEqualTo(target),
            reason: '$name을 $target줄로 접으려는데 ${lines.length}줄이 나온다',
          );
        }
      }
    });

    test('목표를 만족하는 폭 중 가장 좁은 것을 고른다', () {
      // 더 좁게 잡을 수 있는데 넓게 주면 라벨이 옆으로 퍼져 매장을 벗어난다.
      const name = '조 말론 런던';
      final width = storeLabelWrapWidth(name, 2);
      expect(storeLabelLineWidths(name, width), hasLength(2));
      // 한 덩어리(전각 1글자 = 1.0em)만큼 좁히면 2줄이 깨져야 최소값이다.
      expect(
        storeLabelLineWidths(name, width - 1.0).length,
        greaterThan(2),
      );
    });

    test('1줄 목표는 이름 전체 폭이다', () {
      expect(storeLabelWrapWidth('루이비통', 1), closeTo(4.0, 1e-9));
    });
  });

  group('fitStoreLabel', () {
    test('한 글자만 남는 줄은 만들지 않는다', () {
      // 실기기 증상: 「르 라보」가 「르」 / 「라보」로 접혀, 첫 줄의 한 글자가
      // 이웃 매장 이름의 조각처럼 읽혔다. 2줄 규칙은 지켰지만 줄의 내용이 문제다.
      final fit = fitStoreLabel(name: '르 라보', boxWidthM: 4.0, boxHeightM: 2.5);
      final lines = storeLabelLineWidths('르 라보', fit.maxWidthEm);

      expect(lines, hasLength(1), reason: '2줄로 쪼갤 수 없는 이름이다');
      expect(lines.first, closeTo(storeLabelEmWidth('르 라보'), 1e-9));
    });

    test('양쪽이 두 글자 이상이면 그대로 2줄로 접는다', () {
      for (final name in ['디올 뷰티', '조 말론 런던', '에스티 로더']) {
        final fit = fitStoreLabel(name: name, boxWidthM: 4.0, boxHeightM: 4.0);
        final lines = storeLabelLineWidths(name, fit.maxWidthEm);
        if (lines.length == 1) continue; // 박스가 넓어 1줄이 이긴 경우
        expect(
          lines.reduce(min),
          greaterThanOrEqualTo(kStoreLabelMinLineEm - 1e-9),
          reason: '$name의 짧은 줄이 두 글자보다 얇다',
        );
      }
    });

    test('짧은 브랜드명이 글자 단위로 흩어지지 않는다', () {
      // 실기기에서 나온 증상 그대로다 — `조 말론 런던`이 세 조각으로 흩어져
      // 각각 다른 매장 이름처럼 읽혔다.
      final fit = fitStoreLabel(
        name: '조 말론 런던',
        boxWidthM: 4.0,
        boxHeightM: 3.0,
      );

      expect(fit.lines, lessThanOrEqualTo(kStoreLabelMaxLines));
      // text-max-width로 그대로 나가는 값이라, 이 폭으로 접었을 때도 같은 줄
      // 수여야 MapLibre가 화면에 같은 모양을 그린다.
      final lines = storeLabelLineWidths('조 말론 런던', fit.maxWidthEm);
      expect(lines, hasLength(fit.lines));
      // 한 줄에 한 글자만 남는 배치가 다시 나오면 여기서 걸린다.
      expect(lines.reduce(max), greaterThan(1.0));
    });

    test('고른 크기로 접으면 실제로 박스 안에 들어간다', () {
      // 이 테스트가 곧 "글자가 매장 밖으로 빠져나가지 않는다"의 정의다.
      const boxWidthM = 5.0;
      const boxHeightM = 5.0;
      final fit = fitStoreLabel(
        name: '루이비통',
        boxWidthM: boxWidthM,
        boxHeightM: boxHeightM,
      );

      expect(fit.emMeters, greaterThan(0));
      expect(
        fit.emMeters * fit.maxWidthEm,
        lessThanOrEqualTo(boxWidthM * kStoreLabelBoxPadding + 1e-9),
      );
      expect(
        fit.emMeters * fit.lines * kStoreLabelLineHeightEm,
        lessThanOrEqualTo(boxHeightM * kStoreLabelBoxPadding + 1e-9),
      );
    });

    test('돌려준 줄바꿈 폭은 그 줄 수를 실제로 만들어 낸다', () {
      // maxWidthEm을 text-max-width로 그대로 걸기 때문에, 이 값으로 접었을 때
      // 계산에 쓴 줄 수가 나와야 세로 예산이 맞는다.
      final fit = fitStoreLabel(
        name: '리치몬드 과자점',
        boxWidthM: 4.0,
        boxHeightM: 4.0,
      );
      final lines = storeLabelLineWidths('리치몬드 과자점', fit.maxWidthEm);
      expect(lines, hasLength(fit.lines));
      expect(lines.reduce(max), lessThanOrEqualTo(fit.maxWidthEm + 1e-9));
    });

    test('같은 이름이면 작은 매장이 더 작은 글자를 받는다', () {
      // 매장 크기가 1.9m~14m로 벌어져 있어서, 모든 매장에 같은 px을 주는 한
      // 어떤 값을 골라도 한쪽은 넘치고 한쪽은 작다 — 이 차이가 그 해결책이다.
      final small = fitStoreLabel(
        name: '올리브영',
        boxWidthM: 2.0,
        boxHeightM: 2.0,
      );
      final large = fitStoreLabel(
        name: '올리브영',
        boxWidthM: 12.0,
        boxHeightM: 9.0,
      );
      expect(large.emMeters, greaterThan(small.emMeters * 3));
    });

    test('긴 이름은 같은 박스에서 더 작은 글자를 받는다', () {
      final short = fitStoreLabel(name: '자라', boxWidthM: 6.0, boxHeightM: 6.0);
      final long = fitStoreLabel(
        name: '사은 고객상담실 수유실 배송 접수 데스크',
        boxWidthM: 6.0,
        boxHeightM: 6.0,
      );
      expect(long.emMeters, lessThan(short.emMeters));
    });

    test('폴리곤이 없는 매장은 크기 0으로 나가 하한이 받는다', () {
      final fit = fitStoreLabel(name: '출구', boxWidthM: 0, boxHeightM: 0);
      expect(fit.emMeters, 0);
      expect(fit.maxWidthEm, greaterThan(0));
      // 하한이 없으면 글자가 사라진다. 0이 들어와도 읽을 수 있는 크기로 그린다.
      final stops = _stops(storeLabelTextSizeExpression(latitude: _lat));
      expect(_evalStop(stops[20.0]!, fit.emMeters), kStoreLabelMinPx);
    });
  });

  group('storeLabelBoxMeters', () {
    test('북향 사각형은 bearing 0에서 실제 가로/세로로 잰다', () {
      final box = storeLabelBoxMeters(
        polygon: _rectangle(widthM: 10, heightM: 4),
        bearingDeg: 0,
      );
      expect(box.widthM, closeTo(10, 0.05));
      expect(box.heightM, closeTo(4, 0.05));
    });

    test('bearing 90에서는 가로/세로가 뒤바뀐다', () {
      // 지도를 90° 돌리면 화면 가로였던 변이 세로가 된다. 이 뒤바뀜이 없으면
      // 건물 축에 맞춰 돌아간 실내 지도에서 박스를 통째로 잘못 잰다.
      final box = storeLabelBoxMeters(
        polygon: _rectangle(widthM: 10, heightM: 4),
        bearingDeg: 90,
      );
      expect(box.widthM, closeTo(4, 0.05));
      expect(box.heightM, closeTo(10, 0.05));
    });

    test('점이 모자라면 0을 돌려준다', () {
      final box = storeLabelBoxMeters(
        polygon: [const LatLng(_lat, 127.0)],
        bearingDeg: 0,
      );
      expect(box.widthM, 0);
      expect(box.heightM, 0);
    });
  });

  group('storeLabelTextSizeExpression', () {
    test('zoom이 1 오르면 글자도 2배가 된다', () {
      // 증상 1의 정의다. 예전 표현식은 z16~z20에서 매장이 16배 커질 때 글자는
      // 1.55배(9→14px)만 커져서, 확대할수록 글자가 상대적으로 작아 보였다.
      //
      // clamp를 풀고 본다. 기본 범위(9~16px)는 2배가 채 안 되므로 이웃한 두
      // zoom이 동시에 그 안에 들어올 수 없어, 걸어 둔 채로는 이 법칙을 볼 수 없다.
      final stops = _stops(
        storeLabelTextSizeExpression(latitude: _lat, minPx: 0, maxPx: 1e9),
      );
      final emMeters = 12.0 / _pixelsPerMeter(18);
      expect(_evalStop(stops[18.0]!, emMeters), closeTo(12.0, 1e-6));
      expect(_evalStop(stops[17.0]!, emMeters), closeTo(6.0, 1e-6));
      expect(_evalStop(stops[19.0]!, emMeters), closeTo(24.0, 1e-6));
    });

    test('모든 zoom stop이 하한과 상한 사이에 머문다', () {
      final stops = _stops(storeLabelTextSizeExpression(latitude: _lat));
      expect(stops.keys.toList()..sort(), [16, 17, 18, 19, 20, 21, 22]);
      for (final emMeters in [0.0, 0.05, 0.3, 1.8, 20.0]) {
        for (final entry in stops.entries) {
          final px = _evalStop(entry.value, emMeters);
          expect(px, greaterThanOrEqualTo(kStoreLabelMinPx));
          expect(px, lessThanOrEqualTo(kStoreLabelMaxPx));
        }
      }
    });

    test('하한과 상한이 양쪽 끝을 실제로 잘라 낸다', () {
      final stops = _stops(storeLabelTextSizeExpression(latitude: _lat));
      // 작은 매장이 읽을 수 없게 줄어드는 쪽과, 큰 매장이 도면을 삼키는 쪽을
      // 각각 참값으로 확인한다.
      final tooSmall = (kStoreLabelMinPx - 1) / _pixelsPerMeter(18);
      expect(
        _evalStop(stops[18.0]!, tooSmall),
        closeTo(kStoreLabelMinPx, 1e-6),
      );

      final tooBig = (kStoreLabelMaxPx + 1) / _pixelsPerMeter(18);
      expect(_evalStop(stops[18.0]!, tooBig), closeTo(kStoreLabelMaxPx, 1e-6));
    });

    test('위도가 다르면 픽셀 환산도 달라진다', () {
      // 환산 자체를 보는 테스트라 clamp를 푼다 — 걸어 두면 두 값이 나란히
      // 하한에 눌려 차이가 사라진다.
      final seoul = _stops(
        storeLabelTextSizeExpression(latitude: 37.5, minPx: 0, maxPx: 1e9),
      );
      final equator = _stops(
        storeLabelTextSizeExpression(latitude: 0, minPx: 0, maxPx: 1e9),
      );
      const emMeters = 0.5;
      // 같은 zoom에서 적도가 픽셀당 미터가 커서 글자는 더 작다.
      expect(
        _evalStop(equator[19.0]!, emMeters),
        lessThan(_evalStop(seoul[19.0]!, emMeters)),
      );
    });

    test('실제 매장 크기에서 예전 고정값보다 넘침이 줄어든다', () {
      // 5m 매장 + 4글자 이름. 예전 표현식은 z19에서 12.75px 한 줄 = 약 51px인데
      // 박스는 42px이라 넘쳤다. 지금은 접힌 두 줄이 박스 안에 들어가야 한다.
      const boxM = 5.0;
      final fit = fitStoreLabel(
        name: '루이비통',
        boxWidthM: boxM,
        boxHeightM: boxM,
      );
      final stops = _stops(storeLabelTextSizeExpression(latitude: _lat));

      final pixelsPerMeter = _pixelsPerMeter(19);
      final boxPx = boxM * pixelsPerMeter;
      final sizePx = _evalStop(stops[19.0]!, fit.emMeters);

      expect(sizePx * fit.maxWidthEm, lessThan(boxPx));
      expect(sizePx * fit.lines * kStoreLabelLineHeightEm, lessThan(boxPx));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/map/style/label_style.dart';
import 'package:navigation_client/screens/outdoor_map/layers/indoor_overlay_layers.dart';
import 'package:navigation_client/map/style/floor_facility_style.dart';
import 'package:navigation_client/map/label/store_label_fit.dart';

/// 라벨 스타일에서 지키려는 것은 **값 자체가 아니라 값이 하나라는 사실**이다.
/// 색·헤일로가 레이어마다 갈라져 있던 것이 애초의 문제였으므로, 숫자를 잠그는
/// 대신 "여러 레이어가 같은 상수를 본다"를 잠근다.
void main() {
  group('라벨 타이포그래피 단일 출처', () {
    test('야외 매장명 라벨이 공용 색·헤일로를 쓴다', () {
      final props = indoorStoresLabelProps(const [1.0], null, 1);

      expect(props.textColor, mapLabelStoreColor);
      expect(props.textHaloColor, mapLabelHaloColor);
      expect(props.textHaloWidth, mapLabelHaloWidth);
    });

    test('야외 편의시설 라벨이 공용 보조 스타일을 쓴다', () {
      final props = indoorFacilityLabelProps(const [1.0], null);

      expect(props.textColor, mapLabelFacilityColor);
      expect(props.textHaloColor, mapLabelHaloColor);
      expect(props.textHaloWidth, mapLabelHaloWidth);
      expect(props.textSize, mapLabelFixedTextSize);
      expect(props.textMaxWidth, mapLabelFixedMaxWidth);
      expect(props.textOffset, mapLabelBelowIconOffset);
    });

    test('매장명과 편의시설 이름은 서로 다른 단계다', () {
      // 둘이 같아지면 "아이콘이 주 신호"라는 위계가 사라진다. 색 값 자체가
      // 아니라 **다르다**는 사실만 잠근다.
      expect(mapLabelFacilityColor, isNot(mapLabelStoreColor));
    });
  });

  group('매장명 글자 크기 폭', () {
    test('고정 라벨 크기가 매장명 크기 범위 안에 든다', () {
      // 편의시설 이름이 매장명보다 크거나 작기만 하면 도면이 두 덩어리로
      // 갈라져 보인다. 범위 안에 있어야 한 시스템으로 읽힌다.
      expect(mapLabelFixedTextSize, greaterThanOrEqualTo(kStoreLabelMinPx));
      expect(mapLabelFixedTextSize, lessThanOrEqualTo(kStoreLabelMaxPx));
    });

    test('한 화면 안 글자 크기 차이가 1.6배를 넘지 않는다', () {
      // 9~18(2.0배)이 "글자가 제멋대로다"로 읽힌 것이 이 값을 좁힌 이유다
      // ([kStoreLabelMaxPx] 주석). 숫자를 되돌리면 여기서 걸린다.
      expect(kStoreLabelMaxPx / kStoreLabelMinPx, lessThanOrEqualTo(1.6));
    });
  });

  // 한 화면에서 이름이 붙는 자리가 하나여야 눈이 규칙을 세운다. 예전에는
  // 매장명만 아이콘 좌/우로 뒤집히고(variable-anchor) 시설명은 아래로 고정이라,
  // 같은 도면에 두 규칙이 섞여 있었다.
  group('이름은 항상 아이콘 아래', () {
    test('야외 매장명이 아이콘 아래에 고정된다', () {
      final props = indoorStoresLabelProps(const [1.0], null, 1);

      expect(props.textAnchor, 'top');
      expect(props.textOffset, mapLabelBelowIconOffset);
      // 뒤집기가 남아 있으면 앵커 고정이 무효가 된다.
      expect(props.textVariableAnchor, isNull);
    });

    test('야외 편의시설명과 같은 오프셋을 쓴다', () {
      final store = indoorStoresLabelProps(const [1.0], null, 1);
      final facility = indoorFacilityLabelProps(const [1.0], null);

      expect(store.textOffset, facility.textOffset);
    });
  });

  group('마커는 한 크기', () {
    // "매장 아이콘을 화장실만큼 해 달라"는 피드백이다. 실내 화면은 이미
    // [kIndoorMarkerLogicalPx] 하나로 합쳤는데 지도 오버레이만 자기 값을 들고
    // 있었다 — 매장 배지 0.16~0.21, 시설 0.33~0.45로 두 배 차이였다.
    const dpr = 3.5;

    test('매장 배지와 시설 아이콘이 같은 크기다', () {
      final store = indoorStoresLabelProps(const [1.0], null, dpr);
      final facility = indoorFacilityIconProps(const [1.0], dpr);
      final poi = indoorPoiIconProps(const [1.0], dpr);

      expect(store.iconSize, facility.iconSize);
      expect(store.iconSize, poi.iconSize);
    });

    test('아이콘 크기는 화면 배율로 환산한다', () {
      // `icon-size`는 비트맵의 물리 px에 곱해지고 `text-size`는 논리 px이라,
      // 배율을 안 곱하면 고밀도 화면에서 아이콘만 배율만큼 작아진다. 이 저장소가
      // 실제로 겪은 버그다 — 배율 3.5에서 배지가 4.4 논리 px으로 떴다.
      final low = indoorStoresLabelProps(const [1.0], null, 1).iconSize;
      final high = indoorStoresLabelProps(const [1.0], null, dpr).iconSize;

      expect(high, greaterThan(low as double));
      expect(high, indoorMarkerIconSize(dpr));
    });
  });

  group('이름은 아이콘에 붙어 있다', () {
    test('아이콘을 덮지도, 떨어져 나가지도 않는다', () {
      // 오프셋은 **폴리곤 중심**에서 재므로 눈에 보이는 빈 간격은
      // `오프셋 - 아이콘 반지름`이다. 예전 값 1.6em은 아이콘이 배율 환산 없이
      // 4~6 논리 px으로 그려지던 시절의 값이라 간격이 15px까지 벌어졌고,
      // "이름이 어느 아이콘 것인지 모르겠다"가 실제 피드백이었다.
      final gap =
          mapLabelBelowIconOffset[1] * mapLabelFixedTextSize -
          kIndoorMarkerLogicalPx / 2;

      expect(gap, greaterThan(0), reason: '0 이하면 이름이 아이콘 위에 겹쳐 찍힌다');
      expect(gap, lessThan(6), reason: '6px를 넘으면 이름이 아이콘에서 떨어져 나온 것으로 읽힌다');
    });

    test('가장 작은 글자에서도 헤일로가 아이콘을 파고들지 않는다', () {
      // 오프셋은 em인데 아이콘은 고정 px이라 **글자가 작을수록 간격이 좁아진다**.
      // 실내 매장명은 폴리곤에 맞춰 줄어들므로 가장 빡빡한 쪽이 하한을 정한다.
      // 헤일로 두께보다 좁아지면 글자 외곽선이 아이콘 흰 테두리를 파고든다.
      final gap =
          mapLabelBelowIconOffset[1] * kStoreLabelMinPx -
          kIndoorMarkerLogicalPx / 2;

      // 지금 값은 이 하한과 **정확히 같다**(0.6 × 12 − 6 = 1.2). 여유가 0이므로
      // 오프셋을 더 줄이거나 아이콘을 키우면 이 테스트가 바로 깨진다 — 그게
      // 이 테스트를 둔 이유다. 1e-9는 double 곱셈 오차만 흡수한다.
      expect(gap, greaterThanOrEqualTo(mapLabelHaloWidth - 1e-9));
    });
  });
}

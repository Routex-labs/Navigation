import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/core/map_label_style.dart';
import 'package:navigation_client/screens/outdoor_map/indoor_overlay_layers.dart';
import 'package:navigation_client/widgets/store_label_fit.dart';

/// 라벨 스타일에서 지키려는 것은 **값 자체가 아니라 값이 하나라는 사실**이다.
/// 색·헤일로가 레이어마다 갈라져 있던 것이 애초의 문제였으므로, 숫자를 잠그는
/// 대신 "여러 레이어가 같은 상수를 본다"를 잠근다.
void main() {
  group('라벨 타이포그래피 단일 출처', () {
    test('야외 매장명 라벨이 공용 색·헤일로를 쓴다', () {
      final props = indoorStoresLabelProps(const [1.0], null);

      expect(props.textColor, mapLabelStoreColor);
      expect(props.textHaloColor, mapLabelHaloColor);
      expect(props.textHaloWidth, mapLabelHaloWidth);
    });

    test('야외 편의시설 라벨이 공용 보조 스타일을 쓴다', () {
      final props = indoorFacilityLabelProps(const [1.0], null);

      expect(props.textColor, mapLabelFacilityColor);
      expect(props.textHaloColor, mapLabelHaloColor);
      expect(props.textHaloWidth, mapLabelHaloWidth);
      expect(props.textSize, mapLabelFacilityTextSize);
      expect(props.textMaxWidth, mapLabelFacilityMaxWidth);
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
      expect(mapLabelFacilityTextSize, greaterThanOrEqualTo(kStoreLabelMinPx));
      expect(mapLabelFacilityTextSize, lessThanOrEqualTo(kStoreLabelMaxPx));
    });

    test('한 화면 안 글자 크기 차이가 1.6배를 넘지 않는다', () {
      // 9~18(2.0배)이 "글자가 제멋대로다"로 읽힌 것이 이 값을 좁힌 이유다
      // ([kStoreLabelMaxPx] 주석). 숫자를 되돌리면 여기서 걸린다.
      expect(kStoreLabelMaxPx / kStoreLabelMinPx, lessThanOrEqualTo(1.6));
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/outdoor_map/indoor_entry_zoom.dart';

/// 확대로 실내에 들어가는 판정.
///
/// 한 번 걷어냈다가 되살린 기능이라 경계가 중요하다. 걷어냈던 이유는 "건너편에서
/// 건물을 훑던 사용자가 영문 모르고 실내 화면에 들어와 있었다"였고, 그건 위치
/// 조건(화면 중심이 건물 위)으로 막는다 — 여기서는 zoom 쪽만 지킨다.
void main() {
  test('도면이 완전히 진해지는 zoom부터 들어간다', () {
    expect(shouldEnterIndoorForZoom(indoorEntryZoomThreshold), isTrue);
    expect(shouldEnterIndoorForZoom(indoorEntryZoomThreshold + 0.5), isTrue);
    expect(shouldEnterIndoorForZoom(indoorEntryZoomThreshold - 0.01), isFalse);
  });

  test('진입 임계값은 도면이 다 보이는 지점과 같다', () {
    // 이보다 낮으면 반쯤 흐린 도면 위에서 실내에 들어가 있게 된다.
    expect(indoorEntryZoomThreshold, indoorFocusZoom);
    expect(indoorEntryZoomThreshold, indoorOverlayFadeInEndZoom);
  });

  test('진입과 이탈 임계값 사이에 넉넉한 간격이 있다', () {
    // 붙어 있으면 손가락이 한 번 움찔하는 것만으로 진입과 이탈이 번갈아 난다.
    expect(indoorEntryZoomThreshold - indoorExitZoomThreshold, greaterThan(1));
  });

  test('진입과 이탈 구간은 겹치지 않는다', () {
    // 진입하자마자 이탈 조건이 참이면 오버레이가 켜졌다 꺼지기를 반복한다.
    expect(shouldExitIndoorForZoom(indoorEntryZoomThreshold), isFalse);
    // 반대로 이탈 직후 zoom에서 곧바로 다시 들어가지도 않는다.
    expect(shouldEnterIndoorForZoom(indoorExitZoomThreshold - 0.01), isFalse);
  });
}

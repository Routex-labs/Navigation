import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/guidance/guidance_chrome.dart';

/// 이 판정의 유일한 불변식은 **접는 조건 == 종료 수단이 있는 조건** 이다.
/// chrome을 접으면 화면에 지도와 안내 카드만 남으므로, 카드에 종료 버튼이
/// 없는 상태에서 접으면 사용자가 빠져나갈 수단을 전부 잃는다. 아래 테스트는
/// 그 대응을 경우별로 못 박는다.
void main() {
  group('안내 chrome 접기', () {
    test('실내 매장 목적지가 잡히면 접는다', () {
      // 실내 안내 카드는 목적지만 있으면 뜨고 늘 종료 버튼을 단다.
      expect(
        shouldFoldGuidanceChrome(
          hasUserDestination: false,
          hasIndoorRouteDestination: true,
          hasComputedRoute: true,
        ),
        isTrue,
      );
    });

    test('실내 목적지는 경로 계산이 아직이어도 접는다', () {
      // 실내 카드는 경로와 무관하게 뜨므로 이 순간에도 탈출구가 있다.
      expect(
        shouldFoldGuidanceChrome(
          hasUserDestination: false,
          hasIndoorRouteDestination: true,
          hasComputedRoute: false,
        ),
        isTrue,
      );
    });

    test('야외는 사용자가 고른 목적지의 경로가 그려진 뒤에 접는다', () {
      expect(
        shouldFoldGuidanceChrome(
          hasUserDestination: true,
          hasIndoorRouteDestination: false,
          hasComputedRoute: true,
        ),
        isTrue,
      );
    });

    test('야외 목적지만 있고 경로가 아직 없으면 접지 않는다', () {
      // 회귀 방지: showRouteTo가 목적지를 세팅하고 경로 API를 기다리는 구간이다.
      // 이때 야외 안내 카드는 경로가 없어 그려지지 않는다. 접어 버리면 카드도
      // 검색창도 하단 바도 없는 화면이 되고, GPS를 못 잡아 경로 계산이 실패하면
      // 그 상태가 그대로 남아 사용자가 갇힌다.
      expect(
        shouldFoldGuidanceChrome(
          hasUserDestination: true,
          hasIndoorRouteDestination: false,
          hasComputedRoute: false,
        ),
        isFalse,
      );
    });

    test('건물 입구까지 자동으로 그린 경로에서는 접지 않는다', () {
      // 목적지 없이 경로만 있는 상태다. 이 카드에는 종료 버튼이 없다 —
      // 사용자가 시작한 적이 없으니 끝낼 것도 없다는 기획이고, 그래서 chrome을
      // 남겨 둬야 검색·메뉴로 빠져나갈 수 있다.
      expect(
        shouldFoldGuidanceChrome(
          hasUserDestination: false,
          hasIndoorRouteDestination: false,
          hasComputedRoute: true,
        ),
        isFalse,
      );
    });

    test('아무것도 없으면 접지 않는다', () {
      expect(
        shouldFoldGuidanceChrome(
          hasUserDestination: false,
          hasIndoorRouteDestination: false,
          hasComputedRoute: false,
        ),
        isFalse,
      );
    });
  });
}

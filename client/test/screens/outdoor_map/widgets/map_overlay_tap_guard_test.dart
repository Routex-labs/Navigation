import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/screens/outdoor_map/widgets/map_overlay_tap_guard.dart';

void main() {
  test('길안내 종료 탭은 지도에 전달되지 않고 다음 별도 탭은 정상 처리된다', () {
    final guard = MapOverlayTapGuard();
    const closeButtonPoint = Offset(300, 545);
    const nextStorePoint = Offset(160, 300);
    final pointerDownAt = DateTime(2026, 7, 30, 12);
    var clearCount = 0;
    var storeSelectionCount = 0;

    void closeRoute() {
      clearCount += 1;
      guard.retainPointerDown(closeButtonPoint, at: pointerDownAt);
    }

    void dispatchMapTap(Offset point) {
      if (!guard.consumeIfBlocked(
        point,
        now: pointerDownAt.add(const Duration(milliseconds: 20)),
      )) {
        storeSelectionCount += 1;
      }
    }

    closeRoute();
    dispatchMapTap(closeButtonPoint);

    expect(clearCount, 1);
    expect(storeSelectionCount, 0);

    dispatchMapTap(nextStorePoint);
    expect(clearCount, 1);
    expect(storeSelectionCount, 1);
  });

  test('첫 지도 탭이 반경 밖이면 차단하지 않고 guard를 해제한다', () {
    final guard = MapOverlayTapGuard();
    const closeButtonPoint = Offset(300, 545);
    const farPoint = Offset(160, 300);
    final pointerDownAt = DateTime(2026, 7, 30, 12);

    guard.retainPointerDown(closeButtonPoint, at: pointerDownAt);

    expect(
      guard.consumeIfBlocked(
        farPoint,
        now: pointerDownAt.add(const Duration(milliseconds: 20)),
      ),
      isFalse,
    );
    expect(
      guard.consumeIfBlocked(
        closeButtonPoint,
        now: pointerDownAt.add(const Duration(milliseconds: 30)),
      ),
      isFalse,
    );
  });

  test('보존 시간이 지난 지도 탭은 차단하지 않는다', () {
    final guard = MapOverlayTapGuard();
    const closeButtonPoint = Offset(300, 545);
    final pointerDownAt = DateTime(2026, 7, 30, 12);

    guard.retainPointerDown(closeButtonPoint, at: pointerDownAt);

    expect(
      guard.consumeIfBlocked(
        closeButtonPoint,
        now: pointerDownAt.add(const Duration(milliseconds: 701)),
      ),
      isFalse,
    );
  });

  test('근접 지도 탭은 한 번만 차단하고 같은 위치의 다음 탭은 통과시킨다', () {
    final guard = MapOverlayTapGuard();
    const closeButtonPoint = Offset(300, 545);
    final pointerDownAt = DateTime(2026, 7, 30, 12);

    guard.retainPointerDown(closeButtonPoint, at: pointerDownAt);

    expect(
      guard.consumeIfBlocked(
        closeButtonPoint,
        now: pointerDownAt.add(const Duration(milliseconds: 20)),
      ),
      isTrue,
    );
    expect(
      guard.consumeIfBlocked(
        closeButtonPoint,
        now: pointerDownAt.add(const Duration(milliseconds: 30)),
      ),
      isFalse,
    );
  });
}

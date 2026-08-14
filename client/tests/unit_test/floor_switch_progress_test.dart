import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/core/floor_switch_progress.dart';

/// 층 전환은 별도 상태 UI나 빠른 전환 예외 없이 항상 같은 교차 페이드 정책을
/// 사용한다. MapLibre 레이어 자체는 컨트롤러가 필요한 통합 영역이므로 여기서는
/// 시간 정책이 프레임 단위로 정확히 나뉘는지만 고정한다.
void main() {
  group('층 교차 페이드 타이밍', () {
    test('사람 조작 페이드는 단계로 정확히 나뉜다', () {
      expect(floorSwitchCrossfadeSteps, greaterThan(1));
      expect(
        floorSwitchCrossfadeDuration.inMilliseconds % floorSwitchCrossfadeSteps,
        0,
      );
    });

    test('자동 층 전환은 사람 조작보다 천천히 인지시킨다', () {
      expect(
        floorSwitchGuidedCrossfadeDuration,
        greaterThan(floorSwitchCrossfadeDuration),
      );
    });

    test('외곽선은 중간에 숨긴 뒤 새 모양으로 다시 나타난다', () {
      expect(floorBoundaryCrossfadeFactor(0), 1);
      expect(floorBoundaryCrossfadeFactor(0.25), 0.5);
      expect(floorBoundaryCrossfadeFactor(0.5), 0);
      expect(floorBoundaryCrossfadeFactor(0.75), 0.5);
      expect(floorBoundaryCrossfadeFactor(1), 1);
    });

    test('외곽선 계수는 잘못된 진행률에도 0에서 1 사이를 지킨다', () {
      expect(floorBoundaryCrossfadeFactor(-1), 1);
      expect(floorBoundaryCrossfadeFactor(2), 1);
    });

    test('타일 준비 확인은 대기 상한 전에 여러 번 수행된다', () {
      expect(
        floorSwitchTilesReadyTimeout.inMilliseconds ~/
            floorSwitchTilesPollInterval.inMilliseconds,
        greaterThan(2),
      );
    });
  });
}

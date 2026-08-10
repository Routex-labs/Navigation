/// 층 전환이 화면에 그려지기까지의 구간 계측.
///
/// 층 전환은 여러 위젯에 걸쳐 **직렬로** 이어진다 — 층 선택 → 도면 JSON 왕복 →
/// 지도 위젯 재생성 → 스타일 로드 → 아이콘·레이어 등록 → 타일이 그려짐. 어느
/// 구간이 실제로 오래 걸리는지는 코드만 봐서는 정할 수 없고, 에뮬레이터도 답이
/// 아니다(네이티브 지도 생성과 타일 왕복이 실기기와 자릿수로 다르다).
///
/// 그래서 실기기 릴리스 빌드에서 logcat으로 찍는다. 계측은 기본으로 **꺼져
/// 있고**, 재려는 빌드에서만 켠다:
///
/// ```
/// flutter build apk --release --dart-define-from-file=config.local.json \
///   --dart-define=FLOOR_TIMING=true
/// adb logcat -s flutter | findstr floor-timing
/// ```
///
/// 상수 게이트라 꺼진 빌드에서는 호출부까지 통째로 트리셰이킹된다 — 계측을
/// 남겨 둬도 배포 빌드에 로그가 새지 않는다.
library;

const bool kFloorSwitchTimingEnabled = bool.fromEnvironment('FLOOR_TIMING');

/// 한 번의 층 전환을 [begin]부터 [mark]까지 누적 ms로 찍는다.
///
/// 전역 static인 이유는 구간이 위젯 경계를 넘기 때문이다 — 시작은 실내 화면
/// (`_selectFloor`), 끝은 지도 위젯(`FloorPlanView`)이라 한 객체에 담아 넘길
/// 자리가 없다. 계측 전용 도구라 이 정도 결합은 감수한다.
class FloorSwitchTiming {
  FloorSwitchTiming._();

  static final Stopwatch _stopwatch = Stopwatch();
  static String _floor = '';

  /// 이번 전환에서 이미 찍은 구간. `idle`처럼 여러 번 불리는 콜백을 **처음
  /// 한 번만** 남긴다 — 카메라가 멈출 때마다 찍히면 "그려지기까지"가 아니라
  /// 그냥 로그 홍수가 된다.
  static final Set<String> _marked = <String>{};

  static void begin(String floor) {
    if (!kFloorSwitchTimingEnabled) return;
    _floor = floor;
    _marked.clear();
    _stopwatch
      ..reset()
      ..start();
    // ignore: avoid_print — logcat으로 내보내는 게 이 도구의 목적이다.
    print('[floor-timing] floor=$floor phase=select t=0ms');
  }

  /// 구간이 아니라 값을 남긴다(타일 URL 등). 같은 접두어로 찍어서 logcat 필터
  /// 하나로 함께 걸린다.
  static void note(String message) {
    if (!kFloorSwitchTimingEnabled) return;
    // ignore: avoid_print
    print('[floor-timing] $message');
  }

  static void mark(String phase) {
    if (!kFloorSwitchTimingEnabled) return;
    if (!_stopwatch.isRunning) return;
    if (!_marked.add(phase)) return;
    // ignore: avoid_print
    print(
      '[floor-timing] floor=$_floor phase=$phase '
      't=${_stopwatch.elapsedMilliseconds}ms',
    );
  }
}

/// 층 도면 교체의 교차 페이드 타이밍 정책.
///
/// 새 층을 고르면 기존 층은 새 벡터 타일이 실제로 준비될 때까지 그대로 둔다.
/// 준비된 순간부터 기존 층은 사라지고 새 층은 나타난다. 별도 로딩 카드나 흰
/// 덮개를 쓰지 않으므로, 네트워크가 느려도 화면이 번쩍이거나 빈 지도를 보이지
/// 않는다.
library;

/// 사람이 층 선택기를 눌렀을 때의 교차 페이드 시간.
///
/// 카메라 재정렬(500ms)과 겹쳐 하나의 전환으로 읽히면서도, 층을 연속해서
/// 훑을 때 잔상이 길게 끌리지 않는 범위다.
const floorSwitchCrossfadeDuration = Duration(milliseconds: 320);

/// 안내 중 자동 층 전환은 사용자가 직접 누른 전환보다 조금 더 천천히 보여 준다.
/// 요청하지 않은 화면 변화라 층이 바뀌었다는 사실을 알아챌 시간이 필요하다.
const floorSwitchGuidedCrossfadeDuration = Duration(milliseconds: 520);

/// MapLibre Flutter 바인딩은 paint transition을 직접 설정할 수 없어, 완성된
/// 레이어 속성을 단계적으로 교체한다. 8단계는 320ms 전환에서 약 40ms 간격이다.
/// 더 늘리면 매 프레임 18개(이전·새 층 각 9개) 플랫폼 호출이 밀려 오히려
/// 프레임이 뭉치므로 이 값을 상한으로 둔다.
const floorSwitchCrossfadeSteps = 8;

/// 단일 GeoJSON 소스를 쓰는 층 외곽선·scrim hole의 전환 계수.
///
/// 이전·새 지오메트리를 동시에 들고 있을 수 없으므로 전반부에는 1→0으로
/// 이전 경계를 숨기고, 완전히 투명한 중간에 좌표를 바꾼 뒤 후반부에 0→1로
/// 새 경계를 드러낸다. 범위 밖 입력은 비동기 프레임 오차에 안전하게 자른다.
double floorBoundaryCrossfadeFactor(double progress) {
  final p = progress.clamp(0.0, 1.0).toDouble();
  return (p * 2 - 1).abs();
}

/// 새 소스의 실제 타일 도착 여부를 확인하는 주기.
const floorSwitchTilesPollInterval = Duration(milliseconds: 120);

/// 화면 밖이거나 네트워크가 끊겨 feature가 영영 잡히지 않을 때의 대기 상한.
/// 상한 뒤에도 이전 층과 새 층은 즉시 교체하지 않고 동일한 페이드를 거친다.
const floorSwitchTilesReadyTimeout = Duration(seconds: 12);

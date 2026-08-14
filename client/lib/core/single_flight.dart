/// 같은 작업이 **겹쳐 도는 것**을 막는다. 이미 돌고 있으면 새 요청을 버린다.
///
/// 실기기 로그에서 같은 대중교통 조회가 2~3번 연달아 나가 API 쿼터를 배로
/// 태우던 것을 막는다.
///
/// 큐가 아니라 **버리는** 쪽이다 — 겹친 요청은 어차피 같은 답을 받아 온다.
class SingleFlight {
  bool _busy = false;

  /// 지금 작업이 돌고 있는지.
  bool get isBusy => _busy;

  /// [task]를 실행한다. 이미 돌고 있으면 실행하지 않고 [onDuplicate]만 부른다.
  ///
  /// **[task]가 예외를 던져도 잠금은 풀린다.** 여기서 새면 그 뒤로 이 작업이
  /// 영영 실행되지 않는데, 화면에는 아무 반응이 없어 원인을 찾기가 가장 어렵다.
  /// 예외는 삼키지 않고 그대로 올려 보낸다 — 잠금 관리가 오류 처리까지 대신하면
  /// 호출부가 실패를 알 방법이 없다.
  Future<void> run(
    Future<void> Function() task, {
    void Function()? onDuplicate,
  }) async {
    if (_busy) {
      onDuplicate?.call();
      return;
    }
    _busy = true;
    try {
      await task();
    } finally {
      _busy = false;
    }
  }
}

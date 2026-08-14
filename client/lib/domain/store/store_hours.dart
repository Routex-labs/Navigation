/// 요일별 영업시간 규칙에서 "지금 영업 중인가"를 계산한다.
///
/// **판정 문자열을 저장하지 않는 이유가 이 파일의 존재 이유다.** 서버가 "영업 중"을
/// 내려보내면 그 값은 응답을 만든 순간부터 틀리기 시작하고, 상세 응답에는 ETag
/// 캐시까지 걸려 있어 더 오래 살아남는다. 서버는 규칙만 주고 판정은 매번 여기서 한다
/// (설계 9-1 · 지도·상세 UI 개선 계획 「보류 항목」 B안).
///
/// [DateTime.now]를 함수 안에서 부르지 않고 인자로 받는다. 시간에 의존하는 계산을
/// 함수 안에서 읽으면 테스트가 시각에 따라 통과했다 실패했다 한다.
///
/// 구현 전에 정한 검증 기준 17건(개점·폐점 정각, 브레이크 타임, 자정 넘김, 예외
/// 휴점·단축, 낡은 데이터, 다른 시간대 기기 …)은 표로 먼저 쓰고 그대로
/// `test/domain/store_hours_test.dart`로 옮겼다. **그 테스트가 이 계산의 명세다.**
library;

import '../../models/place_detail.dart';

/// 요일 키와 순서. 서버(`app/repositories/place_details.WEEKDAY_KEYS`)와 같은
/// 순서를 쓴다 — 전선 계약이라 양쪽 코드에 나란히 두고 스키마 파일에는 베끼지 않는다.
const kStoreHoursWeekdayKeys = <String>[
  'mon',
  'tue',
  'wed',
  'thu',
  'fri',
  'sat',
  'sun',
];

/// 확인일이 이만큼 지나면 "지금 영업 중" 판정을 거둔다.
///
/// **90일(약 한 분기)로 잡은 근거.**
/// 영업시간이 바뀌는 사건은 백화점 영업시간 조정·시즌 연장영업·리뉴얼처럼 대체로
/// 분기 단위로 온다. 180일로 두면 여름 연장영업에서 겨울 단축영업으로 넘어가는
/// 변화를 통째로 한 번 놓치고, 30일로 두면 539건을 매달 다시 확인해야 해서 규칙이
/// 지켜지지 않는다 — 지켜지지 않는 임계값은 임계값이 아니다. 분기에 한 번은 다시
/// 본다는 운영 주기가 이 데이터에서 유일하게 현실적인 선이라 그 값을 쓴다.
///
/// **넘겼을 때 요일 표까지 지우지는 않는다.** 요일 규칙은 낡아도 대체로 맞고, 통째로
/// 지우면 "정보가 없는 앱"으로 읽힌다(설계 F1). 거두는 것은 **지금 시각 판정**뿐이다 —
/// 틀렸을 때 사용자를 헛걸음하게 만드는 것이 정확히 그 한 줄이기 때문이다.
///
/// 시드에서 만료로 잡지 않는 이유도 같다. 데이터가 그대로인 날 CI가 죽는 대신,
/// 화면이 스스로 낮춘다.
const kStoreHoursStaleAfter = Duration(days: 90);

/// 지금 영업 중인지.
enum StoreOpenState {
  open,
  closed,

  /// 판정하지 않는다. 확인일이 [kStoreHoursStaleAfter]를 넘겼거나 규칙을 읽을 수
  /// 없는 경우다. "영업 종료"로 떨어뜨리지 않는 이유는 그것도 하나의 주장이기
  /// 때문이다 — 모르는 것을 닫혔다고 말하면 열려 있는 매장을 돌려보낸다.
  unknown,
}

/// [computeStoreHoursStatus]의 결과.
class StoreHoursStatus {
  const StoreHoursStatus({
    required this.state,
    required this.nextChangeAt,
    required this.isStale,
  });

  final StoreOpenState state;

  /// 다음으로 상태가 바뀌는 **매장 현지 벽시계** 시각. 영업 중이면 닫는 시각,
  /// 닫혀 있으면 다음에 여는 시각이다.
  ///
  /// null인 경우가 둘이다 — 종일 영업이라 바뀌지 않거나, 앞으로 8일 안에 여는 날이
  /// 없는 경우(전 요일 휴무). 둘 다 "다음 전환을 말할 수 없다"는 점에서 같다.
  final DateTime? nextChangeAt;

  /// 확인일이 임계값을 넘겼다. 판정은 거두되 요일 표는 그린다.
  final bool isStale;
}

/// 하루치 영업시간. 화면이 요일 표를 그릴 때 쓴다.
class StoreHoursDay {
  const StoreHoursDay({
    required this.date,
    required this.intervals,
    required this.isException,
    required this.note,
  });

  /// 매장 현지 날짜(시각은 00:00).
  final DateTime date;

  /// 그날의 영업 구간. 비어 있으면 휴무다.
  final List<StoreHoursInterval> intervals;

  /// 요일 규칙이 아니라 예외가 적용된 날.
  final bool isException;

  /// 예외의 사유("백화점 정기 휴점" 등).
  final String? note;
}

/// 기기 시각을 **매장 현지 벽시계**로 옮긴다.
///
/// 반환값은 `isUtc`가 true인 [DateTime]이지만 뜻은 UTC가 아니라 매장 벽시계다.
/// 그렇게 두는 이유는 이 뒤의 모든 날짜 계산이 정확해지기 때문이다 — 기기가 서머타임을
/// 쓰는 지역에 있으면 로컬 [DateTime]의 하루 더하기가 한 시간씩 어긋나는데, UTC 축
/// 위에서는 그런 일이 없다. 한국은 서머타임이 없어 고정 오프셋으로 정확하다.
DateTime storeLocalTime(HoursSection hours, DateTime now) =>
    now.toUtc().add(Duration(minutes: hours.utcOffsetMinutes));

/// 지금 영업 중인지 계산한다. [now]는 기기 시각(어느 시간대든 상관없다).
StoreHoursStatus computeStoreHoursStatus(HoursSection hours, DateTime now) {
  final local = storeLocalTime(hours, now);

  if (isStoreHoursStale(hours, now)) {
    return const StoreHoursStatus(
      state: StoreOpenState.unknown,
      nextChangeAt: null,
      isStale: true,
    );
  }

  // 어제부터 보는 이유는 **자정을 넘긴 구간** 때문이다. 새벽 1시의 "영업 중"은
  // 오늘이 아니라 어제 22:00에 시작한 구간이 만든다.
  final today = _dateOf(local);
  final from = today.subtract(const Duration(days: 1));
  const windowDays = 9;
  final windowEnd = from.add(const Duration(days: windowDays));
  final spans = _absoluteSpans(hours, from, windowDays);

  for (final span in spans) {
    // 개점 시각은 포함하고 폐점 시각은 제외한다. 20:00 폐점인 매장 앞에 20:00에
    // 서 있는 사람에게 "영업 중"이라고 말하면 그 길이 헛걸음이 된다.
    if (!local.isBefore(span.$1) && local.isBefore(span.$2)) {
      return StoreHoursStatus(
        state: StoreOpenState.open,
        // 창 끝까지 이어지는 구간은 종일 영업이라 닫는 시각을 말할 수 없다.
        // 창의 마지막 날을 "닫는 시각"이라고 적으면 그건 계산 창의 크기일 뿐
        // 매장에 대한 사실이 아니다.
        nextChangeAt: span.$2.isBefore(windowEnd) ? span.$2 : null,
        isStale: false,
      );
    }
  }

  for (final span in spans) {
    if (span.$1.isAfter(local)) {
      return StoreHoursStatus(
        state: StoreOpenState.closed,
        nextChangeAt: span.$1,
        isStale: false,
      );
    }
  }

  // 8일을 봐도 여는 날이 없다. 전 요일 휴무이거나 예외가 그 기간을 덮은 경우다.
  return const StoreHoursStatus(
    state: StoreOpenState.closed,
    nextChangeAt: null,
    isStale: false,
  );
}

/// 확인일이 [kStoreHoursStaleAfter]를 넘겼는가.
///
/// 확인일을 읽을 수 없으면 **낡은 것으로 본다.** 언제 확인한 값인지 모르는 상태와
/// 오래된 상태는 사용자에게 같은 뜻이고, 모르는 쪽을 믿어 주면 방어가 사라진다.
bool isStoreHoursStale(HoursSection hours, DateTime now) {
  final confirmed = _parseDate(hours.confirmedAt);
  if (confirmed == null) return true;
  final today = _dateOf(storeLocalTime(hours, now));
  return today.difference(confirmed) > kStoreHoursStaleAfter;
}

/// 오늘부터 [days]일치 영업시간. 화면의 요일 표가 쓴다.
List<StoreHoursDay> storeHoursWeek(
  HoursSection hours,
  DateTime now, {
  int days = 7,
}) {
  final today = _dateOf(storeLocalTime(hours, now));
  return [
    for (var offset = 0; offset < days; offset++)
      resolveStoreHoursDay(hours, today.add(Duration(days: offset))),
  ];
}

/// 그 날짜에 실제로 적용되는 규칙. 예외가 있으면 요일 규칙을 **통째로** 대체한다.
///
/// 부분 병합(예외의 구간을 요일 구간에 더하기)을 하지 않는 이유는, 휴점일을 적어 둔
/// 사람이 기대하는 것이 "그날은 이 규칙만"이기 때문이다. 섞으면 단축영업을 적었는데
/// 원래 시간이 함께 살아남는다.
StoreHoursDay resolveStoreHoursDay(HoursSection hours, DateTime date) {
  final key = _isoDate(date);
  for (final exception in hours.exceptions) {
    if (exception.date != key) continue;
    return StoreHoursDay(
      date: date,
      intervals: exception.closed ? const [] : exception.intervals,
      isException: true,
      note: exception.note,
    );
  }
  return StoreHoursDay(
    date: date,
    intervals: hours.weekly[weekdayKeyOf(date)] ?? const [],
    isException: false,
    note: null,
  );
}

/// [DateTime.weekday](월=1 … 일=7)를 서버 요일 키로 바꾼다.
String weekdayKeyOf(DateTime date) =>
    kStoreHoursWeekdayKeys[(date.weekday - 1) % 7];

/// "HH:MM" → 자정부터의 분. 형식이 아니면 null.
///
/// `24:00`은 하루의 끝(1440분)이다. 이 표기를 받아 주기 때문에 종일 영업이
/// `00:00`–`24:00`으로 적히고, "0분 영업"과 구분된다.
int? parseHoursMinute(String raw) {
  final matched = RegExp(r'^([01]\d|2[0-4]):([0-5]\d)$').firstMatch(raw);
  if (matched == null) return null;
  final hour = int.parse(matched.group(1)!);
  final minute = int.parse(matched.group(2)!);
  if (hour == 24 && minute != 0) return null;
  return hour * 60 + minute;
}

/// [from]부터 [days]일 동안의 영업 구간을 절대 시각 쌍으로 편다.
///
/// 자정을 넘긴 구간을 여기서 한 번에 편다. 이후 계산은 "지금이 이 구간 안인가"만
/// 보면 되고, 자정이라는 개념이 남지 않는다.
///
/// **맞닿은 구간은 하나로 잇는다.** 종일 영업(00:00–24:00)이 이어질 때 자정마다
/// "닫았다 연다"고 말하지 않기 위해서다.
List<(DateTime, DateTime)> _absoluteSpans(
  HoursSection hours,
  DateTime from,
  int days,
) {
  final spans = <(DateTime, DateTime)>[];
  for (var offset = 0; offset < days; offset++) {
    final date = from.add(Duration(days: offset));
    for (final interval in resolveStoreHoursDay(hours, date).intervals) {
      final open = parseHoursMinute(interval.open);
      final close = parseHoursMinute(interval.close);
      if (open == null || close == null || open == close) continue;
      final start = date.add(Duration(minutes: open));
      // close가 open보다 작으면 다음 날로 넘어간다. close가 1440(24:00)이면
      // 그대로 더해져 다음 날 00:00이 되므로 따로 분기하지 않는다.
      final end = close > open
          ? date.add(Duration(minutes: close))
          : date.add(Duration(days: 1, minutes: close));
      spans.add((start, end));
    }
  }

  spans.sort((a, b) => a.$1.compareTo(b.$1));

  final merged = <(DateTime, DateTime)>[];
  for (final span in spans) {
    if (merged.isNotEmpty && !span.$1.isAfter(merged.last.$2)) {
      final last = merged.removeLast();
      merged.add((last.$1, span.$2.isAfter(last.$2) ? span.$2 : last.$2));
    } else {
      merged.add(span);
    }
  }
  return merged;
}

DateTime _dateOf(DateTime moment) =>
    DateTime.utc(moment.year, moment.month, moment.day);

String _isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// "YYYY-MM-DD" → 매장 벽시계 축의 날짜. 형식이 아니면 null.
DateTime? _parseDate(String raw) {
  final matched = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
  if (matched == null) return null;
  final year = int.parse(matched.group(1)!);
  final month = int.parse(matched.group(2)!);
  final day = int.parse(matched.group(3)!);
  final parsed = DateTime.utc(year, month, day);
  // 2026-02-30은 3월 2일로 굴러간다. 굴러간 날짜를 그대로 쓰면 확인일이 조용히
  // 이틀 뒤가 된다.
  if (parsed.month != month || parsed.day != day) return null;
  return parsed;
}

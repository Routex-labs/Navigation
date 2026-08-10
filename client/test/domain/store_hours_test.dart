import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/store_hours.dart';
import 'package:navigation_client/models/place_detail.dart';

/// `lib/domain/store_hours.dart`의 표를 그대로 옮긴 것이다. 구현보다 먼저 정한
/// 기준이라 이 파일이 통과한다는 것과 화면이 맞다는 것이 같은 뜻이 되게 둔다.
///
/// 기준 규칙: 화~목 10:30–20:00 · 금~일 10:30–20:30 · 월 휴무.
/// 2026-08-11은 화요일이다.
void main() {
  HoursSection hours({
    Map<String, List<StoreHoursInterval>>? weekly,
    List<StoreHoursException> exceptions = const [],
    String confirmedAt = '2026-08-10',
    int utcOffsetMinutes = 540,
  }) => HoursSection(
    weekly: weekly ?? _starbucksWeekly,
    exceptions: exceptions,
    utcOffsetMinutes: utcOffsetMinutes,
    confirmedAt: confirmedAt,
  );

  /// 매장 현지(KST) 벽시계 시각을 기기 시각으로 바꿔 넘긴다. 판정 함수는 기기가
  /// 어느 시간대든 같은 답을 내야 하므로, 입력은 늘 UTC 순간으로 만든다.
  DateTime kst(int year, int month, int day, int hour, [int minute = 0]) =>
      DateTime.utc(year, month, day, hour, minute).subtract(
        const Duration(minutes: 540),
      );

  group('요일 규칙', () {
    test('영업 시간 안이면 영업 중이고 다음 전환은 닫는 시각이다', () {
      final status = computeStoreHoursStatus(hours(), kst(2026, 8, 11, 14));

      expect(status.state, StoreOpenState.open);
      expect(status.nextChangeAt, DateTime.utc(2026, 8, 11, 20));
      expect(status.isStale, isFalse);
    });

    test('개점 전이면 오늘 개점 시각을 가리킨다', () {
      final status = computeStoreHoursStatus(hours(), kst(2026, 8, 11, 9));

      expect(status.state, StoreOpenState.closed);
      expect(status.nextChangeAt, DateTime.utc(2026, 8, 11, 10, 30));
    });

    test('폐점 후면 다음 날 개점 시각을 가리킨다', () {
      final status = computeStoreHoursStatus(hours(), kst(2026, 8, 11, 21));

      expect(status.state, StoreOpenState.closed);
      expect(status.nextChangeAt, DateTime.utc(2026, 8, 12, 10, 30));
    });

    // 경계는 열림 쪽을 포함하고 닫힘 쪽을 제외한다. 20:00에 문을 닫는 매장 앞에
    // 20:00 정각에 서 있는 사람에게 "영업 중"이라고 말하면 그 길이 헛걸음이 된다.
    test('개점 정각은 영업 중이다', () {
      expect(
        computeStoreHoursStatus(hours(), kst(2026, 8, 11, 10, 30)).state,
        StoreOpenState.open,
      );
    });

    test('폐점 정각은 영업 종료다', () {
      expect(
        computeStoreHoursStatus(hours(), kst(2026, 8, 11, 20)).state,
        StoreOpenState.closed,
      );
    });

    // 요일 하나가 통째로 비어 있는 경우. 빈 배열은 "휴무"라는 명시다.
    test('휴무 요일에는 다음 영업일을 가리킨다', () {
      // 2026-08-10은 월요일.
      final status = computeStoreHoursStatus(hours(), kst(2026, 8, 10, 12));

      expect(status.state, StoreOpenState.closed);
      expect(status.nextChangeAt, DateTime.utc(2026, 8, 11, 10, 30));
    });

    test('전 요일이 휴무면 다음 전환을 말하지 않는다', () {
      final status = computeStoreHoursStatus(
        hours(weekly: {for (final key in kStoreHoursWeekdayKeys) key: const []}),
        kst(2026, 8, 11, 14),
      );

      expect(status.state, StoreOpenState.closed);
      expect(status.nextChangeAt, isNull);
    });
  });

  group('브레이크 타임', () {
    final withBreak = {
      for (final key in kStoreHoursWeekdayKeys)
        key: const [
          StoreHoursInterval(open: '11:00', close: '14:00'),
          StoreHoursInterval(open: '17:00', close: '21:00'),
        ],
    };

    test('브레이크 타임 안이면 영업 종료이고 다음 전환은 오후 개점이다', () {
      final status = computeStoreHoursStatus(
        hours(weekly: withBreak),
        kst(2026, 8, 11, 15),
      );

      expect(status.state, StoreOpenState.closed);
      expect(status.nextChangeAt, DateTime.utc(2026, 8, 11, 17));
    });

    test('브레이크 타임 전이면 영업 중이고 다음 전환은 브레이크 시작이다', () {
      final status = computeStoreHoursStatus(
        hours(weekly: withBreak),
        kst(2026, 8, 11, 12),
      );

      expect(status.state, StoreOpenState.open);
      expect(status.nextChangeAt, DateTime.utc(2026, 8, 11, 14));
    });
  });

  group('자정 넘김', () {
    final nightly = {
      for (final key in kStoreHoursWeekdayKeys)
        key: const [StoreHoursInterval(open: '22:00', close: '02:00')],
    };

    // 이 한 건이 자정 넘김의 핵심이다. 새벽 1시의 "영업 중"은 오늘이 아니라
    // **어제 22:00에 시작한 구간**이 만든다.
    test('새벽 1시는 어제 시작한 구간 덕분에 영업 중이다', () {
      final status = computeStoreHoursStatus(
        hours(weekly: nightly),
        kst(2026, 8, 12, 1),
      );

      expect(status.state, StoreOpenState.open);
      expect(status.nextChangeAt, DateTime.utc(2026, 8, 12, 2));
    });

    test('넘어간 구간이 끝나는 정각은 영업 종료다', () {
      final status = computeStoreHoursStatus(
        hours(weekly: nightly),
        kst(2026, 8, 12, 2),
      );

      expect(status.state, StoreOpenState.closed);
      expect(status.nextChangeAt, DateTime.utc(2026, 8, 12, 22));
    });

    test('자정 직전은 영업 중이고 다음 전환이 날짜를 넘는다', () {
      final status = computeStoreHoursStatus(
        hours(weekly: nightly),
        kst(2026, 8, 11, 23),
      );

      expect(status.state, StoreOpenState.open);
      expect(status.nextChangeAt, DateTime.utc(2026, 8, 12, 2));
    });
  });

  group('종일 영업', () {
    test('00:00–24:00이 이어지면 다음 전환을 말하지 않는다', () {
      final status = computeStoreHoursStatus(
        hours(
          weekly: {
            for (final key in kStoreHoursWeekdayKeys)
              key: const [StoreHoursInterval(open: '00:00', close: '24:00')],
          },
        ),
        kst(2026, 8, 11, 3),
      );

      expect(status.state, StoreOpenState.open);
      // 자정마다 "닫았다 연다"고 말하지 않는다.
      expect(status.nextChangeAt, isNull);
    });
  });

  group('예외 날짜', () {
    test('예외 휴점일이면 요일 규칙을 덮고 다음 영업일을 가리킨다', () {
      final status = computeStoreHoursStatus(
        hours(
          exceptions: const [
            StoreHoursException(
              date: '2026-08-12',
              closed: true,
              intervals: [],
              note: '백화점 정기 휴점',
            ),
          ],
        ),
        kst(2026, 8, 12, 12),
      );

      expect(status.state, StoreOpenState.closed);
      expect(status.nextChangeAt, DateTime.utc(2026, 8, 13, 10, 30));
    });

    // 요일 규칙만 봤다면 20:00까지 열려 있어 "영업 중"이 나왔을 시각이다.
    test('단축 영업 예외가 요일 규칙을 대체한다', () {
      final status = computeStoreHoursStatus(
        hours(
          exceptions: const [
            StoreHoursException(
              date: '2026-08-12',
              closed: false,
              intervals: [StoreHoursInterval(open: '10:30', close: '18:00')],
              note: null,
            ),
          ],
        ),
        kst(2026, 8, 12, 19),
      );

      expect(status.state, StoreOpenState.closed);
    });

    test('예외가 자정을 넘겨도 다음 날 새벽까지 이어진다', () {
      final status = computeStoreHoursStatus(
        hours(
          confirmedAt: '2026-12-30',
          exceptions: const [
            StoreHoursException(
              date: '2026-12-31',
              closed: false,
              intervals: [StoreHoursInterval(open: '10:00', close: '02:00')],
              note: '연말 연장 영업',
            ),
          ],
        ),
        kst(2027, 1, 1, 1),
      );

      expect(status.state, StoreOpenState.open);
      expect(status.nextChangeAt, DateTime.utc(2027, 1, 1, 2));
    });

    test('요일 표에 예외가 사유와 함께 실린다', () {
      final week = storeHoursWeek(
        hours(
          exceptions: const [
            StoreHoursException(
              date: '2026-08-12',
              closed: true,
              intervals: [],
              note: '백화점 정기 휴점',
            ),
          ],
        ),
        kst(2026, 8, 11, 12),
      );

      expect(week.first.date, DateTime.utc(2026, 8, 11));
      expect(week.length, 7);
      expect(week[1].isException, isTrue);
      expect(week[1].intervals, isEmpty);
      expect(week[1].note, '백화점 정기 휴점');
      expect(week[2].isException, isFalse);
    });
  });

  group('낡은 데이터', () {
    // 확인일이 임계값을 넘으면 판정을 거둔다. "영업 종료"로 떨어뜨리지 않는 이유는
    // 그것도 하나의 주장이기 때문이다 — 모르는 것을 닫혔다고 말하면 열려 있는
    // 매장을 돌려보낸다.
    test('임계값을 넘긴 확인일은 판정하지 않는다', () {
      final status = computeStoreHoursStatus(
        // 2026-08-11에서 91일 전.
        hours(confirmedAt: '2026-05-12'),
        kst(2026, 8, 11, 14),
      );

      expect(status.state, StoreOpenState.unknown);
      expect(status.isStale, isTrue);
      expect(status.nextChangeAt, isNull);
    });

    test('임계값 정각(90일)은 아직 낡지 않았다', () {
      final status = computeStoreHoursStatus(
        hours(confirmedAt: '2026-05-13'),
        kst(2026, 8, 11, 14),
      );

      expect(status.state, StoreOpenState.open);
      expect(status.isStale, isFalse);
    });

    test('확인일을 읽을 수 없으면 낡은 것으로 본다', () {
      final status = computeStoreHoursStatus(
        hours(confirmedAt: '2026년 5월'),
        kst(2026, 8, 11, 14),
      );

      expect(status.state, StoreOpenState.unknown);
      expect(status.isStale, isTrue);
    });

    // 판정만 거두고 요일 표는 남긴다. 통째로 지우면 "정보가 없는 앱"으로 읽힌다.
    test('낡아도 요일 표는 그대로 나온다', () {
      final week = storeHoursWeek(
        hours(confirmedAt: '2020-01-01'),
        kst(2026, 8, 11, 14),
      );

      expect(week.length, 7);
      expect(week.first.intervals, isNotEmpty);
    });
  });

  group('시간대', () {
    // 기기 시계가 다른 시간대에 있어도 매장 현지 시각으로 판정한다.
    test('UTC 기기 시각을 매장 현지 시각으로 옮겨 판정한다', () {
      // UTC 04:00 = KST 13:00 (화요일) → 영업 중
      final status = computeStoreHoursStatus(
        hours(),
        DateTime.utc(2026, 8, 11, 4),
      );

      expect(status.state, StoreOpenState.open);
    });

    test('같은 순간이라도 오프셋이 다르면 판정이 갈린다', () {
      // 같은 UTC 02:00을 KST(+540)는 11:00으로, 오프셋 0은 02:00으로 읽는다.
      // 오프셋이 계산에 실제로 쓰이지 않으면 두 답이 같아진다.
      final moment = DateTime.utc(2026, 8, 11, 2);

      expect(
        computeStoreHoursStatus(hours(), moment).state,
        StoreOpenState.open,
      );
      expect(
        computeStoreHoursStatus(hours(utcOffsetMinutes: 0), moment).state,
        StoreOpenState.closed,
      );
      expect(storeLocalTime(hours(), moment), DateTime.utc(2026, 8, 11, 11));
    });
  });

  group('시각 파싱', () {
    test('24:00은 하루의 끝이다', () {
      expect(parseHoursMinute('24:00'), 24 * 60);
    });

    test('24:30 같은 오타는 받지 않는다', () {
      expect(parseHoursMinute('24:30'), isNull);
    });

    test('형식이 아니면 null이다', () {
      expect(parseHoursMinute('10시 30분'), isNull);
      expect(parseHoursMinute('9:00'), isNull);
    });

    // 규칙을 읽을 수 없는 구간은 조용히 건너뛴다. 한 구간의 오타 때문에 그날
    // 전체가 사라지면 화면에는 아무 이상이 없어 보인다.
    test('읽을 수 없는 구간은 건너뛰고 나머지로 판정한다', () {
      final status = computeStoreHoursStatus(
        hours(
          weekly: {
            for (final key in kStoreHoursWeekdayKeys)
              key: const [
                StoreHoursInterval(open: '아침', close: '10:00'),
                StoreHoursInterval(open: '11:00', close: '20:00'),
              ],
          },
        ),
        kst(2026, 8, 11, 14),
      );

      expect(status.state, StoreOpenState.open);
      expect(status.nextChangeAt, DateTime.utc(2026, 8, 11, 20));
    });
  });

  group('요일 키', () {
    test('DateTime.weekday를 서버 키로 옮긴다', () {
      // 2026-08-10 월 … 2026-08-16 일
      expect(weekdayKeyOf(DateTime.utc(2026, 8, 10)), 'mon');
      expect(weekdayKeyOf(DateTime.utc(2026, 8, 16)), 'sun');
    });
  });
}

final _starbucksWeekly = <String, List<StoreHoursInterval>>{
  'mon': const [],
  'tue': const [StoreHoursInterval(open: '10:30', close: '20:00')],
  'wed': const [StoreHoursInterval(open: '10:30', close: '20:00')],
  'thu': const [StoreHoursInterval(open: '10:30', close: '20:00')],
  'fri': const [StoreHoursInterval(open: '10:30', close: '20:30')],
  'sat': const [StoreHoursInterval(open: '10:30', close: '20:30')],
  'sun': const [StoreHoursInterval(open: '10:30', close: '20:30')],
};

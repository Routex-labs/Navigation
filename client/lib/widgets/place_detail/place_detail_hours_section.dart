import 'package:flutter/material.dart';

import '../../domain/store_hours.dart';
import '../../models/place_detail.dart';
import '../../theme/app_theme.dart';

/// 요일별 영업시간. 맨 위에 "지금 영업 중인가" 한 줄, 그 아래 오늘 줄, 나머지
/// 요일은 접어 둔다.
///
/// **오늘 줄을 항상 펴 두는 이유.** 이 섹션을 보는 사람의 질문은 거의 언제나
/// "지금 갈 수 있나"이고, 그 다음이 "오늘 몇 시까지"다. 일곱 줄을 전부 접어 두면
/// 두 번째 질문에 답하려고 매번 펼쳐야 하고, 전부 펴 두면 다른 섹션이 화면 밖으로
/// 밀린다. 오늘 한 줄만 남기는 것이 그 사이다.
///
/// **판정 로직은 여기 없다.** `domain/store_hours.dart`의 순수 함수가 계산하고 이
/// 위젯은 그 결과를 문장으로 바꾸기만 한다. 시각 비교가 위젯에 있으면 테스트가
/// 화면을 띄워야만 돌고, 경계(폐점 정각·자정 넘김)를 하나씩 확인할 수 없다.
class PlaceHoursSection extends StatefulWidget {
  const PlaceHoursSection({super.key, required this.hours, required this.now});

  final HoursSection hours;

  /// 판정 기준 시각. 위젯이 [DateTime.now]를 직접 부르지 않고 받는 이유는
  /// 도메인 함수와 같다 — 시각에 의존하는 화면을 테스트로 고정할 수 있어야 한다.
  final DateTime now;

  @override
  State<PlaceHoursSection> createState() => _PlaceHoursSectionState();
}

class _PlaceHoursSectionState extends State<PlaceHoursSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final status = computeStoreHoursStatus(widget.hours, widget.now);
    final week = storeHoursWeek(widget.hours, widget.now);
    if (week.isEmpty) return const SizedBox.shrink();

    final today = week.first.date;
    final visibleCount = _expanded ? week.length : 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          expanded: _expanded,
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              // 별도 카드 없이도 손가락이 닿는 40px 안팎의 행을 만든다.
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.schedule_outlined,
                    size: 18,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StatusLine(status: status, today: today),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: const Icon(
                      Icons.expand_more,
                      size: 20,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            key: ValueKey(_expanded),
            children: [
              for (var index = 0; index < visibleCount; index++)
                _HoursRow(day: week[index], isToday: index == 0),
            ],
          ),
        ),
        // 최근 확인일은 영업시간을 읽는 데 필요한 정보가 아니라서 숨긴다. 오래된
        // 데이터일 때만 신뢰도 경고의 근거로 작게 남긴다.
        if (status.isStale) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              '${widget.hours.confirmedAt} 기준 · 영업시간이 달라졌을 수 있어요',
              style: const TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: AppColors.muted,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// "영업 중 · 20:00 종료" 한 줄.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status, required this.today});

  final StoreHoursStatus status;

  /// 매장 현지 오늘 날짜. "20:00 종료"와 "내일 10:30 영업 시작"을 가르는 기준이다.
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final headline = switch (status.state) {
      StoreOpenState.open => '영업 중',
      StoreOpenState.closed => '영업 종료',
      // 낡은 데이터에서는 판정 자체를 말하지 않는다. "영업 종료"로 떨어뜨리면
      // 열려 있는 매장을 돌려보내게 되고, 그게 이 섹션이 만들 수 있는 가장 비싼
      // 거짓말이다.
      StoreOpenState.unknown => '영업시간 정보가 오래됐어요',
    };
    final detail = _detailText(status, today);

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: headline,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: status.state == StoreOpenState.open
                  ? AppColors.primary
                  : AppColors.text,
            ),
          ),
          if (detail != null)
            TextSpan(
              text: ' · $detail',
              style: const TextStyle(color: AppColors.muted),
            ),
        ],
      ),
      style: const TextStyle(fontSize: 14, height: 1.35, color: AppColors.text),
    );
  }
}

/// "20:00 종료" / "내일 10:30 영업 시작". 말할 것이 없으면 null.
String? _detailText(StoreHoursStatus status, DateTime today) {
  final next = status.nextChangeAt;
  if (status.state == StoreOpenState.unknown) return null;
  if (next == null) {
    // 영업 중인데 바뀌는 시각이 없으면 종일 영업이고, 닫혀 있는데 없으면 앞으로
    // 여는 날이 없다는 뜻이다. 둘은 전혀 다른 말이라 같은 문구를 쓰지 않는다.
    return status.state == StoreOpenState.open ? '24시간 영업' : null;
  }
  final suffix = status.state == StoreOpenState.open ? '종료' : '영업 시작';
  return '${_whenText(next, today)} $suffix';
}

/// 전환 시각을 "20:00" / "내일 10:30" / "금 10:30"으로 적는다.
///
/// 날짜를 그대로 적지 않는 이유는 대부분의 전환이 오늘·내일 안에서 일어나기
/// 때문이다. "8월 12일 10:30"은 읽는 사람이 오늘 날짜를 떠올려야 뜻이 선다.
String _whenText(DateTime next, DateTime today) {
  final time =
      '${next.hour.toString().padLeft(2, '0')}:'
      '${next.minute.toString().padLeft(2, '0')}';
  final days = DateTime.utc(
    next.year,
    next.month,
    next.day,
  ).difference(today).inDays;
  return switch (days) {
    0 => time,
    1 => '내일 $time',
    _ => '${weekdayLabelOf(next)} $time',
  };
}

/// 요일 표의 한 줄. "화(8/11)    10:30 - 20:00".
class _HoursRow extends StatelessWidget {
  const _HoursRow({required this.day, required this.isToday});

  final StoreHoursDay day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final label =
        '${weekdayLabelOf(day.date)}(${day.date.month}/${day.date.day})';
    final value = day.intervals.isEmpty
        ? '휴무'
        : day.intervals.map((i) => '${i.open} - ${i.close}').join(' · ');

    return Padding(
      // 아이콘 폭(19)과 그 뒤 여백(10)만큼 들여 상태 줄과 왼쪽을 맞춘다.
      padding: const EdgeInsets.only(left: 28, top: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.35,
                fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                color: isToday ? AppColors.text : AppColors.muted,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.35,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                    color: day.intervals.isEmpty
                        ? AppColors.muted
                        : AppColors.text,
                  ),
                ),
                // 예외 사유는 그날이 왜 다른지를 말하는 유일한 자리다. 빼면
                // 휴점일이 "그냥 닫힌 날"과 구분되지 않는다.
                if (day.note != null)
                  Text(
                    day.note!,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: AppColors.muted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 월~일 한 글자 라벨.
String weekdayLabelOf(DateTime date) =>
    const ['월', '화', '수', '목', '금', '토', '일'][(date.weekday - 1) % 7];

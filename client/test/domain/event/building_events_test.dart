import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/domain/event/building_events.dart';

/// 이 검사가 지키는 것 — 목록이 "오늘 열려 있는 것만, 먼저 끝나는 것부터"인가.
/// 날짜 경계(시작일·종료일 당일)와 깨진 파일 판정이 실패 조건이다.
void main() {
  const json = '''
  {"_captured":"2026-08-21","events":[
    {"title":"상설 전시","start":"2026-07-16","end":"2026-11-02",
     "place":"6층 ALT.1","floor":"6F","storeId":"PO-alt1"},
    {"title":"이번 주 팝업","start":"2026-08-20","end":"2026-08-26",
     "place":"지하2층 POP-UP@ICONIC","floor":"B2","storeId":"PO-icon"},
    {"title":"좌표 없는 행사","start":"2026-08-20","end":"2026-08-26",
     "place":"지하1층 중앙 에스컬레이터 옆","floor":null,"storeId":null},
    {"title":"지난 행사","start":"2026-08-01","end":"2026-08-10",
     "place":"1층","floor":"1F","storeId":"PO-gate"}
  ]}''';

  test('열려 있는 것만 남고, 먼저 끝나는 것이 위로 온다', () {
    final open = parseBuildingEvents(json).openOn('2026-08-24');

    expect(open.map((e) => e.title), [
      // 같은 날 끝나는 둘은 안내가 되는 쪽이 먼저다.
      '이번 주 팝업',
      '좌표 없는 행사',
      '상설 전시',
    ]);
    expect(open.first.navigable, isTrue);
    // 좌표가 없어도 목록에서 빠지지 않는다 — 장소 문구는 남아 있다.
    expect(open[1].navigable, isFalse);
    expect(open[1].place, isNotEmpty);
  });

  test('시작일·종료일 당일도 열려 있는 것으로 센다', () {
    final events = parseBuildingEvents(json);
    expect(events.openOn('2026-08-20').map((e) => e.title), contains('이번 주 팝업'));
    expect(events.openOn('2026-08-26').map((e) => e.title), contains('이번 주 팝업'));
    expect(events.openOn('2026-08-27').map((e) => e.title), isNot(contains('이번 주 팝업')));
  });

  test('본문 블록은 순서 그대로 오고, 모르는 종류는 목록을 깨지 않는다', () {
    const withDetails = '''
    {"events":[{"title":"팝업","start":"2026-08-20","end":"2026-08-26",
      "place":"B2","floor":"B2","storeId":"PO-x","details":[
        {"t":"h","text":"SPECIAL PROMOTION"},
        {"t":"p","text":"본문"},
        {"t":"prod","lines":["1만원 이상","띠부씰 증정"],"image":"assets/events/a.jpg"},
        {"t":"notice","items":["한정 수량"]},
        {"t":"신종류","text":"모르는 것"}
      ]}]}''';
    final e = parseBuildingEvents(withDetails).events.single;

    expect(e.details.map((b) => b.kind), [
      'h', 'p', 'prod', 'notice', '신종류',
    ]);
    expect(e.details[2].lines, ['1만원 이상', '띠부씰 증정']);
    expect(e.details[2].image, 'assets/events/a.jpg');
    expect(e.details[3].items, ['한정 수량']);
    // 모르는 종류도 버리지 않는다 — 화면이 건너뛸 뿐이다.
    expect(e.details.last.text, '모르는 것');
  });

  test('빈 목록은 성공이 아니라 실패다', () {
    expect(() => parseBuildingEvents('{"events":[]}'), throwsFormatException);
    expect(() => parseBuildingEvents('[]'), throwsFormatException);
  });
}

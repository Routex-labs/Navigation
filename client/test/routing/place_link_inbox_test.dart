import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_client/routing/place_link.dart';
import 'package:navigation_client/routing/place_link_inbox.dart';

/// 링크가 화면에 닿기까지의 보관함.
///
/// 여기서 틀리면 두 방향으로 손해다 — 중복을 안 거르면 같은 시트가 두 번 열리고,
/// 화면이 세워지기 전에 온 링크를 버리면 사용자는 링크를 눌렀는데 지도만 본다.
void main() {
  const origin = 'https://example.test';
  late PlaceLinkInbox inbox;

  setUp(() => inbox = PlaceLinkInbox(origin: origin));
  tearDown(() => inbox.dispose());

  test('우리 링크를 받아 둔다', () {
    inbox.offer(Uri.parse('$origin/place/thehyundai-seoul/PO-1'));

    expect(
      inbox.value,
      const PlaceLink(buildingId: 'thehyundai-seoul', placeId: 'PO-1'),
    );
  });

  test('가져가면 비고, 다음 링크를 받을 수 있다', () {
    inbox.offer(Uri.parse('$origin/place/b/p1'));
    inbox.take();
    expect(inbox.value, isNull);

    inbox.offer(Uri.parse('$origin/place/b/p2'));

    expect(inbox.value, const PlaceLink(buildingId: 'b', placeId: 'p2'));
  });

  // 최초 URI와 stream이 같은 링크를 함께 흘리는 경우가 있다. 거르지 않으면 시트가
  // 두 번 열린다.
  test('같은 URI가 연달아 오면 한 번만 받는다', () {
    var notified = 0;
    inbox.addListener(() => notified++);

    final uri = Uri.parse('$origin/place/b/p');
    inbox
      ..offer(uri)
      ..offer(uri);

    expect(notified, 1);
  });

  test('우리 링크가 아니면 들고 있던 것을 지우지 않는다', () {
    inbox.offer(Uri.parse('$origin/place/b/p'));

    inbox.offer(Uri.parse('https://evil.test/place/x/y'));

    expect(inbox.value, const PlaceLink(buildingId: 'b', placeId: 'p'));
  });

  // 이 앱은 컴파일 타임 origin으로 링크를 읽는다. 그 값이 없는 빌드에서는 어떤
  // 링크도 우리 것이 아니고, 공유 버튼도 뜨지 않는다.
  test('origin이 없으면 아무 링크도 받지 않는다', () {
    final closed = PlaceLinkInbox(origin: '');
    addTearDown(closed.dispose);

    closed.offer(Uri.parse('$origin/place/b/p'));

    expect(closed.value, isNull);
  });
}

/// 지도 위 오버레이가 지도의 브라우저 이벤트를 가로채게 한다. **웹 전용 문제다.**
library;

import 'package:flutter/widgets.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

/// 웹의 MapLibre는 **플랫폼 뷰**라 DOM에 실제로 존재하는 캔버스가 휠 이벤트를 직접
/// 받는다. 그 위에 Flutter가 시트를 그려도 브라우저에는 시트가 없는 것과 같아서,
/// 시트를 스크롤하면 지도까지 움직였다. iOS·Android는 제스처가 Flutter 아레나를
/// 거치므로 이 문제가 없다.
///
/// [PointerInterceptor]가 투명한 DOM 요소를 깔아 막는다. 웹이 아니면 child를 그대로
/// 통과시키므로 분기 없이 감싸도 된다.
class MapOverlayGuard extends StatelessWidget {
  const MapOverlayGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => PointerInterceptor(child: child);
}

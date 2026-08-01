/// 지도 위에 뜨는 오버레이가 지도의 브라우저 이벤트를 가로채게 한다.
library;

import 'package:flutter/widgets.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

/// 웹에서 지도 위 오버레이(바텀시트 등)를 감싸, 그 영역의 마우스·휠 이벤트가
/// 아래 지도로 새지 않게 막는다.
///
/// 웹의 MapLibre는 **플랫폼 뷰**다 — Flutter가 그리는 캔버스가 아니라 DOM에 실제로
/// 존재하는 `canvas.maplibregl-canvas`이고, 자기 위에서 발생한 휠 이벤트를 직접
/// 받는다. 그 위에 Flutter가 시트를 그려도 브라우저 입장에서는 시트가 없는 것과
/// 같아서, 시트를 스크롤하면 지도까지 함께 움직였다. iOS·Android는 지도가 네이티브
/// 뷰이고 제스처가 Flutter 아레나를 거치므로 이 문제가 없다 — 웹 전용 증상이다.
///
/// [PointerInterceptor]는 오버레이 자리에 투명한 DOM 요소를 깔아 브라우저가 이벤트를
/// 지도에 전달하지 못하게 한다. 웹이 아닌 플랫폼에서는 child를 그대로 통과시키므로
/// 분기 없이 그냥 감싸도 된다.
class MapOverlayGuard extends StatelessWidget {
  const MapOverlayGuard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => PointerInterceptor(child: child);
}

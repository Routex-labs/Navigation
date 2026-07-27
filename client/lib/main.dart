import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'app.dart';

/// Android에서 지도가 **검게 뜨는 문제**를 막기 위한 필수 설정.
///
/// maplibre_gl 0.26의 Dart 기본값은 `useHybridComposition = false`다(문서 주석은
/// true라고 써 있지만 실제 코드는 false — platform_interface의
/// `MapLibreMethodChannel.useHybridComposition`). 이 값이 false면 두 가지가 동시에
/// 정해진다.
///
/// 1. Flutter 쪽: 그냥 `AndroidView` → **Virtual Display** 방식. 플랫폼 뷰를
///    화면 밖 가상 디스플레이에 그린 뒤 텍스처로 읽어 와 합성한다.
/// 2. 네이티브 쪽: `MapLibreMapBuilder`가 `textureMode(false)`로 지도를 만든다
///    → MapLibre가 **SurfaceView**로 렌더링한다.
///
/// **SurfaceView는 Virtual Display 읽기에 잡히지 않는다.** SurfaceView는 자기
/// 하드웨어 surface에 그리고 SurfaceFlinger가 따로 합성하므로, Flutter가 가상
/// 디스플레이에서 읽어 온 텍스처에는 지도 픽셀이 하나도 담기지 않는다. 그래서
/// 지도 영역이 통째로 검게 남는다 — 스타일에 background 레이어를 깔아도
/// 소용없다. GL이 그린 내용 자체가 Flutter 텍스처까지 도달하지 못하기 때문이다.
///
/// 이 값을 true로 올리면 두 쪽이 함께 뒤집힌다: Flutter는
/// `PlatformViewLink` + `initAndroidView`(Hybrid Composition)로, 네이티브는
/// `textureMode(true)`(TextureView)로 간다. 플러그인 주석도 "textureMode must be
/// on if Flutter is using Hybrid Composition. Both are correctness requirements,
/// not knobs."라고 못 박고 있다 — 둘은 짝이며 따로 놀면 안 된다.
///
/// **지도 위젯이 하나라도 만들어지기 전에** 설정해야 한다(생성 시점에만 읽는
/// 값이라 런타임 변경은 네이티브에서 no-op). 그래서 runApp보다 앞에 둔다.
/// 웹·iOS는 이 분기를 타지 않으므로 Android에서만 건드린다.
void _configureMapPlatformView() {
  if (kIsWeb) return;
  if (defaultTargetPlatform != TargetPlatform.android) return;
  MapLibreMap.useHybridComposition = true;
}

void main() {
  _configureMapPlatformView();
  runApp(const NavigationApp());
}

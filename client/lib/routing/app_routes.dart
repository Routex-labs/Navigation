/// 앱의 named route. **하나뿐이다** — 지도 셸 하나가 야외·실내와 그 사이 모든
/// 단계를 시트·오버레이로 그려서 push할 곳이 없다.
///
/// 상수 하나에 클래스를 두는 이유는 `initialRoute`와 `routes`가 같은 문자열을
/// 봐야 하기 때문이다. 한쪽만 고치면 앱이 빈 화면으로 뜬다.
library;

class AppRoutes {
  AppRoutes._();

  static const outdoorMap = '/';
}

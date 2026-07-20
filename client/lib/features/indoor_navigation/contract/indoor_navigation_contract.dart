/// 실내 내비게이션 UI 연동 계약 (Phase 1.5).
///
/// UI팀이 의존하는 공개 표면. 여기에 있는 것만 UI가 import한다. 구현체(headless
/// 컨트롤러, 렌더러)는 이 계약을 넘어 서로의 내부를 import하지 않는다.
///
/// - 읽기(로직→UI): [IndoorNavigationView] — PdrSnapshot·CalibrationStatus 스트림
/// - 쓰기(UI→로직): [IndoorNavigationIntents] — start/stop/anchor/changeFloor
/// - 좌표 변환: [FloorCoordinateTransform] — PDR 좌표를 floor local_m로
/// - 상태: [CalibrationStatus], [PdrAnchor]
///
/// 코어 타입(PdrSnapshot/PdrQuality/PdrLocalPoint/HeadingReference)은
/// indoor_pdr_core를 그대로 재노출한다.
library;

export 'package:indoor_pdr_core/indoor_pdr_core.dart'
    show
        PdrSnapshot,
        PdrPreview,
        PdrQuality,
        PdrQualityState,
        PdrQualityFeatures,
        PdrLocalPoint,
        HeadingReference;

export 'calibration_state.dart';
export 'indoor_navigation_intents.dart';
export 'indoor_navigation_view.dart';
export 'pdr_anchor.dart';
export 'pdr_heading_observation.dart';
export 'pdr_runtime_status.dart';

import 'indoor_navigation_intents.dart';
import 'indoor_navigation_view.dart';

/// 관찰(View) + 명령(Intents)을 함께 제공하는 컨트롤러 계약.
/// 구현체는 Phase 2에서 headless 로직으로 만든다.
abstract interface class IndoorNavigationController
    implements IndoorNavigationView, IndoorNavigationIntents {}

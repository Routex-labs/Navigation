import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/service_locator.dart';
import '../../features/indoor_navigation/contract/indoor_navigation_contract.dart';

const _svgAsset = 'assets/mock/demo_floor_map_v5.svg';
const _svgUnitsPerMeter = 20.0;
// 첨부된 북쪽 고정 지도에서 추정한 도면 +X축의 방위각이다. SVG를 화면에서
// 시계 방향 30° 돌리면 +X축이 북쪽 기준 120°가 된다.
const _svgXAxisBearingDegFromNorth = 120.0;
const _svgClockwiseRotationDeg = _svgXAxisBearingDegFromNorth - 90.0;

/// demo_floor_map_v5.svg의 N17 좌표(892, 594)를 PDR 동-북 좌표로 바꾼 값이다.
/// SVG의 아래 방향(+Y)은 PDR의 북쪽과 반대라 northM 부호를 반전한다. SVG와
/// mock floor 데이터는 20 SVG units = 1m 규약을 공유하지만, 아직 현장 실측으로
/// 검증된 축척은 아니다.
const _teamMakingRoom3Entrance = PdrLocalPoint(44.6, -29.7);

/// 서울창업허브 SVG 원본을 고해상도 PNG로 렌더한 지도 위에서 실제 iOS PDR 위치를
/// 확인하는 실기기용 화면. flutter_svg가 원본의 CSS/필터를 온전히 해석하지 못해
/// 지도 레이어만 PNG를 쓰고, PDR 좌표와 오버레이는 원본 SVG 좌표계를 그대로 쓴다.
///
/// 시작점은 팀메이킹룸 3 입구 노드 N17이다. PDR 좌표계가 자북을 제공하지
/// 못하는 기기에서는 "휴대폰 상단이 SVG의 위쪽"이라는 테스트 전제를 써서
/// 회전을 0도로 보정한다.
class PdrSvgTestScreen extends StatefulWidget {
  const PdrSvgTestScreen({super.key});

  @override
  State<PdrSvgTestScreen> createState() => _PdrSvgTestScreenState();
}

class _PdrSvgTestScreenState extends State<PdrSvgTestScreen> {
  StreamSubscription<PdrSnapshot>? _snapshotSub;
  StreamSubscription<CalibrationStatus>? _calibrationSub;
  StreamSubscription<PdrRuntimeStatus>? _runtimeSub;

  PdrSnapshot? _snapshot;
  CalibrationStatus _calibration = const CalibrationStatus.uncalibrated();
  PdrRuntimeStatus _runtime = const PdrRuntimeStatus.idle();
  bool _starting = true;

  @override
  void initState() {
    super.initState();
    _snapshotSub = indoorNavigationDriver.snapshots.listen((snapshot) {
      if (mounted) setState(() => _snapshot = snapshot);
    });
    _calibrationSub = indoorNavigationDriver.calibration.listen((calibration) {
      if (mounted) setState(() => _calibration = calibration);
    });
    _runtimeSub = indoorNavigationDriver.runtimeStatuses.listen((runtime) {
      if (mounted) setState(() => _runtime = runtime);
    });
    unawaited(_startTracking());
  }

  Future<void> _startTracking() async {
    if (mounted) {
      setState(() {
        _starting = true;
        _snapshot = null;
      });
    }

    await indoorNavigationDriver.stopGuidance();
    await indoorNavigationDriver.startGuidance(floorId: 'seoul-startup-hub-1f');
    await indoorNavigationDriver.confirmAnchorByPin(
      floorPointM: _teamMakingRoom3Entrance,
    );

    // arbitrary corrected heading인 경우에도 현장 테스트가 바로 가능하도록
    // SVG 상단을 0도로 둔다. 사용자는 시작 시 휴대폰 상단을 SVG 상단에 맞춘다.
    if (indoorNavigationDriver
        .currentCalibration
        .requiresManualRotationCalibration) {
      await indoorNavigationDriver.confirmAnchorByFloorDirection(
        floorDirection: pdrDirectionForBearing(_svgClockwiseRotationDeg),
      );
    }
    if (mounted) setState(() => _starting = false);
  }

  PdrLocalPoint get _floorPosition {
    final snapshot = _snapshot;
    if (snapshot == null) return _teamMakingRoom3Entrance;
    return _toMapCoordinate(snapshot.position);
  }

  List<PdrLocalPoint> get _floorPath {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return const [_teamMakingRoom3Entrance];
    }
    return snapshot.path.map(_toMapCoordinate).toList(growable: false);
  }

  List<PdrLocalPoint> get _previewFloorPath {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return const [_teamMakingRoom3Entrance];
    }
    return snapshot.preview.path.map(_toMapCoordinate).toList(growable: false);
  }

  /// PDR ENU(동·북) 좌표를 북쪽 고정 지도에 맞는 도면 좌표로 옮긴다.
  /// 이 화면은 [FloorCoordinateTransform]의 일반 보정과 별도로, 첨부 지도에서
  /// 읽은 건물 방위각을 적용하는 현장 테스트 전용 렌더 변환이다.
  PdrLocalPoint _toMapCoordinate(PdrLocalPoint pdr) {
    final radians = _svgClockwiseRotationDeg * math.pi / 180;
    final east = pdr.eastM * math.cos(radians) - pdr.northM * math.sin(radians);
    final north =
        pdr.eastM * math.sin(radians) + pdr.northM * math.cos(radians);
    return PdrLocalPoint(
      _teamMakingRoom3Entrance.eastM + east,
      _teamMakingRoom3Entrance.northM + north,
    );
  }

  String get _statusText {
    if (_starting) return '팀메이킹룸 3 입구 N17에서 센서를 시작하고 있습니다.';
    if (_runtime.state == PdrRuntimeState.degraded) {
      return '센서 오류: ${_runtime.warnings.join(', ')}';
    }
    if (!_calibration.canRenderPosition) return '시작 위치를 보정하고 있습니다.';
    return 'N17 기준 PDR 추적 중 · 화면의 N 화살표를 기준으로 걸어주세요.';
  }

  @override
  void dispose() {
    unawaited(_snapshotSub?.cancel());
    unawaited(_calibrationSub?.cancel());
    unawaited(_runtimeSub?.cancel());
    unawaited(indoorNavigationDriver.stopGuidance());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(
        title: const Text('서울창업허브 PDR 이동 테스트'),
        actions: [
          IconButton(
            tooltip: 'PDR 다시 시작',
            onPressed: _starting ? null : _startTracking,
            icon: const Icon(Icons.restart_alt),
          ),
          IconButton(
            tooltip: '앱 권한 설정 열기',
            onPressed: openAppSettings,
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _PdrSvgMap(
                floorPath: _floorPath,
                previewPath: _previewFloorPath,
                position: _floorPosition,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _statusText,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '시작: 팀메이킹룸 3 입구 (N17) · '
                    '${snapshot?.steps ?? 0}걸음 · '
                    '${(snapshot?.distanceM ?? 0).toStringAsFixed(2)}m',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 6),
                  const _TraceLegend(),
                  const SizedBox(height: 4),
                  Text(
                    '도면 좌표 기준 · 현장 실측 보정 전',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (_runtime.warnings.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _runtime.warnings.join(', '),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TraceLegend extends StatelessWidget {
  const _TraceLegend();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 22,
          height: 4,
          child: ColoredBox(color: Color(0xFFFF8A00)),
        ),
        SizedBox(width: 5),
        Text('보행 미리보기'),
        SizedBox(width: 16),
        SizedBox(
          width: 22,
          height: 4,
          child: ColoredBox(color: Color(0xFF00A86B)),
        ),
        SizedBox(width: 5),
        Text('확정 위치'),
        SizedBox(width: 16),
        SizedBox(
          width: 22,
          height: 4,
          child: ColoredBox(color: Color(0xFF1769AA)),
        ),
        SizedBox(width: 5),
        Text('노드 맵매칭'),
      ],
    );
  }
}

class _PdrSvgMap extends StatefulWidget {
  const _PdrSvgMap({
    required this.floorPath,
    required this.previewPath,
    required this.position,
  });

  final List<PdrLocalPoint> floorPath;
  final List<PdrLocalPoint> previewPath;
  final PdrLocalPoint position;

  @override
  State<_PdrSvgMap> createState() => _PdrSvgMapState();
}

class _PdrSvgMapState extends State<_PdrSvgMap> {
  late final WebViewController _controller;
  bool _pageReady = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFEDF4E7))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            _pageReady = true;
            unawaited(_renderPdrOverlay());
          },
        ),
      );
    unawaited(_loadSvg());
  }

  @override
  void didUpdateWidget(covariant _PdrSvgMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    unawaited(_renderPdrOverlay());
  }

  Future<void> _loadSvg() async {
    final svg = await rootBundle.loadString(_svgAsset);
    // XML 선언은 HTML 문서 본문에 중첩할 수 없으므로 제거한다. SVG 본문은
    // WKWebView가 그대로 파싱해 CSS, <use>, filter를 모두 벡터로 렌더한다.
    final svgBody = svg.replaceFirst(RegExp(r'<\?xml[^>]*\?>\s*'), '');
    await _controller.loadHtmlString(_buildHtml(svgBody));
  }

  Future<void> _renderPdrOverlay() async {
    if (!_pageReady) return;
    final confirmed = _encodePath(widget.floorPath);
    final preview = _encodePath(widget.previewPath);
    final position = _encodePoint(widget.position);
    await _controller.runJavaScript(
      'window.updatePdr($confirmed, $preview, $position);',
    );
  }

  String _encodePath(List<PdrLocalPoint> points) =>
      jsonEncode(points.map(_encodePointMap).toList(growable: false));

  String _encodePoint(PdrLocalPoint point) =>
      jsonEncode(_encodePointMap(point));

  Map<String, double> _encodePointMap(PdrLocalPoint point) => {
    'x': point.eastM * _svgUnitsPerMeter,
    'y': -point.northM * _svgUnitsPerMeter,
  };

  @override
  Widget build(BuildContext context) => WebViewWidget(controller: _controller);
}

String _buildHtml(String svg) =>
    '''
<!doctype html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=5, user-scalable=yes">
  <style>
    html, body, #map { width: 100%; height: 100%; margin: 0; overflow: hidden; background: #edf4e7; }
    #map { touch-action: pan-x pan-y pinch-zoom; }
    #map > svg {
      display: block;
      width: 100%;
      height: 100%;
      overflow: visible;
      transform: rotate(${_svgClockwiseRotationDeg}deg);
      transform-origin: center center;
    }
    #north {
      position: fixed;
      z-index: 10;
      top: 14px;
      right: 16px;
      display: flex;
      align-items: center;
      gap: 4px;
      padding: 6px 9px;
      border-radius: 16px;
      color: #17324d;
      background: rgba(255, 255, 255, .92);
      font: 700 14px -apple-system, BlinkMacSystemFont, sans-serif;
      box-shadow: 0 1px 5px rgba(0, 0, 0, .25);
    }
  </style>
</head>
<body>
  <div id="map">$svg</div>
  <div id="north">↑ N</div>
  <script>
    const svg = document.querySelector('#map > svg');
    const ns = 'http://www.w3.org/2000/svg';
    const overlay = document.createElementNS(ns, 'g');
    overlay.setAttribute('id', 'pdr-overlay');
    overlay.setAttribute('pointer-events', 'none');

    const previewPath = document.createElementNS(ns, 'path');
    previewPath.setAttribute('fill', 'none');
    previewPath.setAttribute('stroke', '#ff8a00');
    previewPath.setAttribute('stroke-width', '3');
    previewPath.setAttribute('stroke-linecap', 'round');
    previewPath.setAttribute('stroke-linejoin', 'round');
    previewPath.setAttribute('vector-effect', 'non-scaling-stroke');

    const confirmedPath = document.createElementNS(ns, 'path');
    confirmedPath.setAttribute('fill', 'none');
    confirmedPath.setAttribute('stroke', '#00a86b');
    confirmedPath.setAttribute('stroke-width', '4');
    confirmedPath.setAttribute('stroke-linecap', 'round');
    confirmedPath.setAttribute('stroke-linejoin', 'round');
    confirmedPath.setAttribute('vector-effect', 'non-scaling-stroke');

    const matchedPath = document.createElementNS(ns, 'path');
    matchedPath.setAttribute('fill', 'none');
    matchedPath.setAttribute('stroke', '#1769aa');
    matchedPath.setAttribute('stroke-width', '3');
    matchedPath.setAttribute('stroke-dasharray', '7 5');
    matchedPath.setAttribute('stroke-linecap', 'round');
    matchedPath.setAttribute('stroke-linejoin', 'round');
    matchedPath.setAttribute('vector-effect', 'non-scaling-stroke');

    const markerHalo = document.createElementNS(ns, 'circle');
    markerHalo.setAttribute('r', '13');
    markerHalo.setAttribute('fill', '#ffffff');
    markerHalo.setAttribute('vector-effect', 'non-scaling-stroke');
    const marker = document.createElementNS(ns, 'circle');
    marker.setAttribute('r', '10');
    marker.setAttribute('fill', '#00a86b');
    marker.setAttribute('vector-effect', 'non-scaling-stroke');
    const markerDot = document.createElementNS(ns, 'circle');
    markerDot.setAttribute('r', '3.5');
    markerDot.setAttribute('fill', '#ffffff');

    overlay.append(previewPath, confirmedPath, matchedPath, markerHalo, marker, markerDot);
    svg.append(overlay);

    function nodePoint(node) {
      const values = (node.getAttribute('transform') || '').match(/translate\\(\\s*([-.\\d]+)[, ]+\\s*([-.\\d]+)/);
      return values ? { x: Number(values[1]), y: Number(values[2]) } : null;
    }
    const nodes = new Map(
      Array.from(svg.querySelectorAll('[data-node-id]'))
        .map((node) => [node.dataset.nodeId, nodePoint(node)])
        .filter((entry) => entry[1] !== null),
    );
    const graphSegments = Array.from(svg.querySelectorAll('.graph-edge'))
      .map((edge) => ({ from: nodes.get(edge.dataset.from), to: nodes.get(edge.dataset.to) }))
      .filter((edge) => edge.from && edge.to);

    function nearestOnSegment(point, edge) {
      const dx = edge.to.x - edge.from.x;
      const dy = edge.to.y - edge.from.y;
      const lengthSquared = dx * dx + dy * dy;
      const t = lengthSquared === 0 ? 0 : Math.max(0, Math.min(1,
        ((point.x - edge.from.x) * dx + (point.y - edge.from.y) * dy) / lengthSquared));
      const x = edge.from.x + dx * t;
      const y = edge.from.y + dy * t;
      return { x, y, distanceSquared: (point.x - x) ** 2 + (point.y - y) ** 2 };
    }
    function mapMatch(points) {
      return points.map((point) => {
        let nearest = null;
        for (const edge of graphSegments) {
          const candidate = nearestOnSegment(point, edge);
          if (!nearest || candidate.distanceSquared < nearest.distanceSquared) nearest = candidate;
        }
        // 4.5m 밖의 위치는 억지로 그래프에 붙이지 않아 원시 PDR 오차를 숨기지 않는다.
        return nearest && nearest.distanceSquared <= 90 * 90
          ? { x: nearest.x, y: nearest.y }
          : point;
      });
    }

    function asPath(points) {
      if (!points || points.length < 2) return '';
      return 'M ' + points.map((p) => p.x + ' ' + p.y).join(' L ');
    }
    window.updatePdr = function(confirmed, preview, position) {
      previewPath.setAttribute('d', asPath(preview));
      confirmedPath.setAttribute('d', asPath(confirmed));
      matchedPath.setAttribute('d', asPath(mapMatch(confirmed)));
      for (const element of [markerHalo, marker, markerDot]) {
        element.setAttribute('cx', position.x);
        element.setAttribute('cy', position.y);
      }
    };
  </script>
</body>
</html>
''';

import 'package:flutter/material.dart';

/// 지도 위에 진단 상태를 한 줄로 띄우는 디버그 칩.
///
/// 실측 현장에서 임계값을 조정하려면 "지금 값이 얼마고 판정이 걸렸는지"를 파일을
/// 꺼내기 전에 눈으로 봐야 한다. 진단 JSON은 사후 분석용이고, 이 칩은 그 자리에서
/// 판정이 왜 안 걸리는지 알기 위한 것이다. 기압계·GPS 진입 판정처럼 **표시할
/// 내용이 이미 한 줄로 정리된 쪽**이 문자열을 만들어 넘긴다 — 칩은 무엇을 재는지
/// 모른다.
///
/// 값 갱신은 5Hz까지 올 수 있어 화면 전체를 다시 그리면 안 된다. 호출자는
/// `ValueNotifier<String?>`와 `ValueListenableBuilder`로 이 칩만 다시 그린다.
class MapDebugChip extends StatelessWidget {
  const MapDebugChip({super.key, required this.text});

  /// 표시할 한 줄. null이면 아무것도 그리지 않는다(값이 아직 없음).
  final String? text;

  @override
  Widget build(BuildContext context) {
    final label = text;
    if (label == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xE6212124),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            height: 1.2,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// 건물 정보 Q&A 패널 (design.md 공통 컴포넌트: RagChatPanel).
/// 실제 RAG 응답이 붙기 전까지 하드코딩된 대화 샘플을 보여준다.
class RagChatPanel extends StatelessWidget {
  const RagChatPanel({super.key});

  static const _sampleExchanges = [
    ('화장실 몇 시까지 이용 가능해요?', '본관 화장실은 22시까지 운영합니다.'),
    ('엘리베이터는 어디 있어요?', '정문 로비 안내데스크 옆에 있습니다.'),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '건물 정보 Q&A',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            for (final exchange in _sampleExchanges) ...[
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(exchange.$1),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(exchange.$2),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

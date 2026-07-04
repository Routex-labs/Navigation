import 'package:flutter/material.dart';

/// 예상 도착 시간 카드 (design.md 공통 컴포넌트: EtaCard).
class EtaCard extends StatelessWidget {
  const EtaCard({super.key, required this.distanceMeters, required this.minutes});

  final double distanceMeters;
  final int minutes;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text('목적지까지 약 $minutes분 / ${distanceMeters.round()}m'),
      ),
    );
  }
}

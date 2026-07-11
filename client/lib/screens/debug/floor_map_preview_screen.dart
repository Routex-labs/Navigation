import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../models/floor_plan.dart';
import '../../widgets/floor_plan_view.dart';

/// hyundai_floor_map_corrected_v6.svg에서 변환한 매장 폴리곤 데이터를
/// FloorPlanView로 그려 탭 이벤트가 잘 붙는지 확인하는 개발용 화면.
class FloorMapPreviewScreen extends StatefulWidget {
  const FloorMapPreviewScreen({super.key});

  @override
  State<FloorMapPreviewScreen> createState() => _FloorMapPreviewScreenState();
}

class _FloorMapPreviewScreenState extends State<FloorMapPreviewScreen> {
  FloorPlan? _floorPlan;
  StorePolygon? _selectedStore;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final raw = await rootBundle.loadString('assets/mock/hyundai_floor_1f.json');
    final floorPlan = FloorPlan.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    if (!mounted) return;
    setState(() => _floorPlan = floorPlan);
  }

  @override
  Widget build(BuildContext context) {
    final floorPlan = _floorPlan;
    return Scaffold(
      appBar: AppBar(title: const Text('더현대 서울 평면도 미리보기')),
      body: floorPlan == null
          ? const Center(child: CircularProgressIndicator())
          : FloorPlanView(
              floorPlan: floorPlan,
              onStoreSelected: (store) => setState(() => _selectedStore = store),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _selectedStore == null
                ? '매장을 탭해보세요'
                : '${_selectedStore!.name} · ${_selectedStore!.category ?? '-'}',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

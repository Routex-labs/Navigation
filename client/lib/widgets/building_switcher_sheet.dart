import 'package:flutter/material.dart';

import '../core/service_locator.dart';
import '../models/building.dart';
import '../theme/app_theme.dart';

/// 실내 모드 햄버거 버튼으로 여는 건물 선택 시트. 테스트용으로 백엔드에
/// 적재된 건물 목록(더현대서울/데모 건물 등)을 그대로 보여주고, 고르면
/// 그 건물 ID를 반환한다.
class BuildingSwitcherSheet extends StatefulWidget {
  const BuildingSwitcherSheet({super.key, required this.selectedBuildingId});

  final String selectedBuildingId;

  static Future<String?> show(BuildContext context, {required String selectedBuildingId}) {
    return showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => BuildingSwitcherSheet(selectedBuildingId: selectedBuildingId),
    );
  }

  @override
  State<BuildingSwitcherSheet> createState() => _BuildingSwitcherSheetState();
}

class _BuildingSwitcherSheetState extends State<BuildingSwitcherSheet> {
  late Future<List<Building>> _buildings;

  @override
  void initState() {
    super.initState();
    _buildings = buildingRepository.getAllBuildings();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '건물 선택 (테스트)',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.text),
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<Building>>(
              future: _buildings,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final buildings = snapshot.data ?? const [];
                if (buildings.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('불러올 수 있는 건물이 없습니다', style: TextStyle(color: AppColors.muted)),
                    ),
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final building in buildings)
                      ListTile(
                        leading: Icon(
                          Icons.apartment_rounded,
                          color: building.id == widget.selectedBuildingId
                              ? AppColors.indoor
                              : AppColors.muted,
                        ),
                        title: Text(
                          building.name,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                        subtitle: Text('${building.floors.length}개 층'),
                        trailing: building.id == widget.selectedBuildingId
                            ? const Icon(Icons.check, color: AppColors.indoor)
                            : null,
                        onTap: () => Navigator.of(context).pop(building.id),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

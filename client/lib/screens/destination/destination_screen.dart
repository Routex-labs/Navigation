import 'package:flutter/material.dart';

import '../../core/api_config.dart';
import '../../core/service_locator.dart';
import '../../models/poi_search_result.dart';
import '../../routing/app_routes.dart';
import '../../theme/app_theme.dart';

class DestinationScreen extends StatefulWidget {
  const DestinationScreen({super.key});

  @override
  State<DestinationScreen> createState() => _DestinationScreenState();
}

class _DestinationScreenState extends State<DestinationScreen> {
  bool _loading = true;
  List<PoiSearchResult> _results = [];

  @override
  void initState() {
    super.initState();
    _search('');
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    final results = await destinationRepository.searchDestinations(
      demoBuildingId,
      query,
    );
    if (!mounted) return;
    setState(() {
      _results = results;
      _loading = false;
    });
  }

  void _selectDestination(PoiSearchResult destination) {
    Navigator.of(context).pushNamed(
      AppRoutes.routeGuide,
      arguments: destination,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('목적지 입력')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search, size: 20, color: AppColors.muted),
                hintText: '목적지를 입력하세요',
              ),
              onChanged: _search,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? const _EmptyResults()
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        itemCount: _results.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final destination = _results[index];
                          return _DestinationRow(
                            destination: destination,
                            onTap: () => _selectDestination(destination),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('🔍', style: TextStyle(fontSize: 36)),
          SizedBox(height: 10),
          Text(
            '찾을 수 없어요',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.text),
          ),
          SizedBox(height: 4),
          Text(
            '다시 입력해볼까요?',
            style: TextStyle(fontSize: 12.5, color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _DestinationRow extends StatelessWidget {
  const _DestinationRow({required this.destination, required this.onTap});

  final PoiSearchResult destination;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: AppColors.blue50,
          borderRadius: BorderRadius.circular(11),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.place_outlined, color: AppColors.indoor, size: 19),
      ),
      title: Text(
        destination.name,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.blue50,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              destination.floor,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 18, color: AppColors.muted),
        ],
      ),
    );
  }
}

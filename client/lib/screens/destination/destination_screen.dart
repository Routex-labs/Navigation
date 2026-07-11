import 'package:flutter/material.dart';

import '../../core/api_config.dart';
import '../../core/service_locator.dart';
import '../../models/poi_search_result.dart';
import '../../routing/app_routes.dart';

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
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '목적지를 입력하세요',
                border: OutlineInputBorder(),
              ),
              onChanged: _search,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? const Center(child: Text('찾을 수 없어요. 다시 입력해볼까요?'))
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final destination = _results[index];
                          return ListTile(
                            leading: const Icon(Icons.place),
                            title: Text(destination.name),
                            subtitle: Text(destination.floor),
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

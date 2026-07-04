import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const apiBaseUrl = 'http://10.0.2.2:8001';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Navigation Client',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const ApiHealthCheckPage(),
    );
  }
}

class ApiHealthCheckPage extends StatefulWidget {
  const ApiHealthCheckPage({super.key});

  @override
  State<ApiHealthCheckPage> createState() => _ApiHealthCheckPageState();
}

class _ApiHealthCheckPageState extends State<ApiHealthCheckPage> {
  String _status = '확인 중...';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkHealth();
  }

  Future<void> _checkHealth() async {
    setState(() {
      _loading = true;
      _status = '확인 중...';
    });
    try {
      final response = await http
          .get(Uri.parse('$apiBaseUrl/health'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        setState(() => _status = 'API 연결 성공: $body');
      } else {
        setState(() => _status = 'API 오류 (상태 코드 ${response.statusCode})');
      }
    } catch (e) {
      setState(() => _status = 'API 연결 실패: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('FastAPI 연동 테스트'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(apiBaseUrl, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            if (_loading) const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_status, textAlign: TextAlign.center),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _checkHealth,
        tooltip: 'Retry',
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

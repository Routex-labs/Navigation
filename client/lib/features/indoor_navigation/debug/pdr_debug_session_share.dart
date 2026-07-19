import 'dart:convert';
import 'dart:ui';

import 'package:share_plus/share_plus.dart';

/// 디버그 세션 JSON을 파일 첨부로 시스템 공유 시트에 넘긴다.
class PdrDebugSessionShare {
  const PdrDebugSessionShare();

  Future<void> share(
    Map<String, Object?> session, {
    Rect? sharePositionOrigin,
  }) async {
    final startedAt = session['started_at_utc']?.toString() ?? 'unknown';
    final filename = 'pdr-debug-${_filenameTimestamp(startedAt)}.json';
    final json = const JsonEncoder.withIndent('  ').convert(session);
    await Share.shareXFiles(
      [
        XFile.fromData(
          utf8.encode(json),
          mimeType: 'application/json',
          name: filename,
        ),
      ],
      subject: 'PDR debug session',
      text: 'PDR 실측 디버그 세션 JSON입니다.',
      sharePositionOrigin: sharePositionOrigin,
      fileNameOverrides: [filename],
    );
  }

  static String _filenameTimestamp(String iso8601) => iso8601
      .replaceAll(':', '-')
      .replaceAll('.', '-')
      .replaceAll('Z', 'Z')
      .replaceAll(RegExp(r'[^0-9A-Za-z_-]'), '-');
}

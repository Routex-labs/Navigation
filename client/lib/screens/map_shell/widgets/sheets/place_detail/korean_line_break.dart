/// 한글 문단의 줄 길이 고르기. 어절 묶기는 `RoutexTypography.keepWordsWhole`이 맡는다.
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:routex_design_system/routex_design_system.dart';

/// 같은 최소 줄 수 안에서 문단의 줄 길이를 고르게 다시 나눈다.
///
/// Flutter의 기본 줄바꿈은 현재 줄에 들어가는 어절을 최대한 채우는 탐욕 방식이라,
/// 마지막 줄에 짧은 어절 몇 개만 고립되는 일이 잦다. 먼저 기본 레이아웃의 줄 수를
/// 구한 뒤, 그 줄 수는 늘리지 않으면서 각 줄의 남는 폭 제곱합이 가장 작은 공백
/// 조합을 찾는다. 결과는 명시적 줄바꿈이라 한글 음절 중간이 잘리지 않는다.
String balancedKoreanLines(
  String text, {
  required TextStyle style,
  required double maxWidth,
  required TextDirection textDirection,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final words = text.trim().split(RegExp(r'\s+'));
  if (words.length < 3 || !maxWidth.isFinite || maxWidth <= 0) {
    return RoutexTypography.keepWordsWhole(text);
  }

  double widthOf(String value) {
    final painter = TextPainter(
      text: TextSpan(text: value, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    return painter.width;
  }

  final natural = TextPainter(
    text: TextSpan(text: RoutexTypography.keepWordsWhole(text), style: style),
    textDirection: textDirection,
    textScaler: textScaler,
  )..layout(maxWidth: maxWidth);
  final lineCount = natural.computeLineMetrics().length;
  if (lineCount <= 1 || lineCount >= words.length) {
    return RoutexTypography.keepWordsWhole(text);
  }

  final memo = <(int, int), ({double score, List<String> lines})?>{};
  ({double score, List<String> lines})? solve(int start, int linesLeft) {
    final key = (start, linesLeft);
    if (memo.containsKey(key)) return memo[key];
    if (linesLeft == 1) {
      final line = words.sublist(start).join(' ');
      final width = widthOf(line);
      return memo[key] = width <= maxWidth
          ? (score: math.pow(maxWidth - width, 2).toDouble(), lines: [line])
          : null;
    }

    ({double score, List<String> lines})? best;
    final lastEnd = words.length - linesLeft + 1;
    for (var end = start + 1; end <= lastEnd; end++) {
      final line = words.sublist(start, end).join(' ');
      final width = widthOf(line);
      if (width > maxWidth) break;
      final tail = solve(end, linesLeft - 1);
      if (tail == null) continue;
      final score = math.pow(maxWidth - width, 2).toDouble() + tail.score;
      if (best == null || score < best.score) {
        best = (score: score, lines: [line, ...tail.lines]);
      }
    }
    return memo[key] = best;
  }

  return solve(0, lineCount)?.lines.join('\n') ??
      RoutexTypography.keepWordsWhole(text);
}

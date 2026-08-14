/// 한글 줄바꿈 보정.
library;

import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// 어절이 줄 끝에서 쪼개지지 않게 음절을 묶는다.
///
/// 유니코드 기본 줄바꿈 규칙(UAX #14)은 한글 음절 사이 어디서나 줄을 끊을 수 있게
/// 본다. 그래서 "더현대서울(B2)R / 점입니다"처럼 한 단어가 두 줄로 갈라진다. CSS라면
/// `word-break: keep-all`로 끄지만 Flutter에는 그 옵션이 없어서, 어절 안의 글자를
/// word joiner(U+2060)로 이어 붙여 공백에서만 끊기게 만든다.
///
/// **긴 어절은 손대지 않는다.** 한 줄보다 긴 어절을 통째로 묶으면 줄바꿈이 아니라
/// 넘침이 되어 글자가 잘린다. [maxJoinLength]는 "이 정도면 어차피 한 줄에 들어간다"고
/// 보는 길이다. 시트 본문은 폭 350px에 13~14px 글자라 한 줄에 24자쯤 들어가므로
/// 18자까지는 묶어도 안전하고, 그보다 긴 어절은 기존 규칙대로 쪼개지게 둔다.
String keepWordsWhole(String text, {int maxJoinLength = 18}) {
  const joiner = '⁠';
  return text
      .split(' ')
      .map(
        (word) => word.length > maxJoinLength || word.length < 2
            ? word
            : word.split('').join(joiner),
      )
      .join(' ');
}

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
    return keepWordsWhole(text);
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
    text: TextSpan(text: keepWordsWhole(text), style: style),
    textDirection: textDirection,
    textScaler: textScaler,
  )..layout(maxWidth: maxWidth);
  final lineCount = natural.computeLineMetrics().length;
  if (lineCount <= 1 || lineCount >= words.length) return keepWordsWhole(text);

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

  return solve(0, lineCount)?.lines.join('\n') ?? keepWordsWhole(text);
}

/// 한글 줄바꿈 보정.
library;

/// 어절이 줄 끝에서 쪼개지지 않게 음절을 묶는다.
///
/// 유니코드 기본 줄바꿈 규칙(UAX #14)은 한글 음절 사이 어디서나 줄을 끊을 수 있게
/// 본다. 그래서 "더현대서울(B2)R / 점입니다"처럼 한 단어가 두 줄로 갈라진다. CSS라면
/// `word-break: keep-all`로 끄지만 Flutter에는 그 옵션이 없어서, 어절 안의 글자를
/// word joiner(U+2060)로 이어 붙여 공백에서만 끊기게 만든다.
///
/// **긴 어절은 손대지 않는다.** 한 줄보다 긴 어절을 통째로 묶으면 줄바꿈이 아니라
/// 넘침이 되어 글자가 잘린다. [maxJoinLength]는 "이 정도면 어차피 한 줄에 들어간다"고
/// 보는 길이이고, 그보다 긴 어절은 기존 규칙대로 쪼개지게 둔다.
String keepWordsWhole(String text, {int maxJoinLength = 14}) {
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

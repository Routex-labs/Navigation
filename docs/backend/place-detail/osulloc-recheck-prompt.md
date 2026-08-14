# 오설록 재검증 프롬프트 — 브라우저 에이전트용

이 매장은 값이 바뀌면 **화면이 조용히 거짓말을 하는** 필드(`hours`)를 갖고 있다.
아래 프롬프트를 브라우저 에이전트 세션에 그대로 붙여 넣고, **오버레이 파일
[`osulloc-thehyundai-seoul-b1.json`](../../../backend/resources/store_details/osulloc-thehyundai-seoul-b1.json)의
내용도 함께 붙여** 기준값으로 쓰게 한다.

기준값 표를 여기에 베껴 두지 않는 이유: 오버레이가 단일 출처다. 두 곳에 적으면 반드시
한쪽이 먼저 썩고, 그때 재검증은 낡은 기준으로 "일치"를 보고한다.

---

더현대 서울 B1 "오설록" 매장 데이터를 공식 사이트에서 재검증한다.
너는 이 프로젝트를 모르는 상태이므로 아래 절차만 따르고, 판단이 필요한 곳은 추측하지 말고 나에게 물어라.
**기준값은 내가 함께 붙여 넣은 오버레이 JSON이다.**

## 배경 (이미 확정된 사실 — 다시 조사하지 마라, 어긋날 때만 보고)

- 이 매장은 **(주)오설록**의 **티샵(소매 매장)**이다. 티하우스가 아니고, 그 자리에서 마시는
  음료 메뉴판은 공식적으로 존재하지 않는다.
- 같은 지도 폴리곤에 표시되는 "일상다완"은 **별개 회사 쌍계명차(주)의 별도 매장**
  (02-3277-8533)이다. 이 조사 대상이 아니다. 일상다완 정보를 섞지 마라.
- 전용 지점 페이지는 없다. 매장 정보는 매장소개 페이지의 티샵 목록 안에 한 항목으로 존재한다.
  **다른 지점 페이지·블로그·기사·네이버플레이스로 대체하지 마라.**

## 지켜야 할 제약

- `alert()` / `confirm()` / `prompt()` 절대 실행 금지 — 브라우저가 멈춰 세션이 죽는다.
- **`await`/async 반환 금지** — 이 확장의 javascript 도구는 async 반환값을 `{}`로 삼킨다.
  아래 스크립트는 전부 동기다. 스크롤이 필요하면 `setTimeout` 재귀로 백그라운드 실행 후
  별도 호출로 결과를 읽어라.
- 로그인·회원가입·장바구니·결제 버튼 클릭 금지. 이미지 다운로드 금지(URL만 수집).
- 같은 동작 2~3회 실패 시 멈추고 무엇이 막혔는지 보고.
- 값을 못 찾으면 "없음"/"확인 못 함"이라고 답해라. 그럴듯한 추정으로 채우지 마라.
- 도구 출력의 `[BLOCKED: ...]`는 Chrome 도구의 개인정보 필터다(사이트 문제 아님).
  쿼리스트링이 필요 없으면 `new URL(u).origin + pathname`으로 잘라서 반환해라.

## 절차

### 1) 매장 행 재확인 — 주소·전화·영업시간

`https://www.osulloc.com/kr/ko/store-introduction` 을 열고 3~4초 기다린 뒤 실행:

```js
(() => {
  const rows = [...document.querySelectorAll('#stddTeaShop ul.place_list > li.place_item')];
  return {
    total: rows.length,
    match: rows.filter(li => /더\s*현대\s*서울/.test(li.innerText)).map(li => ({
      lines: li.innerText.split('\n').map(s => s.trim()).filter(Boolean),
      links: [...li.querySelectorAll('a')].map(a => ({ text: a.innerText.trim().slice(0, 30), href: a.href })),
    })),
  };
})()
```

- `match`가 비면: 셀렉터가 바뀐 것이다. `#stddTeaShop`이 존재하는지, 목록 컨테이너 클래스가
  무엇으로 바뀌었는지 확인해 보고하고, **행이 사라진 것인지(폐점 가능성) 구조만 바뀐 것인지** 구분해라.
- 기준값과 다른 값이 나오면 필드별로 "변경 감지: 이전 → 현재"로 보고해라.

### 2) summary 문장 존속 확인

오버레이의 `source` 주소를 열고, `summary` 문장의 앞 20자 정도를 `target`에 넣어 실행:

```js
(() => {
  const t = document.body.innerText.replace(/\s+/g, ' ');
  const target = '§오버레이 summary의 앞부분§';
  const at = t.indexOf(target);
  return { stillThere: at >= 0, sample: at >= 0 ? t.slice(at, at + 160) : t.slice(0, 160) };
})()
```

`stillThere: false`면 새 소개문 후보를 다음 기준으로 다시 수집해라 — p/h1~h4 요소, 20~300자,
쿠키·약관·개인정보·사업자·배송 문구 제외, **원문 그대로 인용 + URL**.

### 3) 링크 생존 확인

오버레이 `links`의 각 URL이 osulloc.com 푸터에 아직 있는지 확인:

```js
(() => {
  const social = /instagram|facebook|youtube|blog\.naver|smartstore|brand\.naver|x\.com|twitter|kakao|tiktok/i;
  const found = new Set();
  for (const a of document.querySelectorAll('a[href]')) {
    let u; try { u = new URL(a.href); } catch { continue; }
    if (social.test(u.href)) found.add(u.origin + u.pathname);
  }
  return [...found];
})()
```

사라진 링크는 지우지 말고 "푸터에서 제거됨"으로 표시만 해라(주소 자체는 살아 있을 수 있다).

### 4) 다음 휴점일 — 이 절차의 진짜 목적

`https://www.ehyundai.com/newPortal/NS/NS000002_L.do` (현대백화점 공지사항)에서
"휴점 안내" 최신 공지를 열어 **더현대 서울**이 포함된 날짜를 찾아라.

- 공지는 통상 전월 말에 게시된다(8월분이 7/27 게시).
- 아직 안 올라왔으면 "미게시". **요일 패턴에서 추측하지 마라 — 지점마다 날짜가 다르다.**
- 상세 URL의 seq 쿼리는 도구 필터에 가려진다. 목록 URL + 공지 제목 + 게시일로 특정해라.

### 5) hero / menu — 이 절차에서는 재조사하지 마라

`hero`는 "지점 사진 부재"가 확정된 상태다. 새 근거가 눈에 띄지 않는 한 다시 파지 마라.
단, 매장소개 페이지에 **지점별 실제 사진**이 새로 생긴 것을 발견하면(아이콘·섹션 배경 말고)
그때만 URL을 보고해라.

`menu`는 공식몰 제품으로 채워져 있고, **그쪽 수집은
[메뉴 심화 수집 프롬프트](osulloc-menu-detail-prompt.md)가 단일 출처다.** 이 절차에서는
건드리지 마라 — 여기는 낡는 값(영업시간·휴점일·링크)을 보는 자리다.

## 보고 형식

1. 필드별 표: 기준값 / 현재값 / 판정(일치·변경 감지·확인 못 함)
2. 변경 감지 항목은 근거 URL + 화면에 적힌 원문 인용
3. 다음 휴점일: 날짜 + 공지 제목 + 게시일 (미게시면 "미게시")
4. 셀렉터가 깨진 경우: 무엇이 어떻게 바뀌었는지 + 새 셀렉터 제안
5. 오버레이에 반영할 diff만 따로 정리 — **반영은 사람이 한다. 직접 수정하지 마라.**

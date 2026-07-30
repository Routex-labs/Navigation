# P3 통합 — 패션 196건 신발 취급 여부 (검증 완료)

작성일: 2026-07-30 · 조사: Sonnet 4개 조(P3-1~4) · 검증·통합: 메인 세션(Fable)

**이 표는 4개 조사 파일의 기계적 병합이며 판정·근거를 재해석하지 않았다.** 원문·미확인 사유는 각 P3-*.md 참고.

## 집계

| 구분 | 예 | 아니오 | 미확인 | 계 |
|---|---|---|---|---|
| 골프 | 10 | 2 | 0 | 12 |
| 스포츠·아웃도어 | 22 | 8 | 0 | 30 |
| 명품 | 38 | 5 | 0 | 43 |
| 캐주얼·스트리트 | 33 | 19 | 0 | 52 |
| 컨템포러리 | 42 | 17 | 0 | 59 |
| **전체** | **145** | **51** | **0** | **196** |

## 검증 기록 (메인 세션)

- 완전성: verify_p3.py — 워크시트 196행 전수 대조, 누락 0 / 초과 0 / 조 간 중복 0 / 판정값 이상 0
- 표본 사실 검증(브라우저 직접 확인): 에르노 예(herno.com Shoes 카테고리 실재), 불가리 아니오(공식 제품군에 신발 없음), 타이틀리스트 아니오(신발은 동일 모기업 풋조이 전담), 쿠어 예(coor.kr SHOES 카테고리·무신사 더비 슈즈 실물) — 4건 모두 원판정과 일치
- 오분류 신규 3건(바이리네·에이스 프리미엄 스토어·프롤라): 더현대 서울 공식 층별 안내(4F)에서 각각 가구·침구(2)·카페(1) 섹션 등재를 직접 확인 — 주장 사실
- P3-2가 예상 함정 5건(주얼리 하우스 3·리모와·스킨 케어룸)을 전부 아니오로 걸러냄 — 프롬프트 함정 통과

## 2차 재분류 (2026-07-30) — 미확인 41건 해소

사용자 지시에 따라 유형별 규칙으로 미확인을 전부 해소했다.

| 유형 | 규칙 | 건수 → 결과 |
|---|---|---|
| A 브랜드 특정 실패 8건 | 브라우저 크롤링(구글 AI 요약 적극 참고)으로 브랜드 특정 후 판정 | 예 5(PEER·시에·아뜰리에 디 갤럭시·프레이트·스컬프) / 아니오 3(세터·노이스·더치랩) |
| B 의류·잡화 전문 22건 | 신발 카테고리 부재가 확인된 의류 전문 브랜드는 아니오로 일괄 | 아니오 21 / 예 1(노매뉴얼 코이세이오 — 병기 브랜드가 신발 취급) |
| C 상시성 불확실 5건 | 범용(브랜드 차원) 판정 — 매장별 세부 상시성은 추후 디테일 작업에서 | 예 5 |
| D 매장 성격 미상 6건 | 브라우저 크롤링으로 매장 성격 직접 확인 | 예 3(SJSJ·시스템 옴므·타임 — 더한섬닷컴 실물) / 아니오 3(시리즈 코너·뉴마핏·티노5) |

부수 발견: **더치랩은 콜드브루 카페였다**(패션/캐주얼·스트리트로 오분류). P4에 21번째
항목으로 추가해 `store_category_by_name.json`을 수정하고 재시딩했다.

## 전체 표 (판정순: 예 → 미확인 → 아니오)

| store_id | 매장명 | subcategory | 판정 | 신발 종류 | 근거 | 비고 | 출처 파일 |
|---|---|---|---|---|---|---|---|
| PO-gfyEtBflu5678 | A.P.C 골프 | 골프 | 예 | 스니커즈(런어라운드/플레인/이기 등) | apcstore.com/collections/a-p-c-golf, ssfshop.com(A.P.C 운동화/스니커즈 카테고리) — "A.P.C. Golf"는 2021년 론칭한 컬렉션으로 스니커즈 라인 존재 |  | P3-1-golf-sports.md |
| PO-APkl7L6cM9301 | PXG | 골프 | 예 | 골프화 | pxg.com/collections/golf-shoes — PXG x Cole Haan 골프화 컬렉션, pxg.co.kr 골프화 프로모션 페이지 |  | P3-1-golf-sports.md |
| PO-TDa0KLOzE0998 | 나이키 골프 | 골프 | 예 | 골프화 | nike.com/kr/ko_kr/w/xg/fw/golf/dual-golf-shoes — 나이키 코리아 공식 골프 신발 카테고리 |  | P3-1-golf-sports.md |
| PO-lGqimRJiO8502 | 말본 골프 | 골프 | 예 | 골프화(스파이크리스), 어디다스 삼바·뉴발란스 550 협업 골프화 | malbon.com/collections/footwear — Malbon Course Spikeless Golf Shoes, Malbon x adidas Samba, NB550 협업 |  | P3-1-golf-sports.md |
| PO-GrmYNs0Pi7413 | 보스 골프 | 골프 | 예 | 골프화 | hugoboss.com/us/v/men-s-golf-shoes — BOSS 공식 "Exclusive Men's Golf Shoes" 카테고리 |  | P3-1-golf-sports.md |
| PO-2-uZgke9R2862 | 세인트 앤드류스 | 골프 | 예 | 골프화 | ssfshop.com/StANDREWS/GLF (WebFetch로 확인) — 좌측 메뉴에 "여성 골프슈즈"·"남성 골프슈즈" 카테고리 존재, "미니 태슬 클래식 스파이크리스 골프화" 상품 확인 |  | P3-1-golf-sports.md |
| PO-BVFEo9nBx9677 | 제이린드 버그 | 골프 | 예 | 골프화(ECCO 협업 하이탑 골프화 등) | 검색 결과(신세계V·SSG 등)에서 J.Lindeberg x ECCO 하이탑 골프화 확인 |  | P3-1-golf-sports.md |
| PO--vxokM-qD4687 | 지포어 | 골프 | 예 | 골프화(스니커즈형) | gfore.kr/Category/List/506010030000 — 지포어 공식 "골프화" 카테고리, 남녀 모델 다수 |  | P3-1-golf-sports.md |
| PO-W6d_iRp_m9917 | 캘러 웨이 | 골프 | 예 | 골프화 | kr.callawaygolf.com/kr/Callaway/.../골프화/c/0436 — 캘러웨이골프 코리아 공식 "골프화" 카테고리 |  | P3-1-golf-sports.md |
| PO-IkD1Ivlvg5669 | 풋 조이 | 골프 | 예 | 골프화(브랜드 정체성 자체가 골프화) | footjoy.co.kr/Catalog/Category/5 — "The #1 Shoe and Glove in Golf", FJ FLEX/PRO SL/DRYJOYS TOUR 등 다수 모델 |  | P3-1-golf-sports.md |
| PO-_iv3c2Zbw6579 | MSGM | 명품 | 예 | 스니커즈, 샌들 | shop-msgm.com/en/accessories/shoes/ (브랜드 공식몰 Shoes 카테고리) |  | P3-2-luxury.md |
| PO-TE4QTaUXw1942 | 겐조 | 명품 | 예 | 스니커즈, 샌들 | kenzo.com/en-us/shoes (공식 사이트 Shoes 섹션) |  | P3-2-luxury.md |
| PO-nkTkSy3st5151 | 구찌 | 명품 | 예 | 스니커즈, 로퍼, 부츠 | gucci.com 공식 사이트 Shoes 카테고리 (잘 알려진 슈즈 라인) |  | P3-2-luxury.md |
| PO-ui14WwvfK3350 | 꼼데가르송 (포켓/남성 컬렉션) | 명품 | 예 | 스니커즈(CDG PLAY×컨버스 등) | comme-des-garcons.us, ssense.com CDG Homme/PLAY shoes 카테고리 확인 | 매장 단위(포켓/남성 컬렉션) 실제 취급 여부는 미확인 — 브랜드 자체는 슈즈 라인 있음 | P3-2-luxury.md |
| PO-Xh3swMMuU5813 | 드롤드무슈 | 명품 | 예 | 로퍼, 보트슈즈 | droledemonsieur.com/collections/chaussures (공식몰 Chaussures 카테고리) |  | P3-2-luxury.md |
| PO-31q8LPA9B4429 | 랑방 컬렉션 | 명품 | 예 | 스니커즈(커브 등) | lanvin.com/kr/shop/men/men-sneakers (공식 사이트 men-sneakers 카테고리) |  | P3-2-luxury.md |
| PO-zSLxgiZPp0753 | 레페토 | 명품 | 예 | 발레슈즈 | 브랜드 자체가 발레슈즈 전문 브랜드(공지 사실) | 슈즈가 곧 본업인 브랜드 | P3-2-luxury.md |
| PO-iK68VYKov8809 | 로에베 | 명품 | 예 | 스니커즈, 로퍼 | loewe.com 공식 사이트 Shoes 카테고리 (잘 알려진 슈즈 라인) |  | P3-2-luxury.md |
| PO-H9EW5K6NS2833 | 루이비통 | 명품 | 예 | 스니커즈, 로퍼, 부츠 | louisvuitton.com 공식 사이트 Shoes 카테고리 |  | P3-2-luxury.md |
| PO-a7gO8V5NY0079 | 루이비통(남) | 명품 | 예 | 스니커즈, 로퍼 등(남성) | 브랜드 남성 슈즈 라인 존재(louisvuitton.com Men Shoes) | 남성 전용 매장 — 실제 매장 취급 라인업은 매장 단위 미확인 | P3-2-luxury.md |
| PO-1loJl6otu4732 | 르메르 (남/여) | 명품 | 예 | 슬리퍼, 부츠, 데르비, 뮬, 샌들 | lemaire.fr/collections/shoes (공식몰 Shoes 카테고리) |  | P3-2-luxury.md |
| PO-H35ljeM_59108 | 막스마라 | 명품 | 예 | 스니커즈, 로퍼, 부츠, 플랫 | us.maxmara.com/v/shoes-adult (공식 사이트 Shoes 카테고리) |  | P3-2-luxury.md |
| PO-CpwdaRU5u7397 | 메종 마르지엘라 (남/여) | 명품 | 예 | 타비 슈즈, 스니커즈 | maisonmargiela.com 공식 사이트(대표 상품 Tabi 슈즈로 잘 알려짐) |  | P3-2-luxury.md |
| PO-EV4vdN0TF0597 | 메종 미하라 야스히로 | 명품 | 예 | 스니커즈(핸드메이드 소울 특유 디자인) | 브랜드 자체가 스니커즈 중심 디자이너 브랜드로 유명(공식 인지도) |  | P3-2-luxury.md |
| PO-AZP5VspPq4681 | 몽클레르 | 명품 | 예 | 스니커즈, 트레이너 | moncler.com/ko-kr/men/shoes, /women/shoes (공식 사이트 Shoes 카테고리) |  | P3-2-luxury.md |
| PO-Hv4mlJ2HD6901 | 무이 (남/여) | 명품 | 예 | 플랫(허스플랫), 부츠 등 | mui.kr 공식 온라인 스토어에 신발 카테고리(허스플랫·달부츠 등) 확인 | 한섬 운영 편집숍 — 입점 브랜드 구성에 따라 매장별 취급 편차 가능 | P3-2-luxury.md |
| PO-XE5AyvOY-6217 | 발렌시아가 | 명품 | 예 | 스니커즈(트리플S 등), 부츠 | balenciaga.com 공식 사이트 Shoes 카테고리 (잘 알려진 스니커즈 라인) |  | P3-2-luxury.md |
| PO-VUPb_mowY7218 | 발렌티노 | 명품 | 예 | 스니커즈, 로퍼, 펌프스 | valentino.com 공식 사이트 Shoes 카테고리 |  | P3-2-luxury.md |
| PO-QBYQxxAAR6145 | 버버리 | 명품 | 예 | 스니커즈, 부츠, 로퍼 | burberry.com 공식 사이트 Shoes 카테고리 |  | P3-2-luxury.md |
| PO-Nmycfl6kW6313 | 보테가 베네타 | 명품 | 예 | 스니커즈, 로퍼, 부츠 | bottegaveneta.com 공식 사이트 Shoes 카테고리 |  | P3-2-luxury.md |
| PO-xVTcQys5A8977 | 셀린느 | 명품 | 예 | 스니커즈, 로퍼, 부츠 | celine.com 공식 사이트 Shoes 카테고리 |  | P3-2-luxury.md |
| PO-biOOVQyvP9149 | 아미 (남/여) | 명품 | 예 | 스니커즈(로고 스니커즈 등) | amiparis.com 공식 사이트 Shoes 카테고리, 로고 스니커즈로 널리 알려짐 |  | P3-2-luxury.md |
| PO-WH7hAmW6m3061 | 아워레가시 | 명품 | 예 | 스니커즈(로우탑 등) | ourlegacy.com 공식몰 Shoes 카테고리, ssense.com Our Legacy shoes/sneakers 카테고리 확인 |  | P3-2-luxury.md |
| PO-Pvt_3L48G8867 | 아크네 스튜디오 | 명품 | 예 | 스니커즈, 부츠, 로퍼 | acnestudios.com 공식 사이트 Shoes 카테고리 |  | P3-2-luxury.md |
| PO-9ncQHVhkS3745 | 언더커버 | 명품 | 예 | 스니커즈(Nike 콜라보 다수) | Nike×UNDERCOVER 협업(SFB Jungle Dunk, Daybreak 등) 다수 확인, undercoverism.com 공식 사이트 |  | P3-2-luxury.md |
| PO-zYc1D3G4b4976 | 에르노 | 명품 | 예 | 스니커즈, 로퍼 | us.herno.com/en/men/accessories/shoes/, /en/women/accessories/shoes/ (공식 사이트 Shoes 카테고리) |  | P3-2-luxury.md |
| PO-c7yr7je5B8606 | 옴므플리세 | 명품 | 예 | 스니커즈(BREEZE, CIOCCOLATO 등) | us.isseymiyake.com/collections/hommeplisse/shoes (공식몰 Shoes 카테고리) |  | P3-2-luxury.md |
| PO-G8TOkvvqk6950 | 우영미 | 명품 | 예 | 스니커즈(하이탑 등) | wooyoungmi.com 공식몰 슈즈 카테고리(블랙 하이탑/레더 스니커즈 등) |  | P3-2-luxury.md |
| PO-n52t1CLzq9021 | 이자벨마랑 (남/여) | 명품 | 예 | 스니커즈(웻지 스니커즈로 유명), 부츠 | isabelmarant.com 공식 사이트 Shoes 카테고리, 웻지 스니커즈로 널리 알려짐 |  | P3-2-luxury.md |
| PO-l6joiTP_I2101 | 일레븐티 | 명품 | 예 | 스니커즈 | eleventymilano.com/collections/men-shoes, mens-sneakers (공식 사이트 Shoes 카테고리) |  | P3-2-luxury.md |
| PO-ycohmIvZf5120 | 크리스챤 디올 (남/여) | 명품 | 예 | 스니커즈(B23 등), 로퍼 | dior.com 공식 사이트 Shoes 카테고리 |  | P3-2-luxury.md |
| PO-Ek5WaJIDm4448 | 토즈 | 명품 | 예 | 드라이빙 슈즈(고무 알갱이 밑창 대표작), 로퍼 | 브랜드 자체가 드라이빙 슈즈로 유명(tods.com) |  | P3-2-luxury.md |
| PO-pls3REc8x5545 | 토템 | 명품 | 예 | 로퍼, 부츠, 샌들 | toteme.com/totemeofficial.shop 공식몰 Shoes 카테고리 |  | P3-2-luxury.md |
| PO-nwmgi9vgb5269 | 페라가모 | 명품 | 예 | 구두, 로퍼(비바라 등) | 브랜드가 구두 장인으로 시작한 하우스(ferragamo.com) |  | P3-2-luxury.md |
| PO-HO4Szxple8130 | 펜디 | 명품 | 예 | 스니커즈, 로퍼, 부츠 | fendi.com 공식 사이트 Shoes 카테고리 |  | P3-2-luxury.md |
| PO-zo0B7h0Ci1073 | 프라다 | 명품 | 예 | 스니커즈(카본화이버 등), 로퍼 | prada.com 공식 사이트 Shoes 카테고리 |  | P3-2-luxury.md |
| PO-NUdsiSuRv1656 | 프라다(남) | 명품 | 예 | 스니커즈, 로퍼(남성) | prada.com 공식 사이트 Men Shoes 카테고리 | 남성 전용 매장 — 매장 단위 실제 취급 라인업은 미확인 | P3-2-luxury.md |
| PO-HDFy4w1c-5856 | 플리츠 플리즈 | 명품 | 예 | 니트 샌들, 스니커즈(Native Shoes 콜라보) | us.isseymiyake.com Pleats Please 슈즈, Native Shoes와의 콜라보 스니커즈 확인 |  | P3-2-luxury.md |
| PO-LfGRRshKl9637 | EQL 퍼포먼스 | 스포츠·아웃도어 | 예 | 러닝화/트레일화(멀티브랜드 편집숍) | biz.newdaily.co.kr(2026-03-17) — 한섬이 더현대서울 4F에 연 '스포츠 브랜드 전문관 EQL 퍼포먼스 클럽'. 호카·브룩스·아크테릭스·아식스·골드윈·오클리 등 30여 브랜드 300여 상품 큐레이션, 미즈노 웨이브 프로페시·비브람 파이브핑거스·호카 마파테 등 신발 상품 구체적으로 확인 |  | P3-1-golf-sports.md |
| PO-N0E3DIPVo9709 | 굿러너 컴퍼니 | 스포츠·아웃도어 | 예 | 러닝화(로드/트레일) | goodrunner.co.kr — "신발" 카테고리에 로드데일리·로드레이싱·리커버리·스피드·안정화·트레일러닝화 세분류 존재 |  | P3-1-golf-sports.md |
| PO-M9yQR3lc-2318 | 나이키스윔 | 스포츠·아웃도어 | 예 | 아쿠아슈즈 | nike.com/kr/w/swimming-3c2dj — AQUA TURF, WMNS AIR RIFT 아쿠아 샌들 등 확인 |  | P3-1-golf-sports.md |
| PO-_53mYSXmI7726 | 노스페이스 | 스포츠·아웃도어 | 예 | 등산화/트레일러닝화/운동화 | thenorthfacekorea.co.kr/category/n/shoes — 등산화·트레일러닝·러닝슈즈·스니커즈 카테고리 존재 |  | P3-1-golf-sports.md |
| PO-jdv1lCgc98262 | 라코스테 | 스포츠·아웃도어 | 예 | 스니커즈(클럽 로우, 헤리티지 L-001 등) | lacoste.com/kr/lacoste/sports/스포츠-전체/신발 — 공식 신발 카테고리 |  | P3-1-golf-sports.md |
| PO-Uspea_hn_4367 | 랑방 블랑 | 스포츠·아웃도어 | 예 | 골프화 | thehandsome.com(더한섬) LANVIN BLANC 상품 — "로고 벨크로 스트랩 골프화" 478,000원 판매 확인 |  | P3-1-golf-sports.md |
| PO-fMbhJAO4W2858 | 룰루레몬 | 스포츠·아웃도어 | 예 | 트레일러닝화/캐주얼 스니커즈(cityverse) | lululemon.co.kr, shop.lululemon.com/c/shoes — Beyond Feel 트레일러닝화, Cityverse 운동화 등 |  | P3-1-golf-sports.md |
| PO-W1YSw1lv44048 | 몽벨 | 스포츠·아웃도어 | 예 | 등산화/트레킹화 | montbell.co.kr, musinsa.com/brand/montbell — 등산화·트레킹화 다수 확인 |  | P3-1-golf-sports.md |
| PO-7Qb38rPHg6679 | 빈폴 | 스포츠·아웃도어 | 예 | 트레킹화/스니커즈 | gsshop.com, danawa.com — 빈폴 고어텍스 트레킹화, 리넨혼방 메시 스니커즈 등 |  | P3-1-golf-sports.md |
| PO-pFFnUKmqH3103 | 사우스 케이프 | 스포츠·아웃도어 | 예 | 골프화 포함 신발 | southcape.shop(공식몰) — "골프웨어, 라이프웨어, 캐디백, 신발, 양말" 취급 명시 |  | P3-1-golf-sports.md |
| PO-6ZhBBpOMW2557 | 살로몬 | 스포츠·아웃도어 | 예 | 트레일러닝화(XT-6, X 울트라 등) | salomon.co.kr/collections/men-신발-트레일러닝 |  | P3-1-golf-sports.md |
| PO-23d6LuNUd9797 | 스노우 피크 | 스포츠·아웃도어 | 예 | 신발(아웃도어 어패럴 콘셉트) | snowpeakstore.co.kr — "내추럴 아웃도어 어패럴" 콘셉트로 의류·용품·신발 판매 명시 |  | P3-1-golf-sports.md |
| PO-2ndzDVZOk2281 | 시에라 디자인 | 스포츠·아웃도어 | 예 | 신발(Footwear 라인) | sierra-designs.co.kr, sierradesigns.com — 제품 카테고리에 Footwear(신발) 존재 확인 |  | P3-1-golf-sports.md |
| PO-Rg3U2RiuL0359 | 아레나 | 스포츠·아웃도어 | 예 | 아쿠아슈즈 | arena.co.kr/category/아쿠아-슈즈 — 공식 아쿠아슈즈 카테고리 |  | P3-1-golf-sports.md |
| PO-tn9HeceFV0326 | 아크 테릭스 | 스포츠·아웃도어 | 예 | 신발(버텍스 알파인, 크라그 등) | arcteryx.co.kr/products/category/65 — 공식 신발 카테고리, 2024년부터 자체 기술 신발 라인 출시 |  | P3-1-golf-sports.md |
| PO-p6DLw3jtQ2070 | 안다르 | 스포츠·아웃도어 | 예 | 스니커즈 | andar.co.kr, namu.wiki/w/안다르 — "레깅스에서 아우터·스니커즈·언더웨어로 제품군 확장"이라 명시 |  | P3-1-golf-sports.md |
| PO-rFDaJaDIa4981 | 알로 | 스포츠·아웃도어 | 예 | 스니커즈/슬라이드 | aloyoga.com/collections/shoes, /pages/sneakers — 공식 신발 카테고리 |  | P3-1-golf-sports.md |
| PO-eUB-KS7sE0551 | 온 | 스포츠·아웃도어 | 예 | 러닝화(Cloudmonster 등) | on.com/ko-kr/shop/shoes — 공식 러닝화 카테고리 |  | P3-1-golf-sports.md |
| PO-gNcWYBF5q1838 | 윌슨 | 스포츠·아웃도어 | 예 | 테니스화/골프화/트레이닝화 | kr.wilson.com — 남녀 테니스화, 골프화, 트레이닝화 카테고리 다수 |  | P3-1-golf-sports.md |
| PO-Siw3WYPVQ9545 | 파타고니아 | 스포츠·아웃도어 | 예 | 신발(레더 슈즈, 방수 부츠 등) | patagonia.co.kr, musinsa.com/brand/patagonia — 룰루 레더 슈즈, 스노우 드리프터 방수 부츠 등 |  | P3-1-golf-sports.md |
| PO-Aa0o4lTmG6390 | 포스엘리먼트 | 스포츠·아웃도어 | 예 | 다이빙 부츠 | fourthelement.kr/category/부츠 — 페라직 부츠, 앰피비언 부츠 등 다이빙용 부츠 카테고리 존재(신발 종류가 일반 운동화는 아니고 다이빙 부츠) |  | P3-1-golf-sports.md |
| PO-A6Im4S9HB0376 | 헤지스 | 스포츠·아웃도어 | 예 | 스니커즈(ID.EIGHT 협업 포함) | musinsa.com/brand/hazzys1, namu.wiki/w/헤지스 — "의류뿐 아니라 스니커즈·운동화 제공", 이탈리아 친환경 슈즈 브랜드 ID.EIGHT와 협업 확인 |  | P3-1-golf-sports.md |
| PO-Dx9wnBQOy0851 | AAPE | 캐주얼·스트리트 | 예 | 슬립온/스니커즈 | bape.com·무신사: "AAPE SLIP ON" 판매 확인, kr.bape.com/collections/aape | BAPE 세컨드 라인. AAPE x DC Shoes 콜라보 이력도 있음 | P3-3-casual.md |
| PO-qYAe5JHV66239 | ARKET | 캐주얼·스트리트 | 예 | 스니커즈 등 남녀 슈즈 | arket.com/ko-kr 공식몰: men/shoes.html, women 슈즈 섹션이 상시 카테고리로 존재 | H&M그룹 라이프스타일 브랜드, 슈즈가 상설 카테고리 | P3-3-casual.md |
| PO-KQV9Pj3CK4915 | CK 진 | 캐주얼·스트리트 | 예 | 스니커즈 | 무신사 브랜드관(calvinkleinjeans): "Malmo Meta Sneakers" 판매·사은품 프로모션 확인 | Calvin Klein Jeans는 이너웨어 라인과 별개로 신발 취급 | P3-3-casual.md |
| PO-vdysvdbRH3543 | EQL | 캐주얼·스트리트 | 예 | 편집숍 내 각종 신발(ASICS 등) | 한섬 EQL 공식몰(eqlstore.com), 아이즈매거진: EQL 성수점에 ASICS 등 신발 브랜드 입점 확인 | 편집숍 — 입점 브랜드 변동. 같은 이름 2건 모두 동일 판정 | P3-3-casual.md |
| PO-k2OxX57KO3354 | EQL | 캐주얼·스트리트 | 예 | 편집숍 내 각종 신발(ASICS 등) | 상동(한섬 EQL 공식몰·아이즈매거진) | 편집숍 — 입점 브랜드 변동. 같은 이름 2건 모두 동일 판정 | P3-3-casual.md |
| PO-dLxzve5dF8972 | MLB | 캐주얼·스트리트 | 예 | 러닝화/스니커즈 | MLB 공식몰(mlb-korea.com/display/MBMB04) "MLB 신발" 카테고리 상시 존재 | 볼캡과 함께 신발이 브랜드 핵심 라인 중 하나 | P3-3-casual.md |
| PO-Lds1P-J538085 | R13 | 캐주얼·스트리트 | 예 | 하이탑/로우탑 스니커즈 | r13.com 공식몰: "Men's Shoes", "Sneakers" 컬렉션 상시 존재 | 뉴욕 데님 브랜드, 슈즈가 상설 라인 | P3-3-casual.md |
| PO-PuwcCDf_o4147 | THISIS NEVERTHAT | 캐주얼·스트리트 | 예 | 스니커즈 | 컨버스 공식몰(converse.co.kr/limited/thisisneverthat.html) 콜라보 상설 페이지 확인 | 컨버스와 상시 협업 라인 운영 | P3-3-casual.md |
| PO-7ROWrtJLA5608 | Y-3 | 캐주얼·스트리트 | 예 | 하이탑 스니커즈 등 | adidas.com/us/y_3-shoes, adidas 공식 Y-3 슈즈 컬렉션 | 아디다스×요지 야마모토 협업 브랜드, 신발이 핵심 제품군 | P3-3-casual.md |
| PO-L-broLeRG1775 | 나이키 라이즈 | 캐주얼·스트리트 | 예 | 운동화 전반(나이키 전 카테고리) | 나이키 공식(nike.com/kr/retail/s/nike-the-hyundai-seoul): "신발을 포함한 나이키 제품 판매" 명시 | 이번 조사의 핵심 대상. 소분류상 캐주얼·스트리트지만 실질은 나이키 신발 매장 | P3-3-casual.md |
| PO-ZjxLyznQe3220 | 노스페이스 화이트 라벨 | 캐주얼·스트리트 | 예 | 라이프스타일 스니커즈(클리프 로우 등) | 노스페이스 공식몰(thenorthfacekorea.co.kr/whitelabel, 뉴스1 보도): "클리프 로우 스니커즈" 정식 출시 확인 | 화이트라벨 자체 신발 라인 존재 | P3-3-casual.md |
| PO-UnpCQYHay7593 | 뉴발란스 | 캐주얼·스트리트 | 예 | 운동화 전반 | 더현대 서울 공식 층별 안내 + nbkorea.com: 뉴발란스는 신발 브랜드 자체 | 이번 조사의 핵심 대상 중 하나 | P3-3-casual.md |
| PO-teOVE4J-C7815 | 레이브 | 캐주얼·스트리트 | 예 | 메시 스니커즈 | 무신사: "레이브(RAIVE) Ciel Mesh Sneakers in Blue" 실제 판매 상품 확인 | 스니커즈 상품 직접 확인됨 | P3-3-casual.md |
| PO-YnKvUx7uJ1536 | 루에브르 | 캐주얼·스트리트 | 예 | 신발(구체 종류 미상) | 무신사 브랜드 소개: "남성·여성 의류, 가방, 주얼리, 신발, 악세서리 등을 판매" 명시 | 신발이 상시 취급 카테고리로 공식 소개됨 | P3-3-casual.md |
| PO-tcTT2WTnf9751 | 베이프 | 캐주얼·스트리트 | 예 | 스니커즈(BAPE STA 등) | 하입비스트·threads(bape_korea): 더현대 서울 2F 신규 매장 오픈 기념 컬렉션에 "베이프 스타 스니커" 포함 확인 | 2025년 12월 더현대 서울 2층 신규 오픈, 워크시트 층 표기(2F)와 일치 | P3-3-casual.md |
| PO-HjOkHzgBc4589 | 스톤아일랜드 | 캐주얼·스트리트 | 예 | 트레이너/스니커즈 | stoneisland.com/ko-kr/collection/슈즈: "남성 슈즈: 트레이너 및 스니커즈" 공식 컬렉션 페이지 확인 | 뉴발란스와의 협업(998) 등 신발 라인 다수 | P3-3-casual.md |
| PO-ipPhp9BE-0864 | 아디다스 스타디움 | 캐주얼·스트리트 | 예 | 스포츠화 전반 | 더현대 서울 공식 층별 안내 + adidas.co.kr 매장안내: 아디다스 신발 포함 스포츠 슈즈·의류 판매 확인 | 이번 조사의 핵심 대상 중 하나 | P3-3-casual.md |
| PO-W_PnYNZl-2259 | 오픈 Yy | 캐주얼·스트리트 | 예 | 신발(공식 SHOES 카테고리) | 공식몰 open-yy.com/category/shoes 상시 카테고리 확인, PUMA×OPENYY 콜라보 판매 확인 | 의류·가방과 함께 신발이 상설 카테고리 | P3-3-casual.md |
| PO-aJHzOKva38360 | 유니폼 브릿지 | 캐주얼·스트리트 | 예 | 스니커즈(구체 모델 미상) | 무신사(uniformbridge): 브랜드관 내 스니커즈·신발 카테고리 상품 존재 확인 | 밀리터리·아웃도어 감성 브랜드, 신발 라인 보유 | P3-3-casual.md |
| PO-Yksk22uUp5472 | 칼하트윕 | 캐주얼·스트리트 | 예 | 신발(구체 종류 미상) | 롤스트릿·렉스몬드 등 국내 셀렉샵에서 "칼하트 WIP 신발" 정품 판매 확인 | 의류가 메인이나 신발도 유통 확인됨 | P3-3-casual.md |
| PO-ftc9SLVZo8560 | 코닥 x 디오디 | 캐주얼·스트리트 | 예 | 스니커즈/샌들 | 무신사(KODAK): "코닥 신발 제품 8개 등록", G마켓 코닥어패럴 신발 카테고리 확인 | 카메라 브랜드의 라이선스 어패럴로, 신발 라인이 실제 존재 | P3-3-casual.md |
| PO-Y8cgBiGdJ9704 | 코이세이오 | 캐주얼·스트리트 | 예 | 신발(구체 종류 미상) | tnnews·공식 판매처(무신사, EQL, 29CM, KREAM, W컨셉) 소개에서 "신발 등"을 취급 상품으로 명시 | 여성 스트리트 브랜드, 신발 포함 상품군 확인 | P3-3-casual.md |
| PO-Vi9px-Ien6731 | 쿠어 | 캐주얼·스트리트 | 예 | 신발(구체 종류 미상) | 무신사(COOR) 브랜드 소개: "상의, 아우터, 바지, 가방, 신발, 액세서리 등" 취급 카테고리 명시 | 신발이 공식 취급 카테고리로 명시됨 | P3-3-casual.md |
| PO-6xhUatzjG6902 | 폴리테루 | 캐주얼·스트리트 | 예 | 신발(구체 종류 미상) | polyteru-store.com·KREAM 브랜드 소개: "clothing, shoes, bags, and accessories" 취급 카테고리 명시 | 신발이 공식 취급 카테고리로 명시됨 | P3-3-casual.md |
| PO-HQN0W3vFY3620 | 피어오브갓 | 캐주얼·스트리트 | 예 | 스니커즈/로퍼 | fearofgod.com/collections/fearofgod-footwear 공식 풋웨어 컬렉션, adidas.co.kr/fear_of_god_athletics | Fear of God Athletics(아디다스 협업)까지 포함해 신발이 핵심 라인 | P3-3-casual.md |
| PO-SXt4j4rTI9143 | A.P.C. | 컨템포러리 | 예 | 스니커즈 | musinsa.com/brand/apc, ssfshop.com A.P.C. Women-Shoes — Plain Sneakers·Run Around Sneakers 등 다수 확인 |  | P3-4-contemporary.md |
| PO-WDK8RFysN1431 | CP컴퍼니 | 컨템포러리 | 예 | 스니커즈 | namu.wiki "C.P. 컴퍼니"(신발 포함 제품군 명시), cpcompany.com — adidas·Clarks와 신발 콜라보 이력 |  | P3-4-contemporary.md |
| PO-IQObxvbrF9918 | DKNY | 컨템포러리 | 예 | 스니커즈/플랫/힐/부츠 | dkny.com/collections/shoes(공식 Shoes 컬렉션), ssfshop.com DKNY Women-Shoes |  | P3-4-contemporary.md |
| PO-oR__leLTv1263 | 가니 | 컨템포러리 | 예 | 플랫슈즈(발레리나) | jentestore.com — GANNI 보우 장식 발레리나 플랫 슈즈(S2755099) 확인 |  | P3-4-contemporary.md |
| PO-PB0WBeLVx9344 | 구호 | 컨템포러리 | 예 | 스니커즈/메리제인/샌들/힐 | newsis.com·apparelnews.co.kr "삼성물산 패션 '구호', 여름 신발 컬렉션 선봬" 기사, ssfshop.com KUHO |  | P3-4-contemporary.md |
| PO-q2fQVxc717780 | 듀베티카 | 컨템포러리 | 예 | 유니섹스 슈즈 | duvetica.co.kr 공식몰 OUTLET-ACC-슈즈 카테고리, musinsa.com — Erta 모델(남녀공용 신발) 확인 |  | P3-4-contemporary.md |
| PO-jzdvRWUJa2343 | 띠어리 | 컨템포러리 | 예 | 슈즈 | ssfshop.com Theory, sivillage.com — "Theory는 의류뿐만 아니라 신발(슈즈) 상품도 판매" |  | P3-4-contemporary.md |
| PO-Nk-vj_Uti5758 | 리던 | 컨템포러리 | 예 | 스니커즈/부츠 | shopredone.com/collections/shoes(공식 Shoes 카테고리: Cavalry Boot·70s Tennis Shoe 등), fashionseoul.com — 첫 여성 스니커즈 컬렉션 기사 |  | P3-4-contemporary.md |
| PO-GcBj_dP-v6488 | 마인 | 컨템포러리 | 예 | 플랫슈즈/샌들 | thehandsome.com MINE — 가죽 스트랩 플랫슈즈·샌들 확인 | 한섬 브랜드 | P3-4-contemporary.md |
| PO-7i9sjAh267389 | 마쥬 | 컨템포러리 | 예 | 슈즈(스니커즈 등) | maje.kr 공식몰 신발(SALE-슈즈) 카테고리 확인 |  | P3-4-contemporary.md |
| PO-L3u216oYd2193 | 메종키츠네 (남/여) | 컨템포러리 | 예 | 스니커즈 | maisonkitsune.com/kr 남성/여성 스니커즈·슈즈 카테고리(공식) |  | P3-4-contemporary.md |
| PO-aAGSgU0Nw4525 | 모드맨 | 컨템포러리 | 예 | 부츠/모카신(편집숍) | mode-man.com — 데님 전문 편집숍이나 취급 브랜드 목록에 Viberg(부츠)·Yuketen(모카신) 등 신발 브랜드 포함 확인 | 편집숍 | P3-4-contemporary.md |
| PO-7fAC1zcRT7649 | 미우미우 | 컨템포러리 | 예 | 플랫슈즈/구두 | musinsa.com — 레더 발레리나 플랫 슈즈 등 다수, miumiu.com 공식 |  | P3-4-contemporary.md |
| PO-71v3YdFIW4817 | 바네사 브루노 | 컨템포러리 | 예 | 뮬/샌들/웨스턴부츠/스니커즈 | musinsa.com "ATHE VANESSABRUNO SHOES" 전용 슈즈 라인 다수 확인 |  | P3-4-contemporary.md |
| PO-4hXOXegKk8112 | 바버 | 컨템포러리 | 예 | 부츠(웰링턴 등) | ssfshop.com Barbour Women-Shoes, kream.co.kr/brands/Barbour — 웰링턴/레인부츠 확인 |  | P3-4-contemporary.md |
| PO-U5QKiaEVq6719 | 버윅 | 컨템포러리 | 예 | 구두/로퍼/부츠 | cappellettoshop.com, theworldofshoes.com 등 — 스페인 Goodyear welted 구두 전문 브랜드(공식 확인) | 명확한 예 후보 | P3-4-contemporary.md |
| PO-dM7m4oYCb3087 | 베로니카 비어드 | 컨템포러리 | 예 | 펌프스/로퍼/부티 | neimanmarcus.com Veronica Beard Shoes 카테고리 확인 |  | P3-4-contemporary.md |
| PO-_Ae_R_q5X8880 | 벨벳트렁크 | 컨템포러리 | 예 | 프리미엄 슈즈(편집숍) | apparelnews.co.kr "성수동 '벨벳트렁크'" — 압구정 편집숍 에크루 + 슈즈 편집숍 카시나가 공동 운영, 프리미엄 슈즈 명시 | 편집숍 | P3-4-contemporary.md |
| PO-4QSeJedrN3475 | 비이커 | 컨템포러리 | 예 | 스니커즈 등(편집숍) | ssfshop.com/beaker — 삼성물산 편집숍, 신발/스니커즈 판매 확인 | 편집숍 | P3-4-contemporary.md |
| PO-dQvU1ADwX6748 | 산드로 | 컨템포러리 | 예 | 더비슈즈 | sandro.kr 공식몰 — 레이스업 레더 더비 슈즈, 소가죽 더비 슈즈 확인 |  | P3-4-contemporary.md |
| PO-kb4ieBLBd1879 | 솔리드 옴므 | 컨템포러리 | 예 | 더비/로퍼/보트슈즈/스니커즈/첼시부츠 | solidhomme.com 공식몰 "신발" 카테고리 확인 |  | P3-4-contemporary.md |
| PO-33oz1_ryf4861 | 송지오 | 컨템포러리 | 예 | 스니커즈/구두 | songzio.com — SHOP-SNEAKERS, BAG AND SHOES 카테고리(공식) 확인 |  | P3-4-contemporary.md |
| PO-6ahlys8bs7104 | 수트 서플라이 | 컨템포러리 | 예 | 로퍼/스니커즈/슬립온 | ssfshop.com SUITSUPPLY — 스웨이드 슬립온, 카프레더 플랫 로퍼, 메쉬 레더 레이싱 스니커즈 확인 | 워크시트가 지정한 확인 대상 | P3-4-contemporary.md |
| PO-7jryGoGrj2027 | 시스템 | 컨템포러리 | 예 | 남성슈즈/여성슈즈 | thehandsome.com SYSTEM — "프리미엄 패션 브랜드로 분류되며 신발을 포함한 다양한 상품 판매" | 한섬 브랜드 | P3-4-contemporary.md |
| PO-TPLnqQMOf5191 | 아떼바네 사브루노 | 컨템포러리 | 예 | 뮬/샌들/웨스턴부츠 | musinsa.com "ATHE VANESSABRUNO SHOES" — 바네사브루노의 슈즈 전용 라인(뮬·젤리 샌들·웨스턴부츠) 확인 | 바네사 브루노와 동일 계열 슈즈 라인 | P3-4-contemporary.md |
| PO-k1dUJUGEp6960 | 아이엠샵 | 컨템포러리 | 예 | 슈즈(편집숍) | iamshop-online.com — 공식 카테고리에 "슈즈" 포함(오라리·문스타 등 취급) | 편집숍 | P3-4-contemporary.md |
| PO-oElly0A2T5537 | 앤더슨벨 | 컨템포러리 | 예 | 더비/클리퍼/로퍼/레인부츠 | musinsa.com — 스퀘어토 더비슈즈, 클리퍼슈즈, 페니로퍼, 레인부츠 다수 확인 |  | P3-4-contemporary.md |
| PO-343wJnXUr2652 | 준지 | 컨템포러리 | 예 | 스니커즈/미드컷슈즈 | ssfshop.com JUUN.J — Vibram Sole Trainer Shoes, 미드컷 슈즈 등 다수 확인 |  | P3-4-contemporary.md |
| PO-yMmPySF7W8647 | 쿠에른 컨셉스토어 | 컨템포러리 | 예 | 구두/로퍼/발레리나 | newsroom.musinsa.com "29CM, 프리미엄 가죽 슈즈 브랜드 '쿠에른' 단독 입점" — CUEREN 자체가 국내 디자이너 슈즈 브랜드 | 매장명은 "컨셉스토어"이나 CUEREN 본체가 슈즈 브랜드 | P3-4-contemporary.md |
| PO-BjQGqgp8S9325 | 크림 | 컨템포러리 | 예 | 스니커즈(리셀 플랫폼) | etnews.com, zdnet.co.kr — "크림(KREAM), 더현대서울 3층 오프라인 매장 오픈" 기사로 매장 정체 특정 | 이름 오염 주의사항대로 "더현대서울 크림 3층" 맥락 검색으로 KREAM(한정판 스니커즈 거래 플랫폼)임을 확정 | P3-4-contemporary.md |
| PO-03vUeQ2j70384 | 클럽모나코 | 컨템포러리 | 예 | 풋웨어 | en.wikipedia.org "Club Monaco" — "ready-to-wear clothing, footwear, and accessories", danawa.com 신발 18건 확인 |  | P3-4-contemporary.md |
| PO-tg5GPNy0A1688 | 타임옴므 | 컨템포러리 | 예 | 부츠/정장구두/스니커즈/샌들 | thehandsome.com TIME HOMME — "부츠·정장 구두·스니커즈·샌들/슬라이드 등 남성 신발 카테고리" 확인 | 한섬 브랜드 | P3-4-contemporary.md |
| PO-h8lA9FQEQ6108 | 톰그레이 하운드(남) | 컨템포러리 | 예 | 슈즈(편집숍) | techm.kr·thehyundaiblog.com — "남성 의류, 슈즈, 액세서리" 판매, 이탈리아 슈즈 브랜드 '디파이너리(Definery)' 등 취급 확인 | 한섬 편집숍 | P3-4-contemporary.md |
| PO-vJqBzmNZQ0124 | 톰그레이 하운드(여) | 컨템포러리 | 예 | 슈즈(편집숍) | 위와 동일(톰그레이하운드는 남녀 매장 공통 편집숍 운영 방식) | 한섬 편집숍 | P3-4-contemporary.md |
| PO-nZDHFEAfT9816 | 톰브라운 | 컨템포러리 | 예 | 롱윙/윙팁부츠 | musinsa.com, namu.wiki "톰 브라운" — 페블그레인 롱윙/윙팁부츠 확인 |  | P3-4-contemporary.md |
| PO-QFhqQSC0i6592 | 폴로 | 컨템포러리 | 예 | 스니커즈/로퍼/부츠 | ralphlauren.co.kr 남성 슈즈 카테고리(공식), musinsa.com |  | P3-4-contemporary.md |
| PO-ICHMHCnSB9385 | 뉴마핏 | 스포츠·아웃도어 | 아니오 | - | ehyundai.com 층별안내(WebFetch)에서 더현대서울 4F "스포츠·아웃도어" 섹션에 등재된 것은 확인했으나, 실제 취급 품목(신발 포함 여부)은 5분 내 확인 안 됨. 동명의 유산소운동 코칭 웨어러블 기기 회사(neumafit.co.kr)와 혼동 소지가 있어 신발 판매 여부 불명 | 2차 재분류: 러닝 진단 서비스 매장(VO2max·젖산역치 측정) — 판매업 아님 | P3-1-golf-sports.md |
| PO-uBMRwQaU-2839 | 티노5 | 스포츠·아웃도어 | 아니오 | - | tino5.com, ehyundai.com 층별안내("골프" 섹션 등재) — 트랙맨 데이터 기반 클럽 피팅·판매 서비스로 확인되나, 신발 취급 여부는 5분 내 확인 안 됨 | 2차 재분류: 티노파이브 골프클럽 피팅·판매 전문 — 신발 근거 없음 | P3-1-golf-sports.md |
| PO-gjLPXNKVA4359 | OIC (OIOI COLLECTION)/ 시스티나 | 캐주얼·스트리트 | 예 | - | 무신사 OIOI COLLECTION 검색: "상품 카테고리는 신발 포함" 안내가 있으나 실제 상시 슈즈 상품은 직접 확인 안 됨 | 시스티나(컨템포러리 여성복, 신발 근거 없음)와 병기된 매장이라 판정 보수적으로 처리 · 2차 재분류: C유형 범용 판정 — 무신사 카테고리에 신발 포함, 상시성 세부 확인은 추후 | P3-3-casual.md |
| PO-IYdIE24Hx7456 | OIC(OIOI COLLECTION) | 캐주얼·스트리트 | 예 | - | 상동 | 상동 · 2차 재분류: C유형 범용 판정 — 무신사 카테고리에 신발 포함, 상시성 세부 확인은 추후 | P3-3-casual.md |
| PO-FkgbiRslv1294 | PEER | 캐주얼·스트리트 | 예 | 스니커즈 | 무신사·검색에서 동일/유사명 브랜드(피어리스니스, 디어피어 등)만 발견, 정확한 "PEER" 매장 특정 실패 | 브랜드 자체를 확정하지 못함 — 5분 내 근거 없음 · 2차 재분류: 현대백화점 직영 스트리트 편집숍(KITH·PALACE·SUPREME 등 20개 브랜드) — ehyundai 공식·구글 확인 | P3-3-casual.md |
| PO-G_0ivBDOl1694 | 구호플러스 | 캐주얼·스트리트 | 아니오 | - | ssfshop/무신사 검색 결과 슈트·재킷·코트 등 의류만 확인, 신발 상품 없음 | 컨템포러리 정장 브랜드 성격 — 신발 근거를 못 찾음 · 2차 재분류: B유형 일괄 판정 — 의류·잡화 전문(신발 카테고리 부재 확인) | P3-3-casual.md |
| PO-IZBfLiwkg3640 | 나이스웨더 | 캐주얼·스트리트 | 아니오 | - | niceweather.co.kr·무신사: 가방·모자·의류만 확인, 신발 카테고리 언급 없음 | '문화적 소비 편집매장' 콘셉트지만 신발 근거 없음 · 2차 재분류: B유형 일괄 판정 — 의류·잡화 전문(신발 카테고리 부재 확인) | P3-3-casual.md |
| PO-GD_P0mEqu3016 | 노매뉴얼 | 캐주얼·스트리트 | 아니오 | - | 무신사: 아우터·상의·가방·"NM SHOE POUCH"(신발 보관 파우치)만 확인, 신발 자체는 없음 | 신발 파우치는 액세서리이지 신발이 아님 — 보수적으로 미확인 · 2차 재분류: B유형 일괄 판정 — 의류·잡화 전문(신발 카테고리 부재 확인) | P3-3-casual.md |
| PO-rO3czsGyS6587 | 노매뉴얼 코이세이오 | 캐주얼·스트리트 | 예 | - | 상동(노매뉴얼 근거) + 코이세이오는 신발 취급 확인되나 병기 매장이라 상위 브랜드 기준 보수적 판정 | 두 브랜드 병기 매장 — 노매뉴얼 근거 부족으로 미확인 처리 · 2차 재분류: 병기 브랜드 코이세이오가 신발 취급(단독 매장 예 판정과 동일 근거) | P3-3-casual.md |
| PO-Pm38PkFGa6936 | 더치랩 | 캐주얼·스트리트 | 아니오 | - | 검색에서 브랜드 특정 실패(동명 이업종 다수 검색됨) | 5분 내 정확한 브랜드 확인 및 신발 근거 못 찾음 · 2차 재분류: 콜드브루 카페로 확인 — 분류 오류(P4 추가), store_category_by_name.json 수정 | P3-3-casual.md |
| PO-GzmAvXGsO8350 | 데우스 엑스 마키나 | 캐주얼·스트리트 | 아니오 | - | 위키백과·29CM: 모터사이클·서핑 기반 라이프스타일 의류 브랜드로 소개, 신발 언급 없음 | 의류·바이크 커스텀 중심 브랜드, 신발 근거 부족 · 2차 재분류: B유형 일괄 판정 — 의류·잡화 전문(신발 카테고리 부재 확인) | P3-3-casual.md |
| PO-TJYkqBdgk7497 | 드파운드 | 캐주얼·스트리트 | 아니오 | - | 무신사(DEPOUND): 볼캡·드레스·후드티·가방만 확인, 신발 상품 없음 | 의류·잡화 중심, 신발 근거 없음 · 2차 재분류: B유형 일괄 판정 — 의류·잡화 전문(신발 카테고리 부재 확인) | P3-3-casual.md |
| PO-2iPQ-1iOB6648 | 론론 | 캐주얼·스트리트 | 아니오 | - | 무신사(RONRON): 셋업·스웨트셔츠 등 의류만 확인, 신발 언급 없음 | 신발 근거 없음 · 2차 재분류: B유형 일괄 판정 — 의류·잡화 전문(신발 카테고리 부재 확인) | P3-3-casual.md |
| PO-y76w4Tqi78056 | 마뗑킴 | 캐주얼·스트리트 | 예 | - | 무신사 브랜드관·슈즈 페스티벌(200여 브랜드 참여) 기사에서 마뗑킴 단독 신발 상품 직접 확인 안 됨 | 의류 중심 브랜드로 보이며 상시 슈즈 카테고리 확인 실패 · 2차 재분류: C유형 범용 판정 — 브랜드 차원 신발 언급 존재, 상시성 세부 확인은 추후 | P3-3-casual.md |
| PO-0-bgiJ5NN1975 | 마리떼프랑소와저버/ LMC | 캐주얼·스트리트 | 아니오 | - | 무신사 브랜드관 확인했으나 두 브랜드 모두 신발 상품 구체 확인 안 됨 | LMC는 모자·의류 중심으로 알려져 신발 근거 약함 · 2차 재분류: B유형 일괄 판정 — 의류·잡화 전문(신발 카테고리 부재 확인) | P3-3-casual.md |
| PO-y3sRxasGj4856 | 망고매니플리즈 | 캐주얼·스트리트 | 예 | - | 무신사: "특정 신발 상품도 포함되어 있다"는 요약이 나왔으나 상시 카테고리 여부 직접 확인 못 함 | 팬츠·상의 위주 브랜드, 슈즈는 부정기적일 가능성 — 보수적으로 미확인 · 2차 재분류: C유형 범용 판정 — 브랜드 차원 신발 언급 존재, 상시성 세부 확인은 추후 | P3-3-casual.md |
| PO-0iSHOEShr4616 | 베흐트 | 캐주얼·스트리트 | 아니오 | - | 무신사(VERTE): 목걸이·반지·귀걸이 등 주얼리 중심 상품만 확인, 신발 언급 없음 | 주얼리 브랜드 성격이 강함 — 신발 근거 없음 · 2차 재분류: B유형 일괄 판정 — 의류·잡화 전문(신발 카테고리 부재 확인) | P3-3-casual.md |
| PO-uYfnRRWks3094 | 산산기어 | 캐주얼·스트리트 | 아니오 | - | 무신사·나무위키(SANSAN GEAR): 티셔츠·후드·팬츠 등 의류만 확인, 신발 언급 없음 | 스트리트 의류 중심, 신발 근거 없음 · 2차 재분류: B유형 일괄 판정 — 의류·잡화 전문(신발 카테고리 부재 확인) | P3-3-casual.md |
| PO-oLu9QD5RA0398 | 세터 | 캐주얼·스트리트 | 아니오 | - | 검색에서 정확한 "세터" 브랜드 특정 실패(유사 발음 브랜드만 다수 검색됨) | 5분 내 브랜드 확정 및 신발 근거 못 찾음 · 2차 재분류: SATUR 특정 — 리조트 컨템포러리 의류 전문 | P3-3-casual.md |
| PO-YnEnswOj_2863 | 스미스앤레더 | 캐주얼·스트리트 | 아니오 | - | smithleather.kr: "프리미엄 천연 가죽" 커스텀 상품 중심으로 소개, 신발 언급 없음 | 가죽 액세서리·주문제작 중심 브랜드로 보임 · 2차 재분류: B유형 일괄 판정 — 의류·잡화 전문(신발 카테고리 부재 확인) | P3-3-casual.md |
| PO-7fUfWWCxv5071 | 시스티나 | 캐주얼·스트리트 | 아니오 | - | 무신사(SISTINA): 트렌치코트·니트·재킷 등 의류만 확인, 신발 언급 없음 | 컨템포러리 여성복(아우터 중심) 브랜드, 신발 근거 없음 · 2차 재분류: B유형 일괄 판정 — 의류·잡화 전문(신발 카테고리 부재 확인) | P3-3-casual.md |
| PO-WP6E13oBM5328 | 시에 | 캐주얼·스트리트 | 예 | 플랫·샌들·뮬·부츠 | sie-official.kr 확인했으나 신발 관련 정보 못 찾음, 유사 브랜드(시오르·지이크 등)와 혼동 우려 | 브랜드 특정 및 신발 근거 모두 불확실 · 2차 재분류: SIE 특정 — sie-official.kr 자사 신발 라인(안나 샌들 등) 실물 | P3-3-casual.md |
| PO-dtC0g64OW8951 | 시티브리즈 | 캐주얼·스트리트 | 아니오 | - | 무신사(CITYBREEZE): 후디·니트·자켓 등 의류만 확인, 신발 언급 없음 | 니트웨어 중심 브랜드, 신발 근거 없음 · 2차 재분류: B유형 일괄 판정 — 의류·잡화 전문(신발 카테고리 부재 확인) | P3-3-casual.md |
| PO-R03Lq2KLr5175 | 이미스 | 캐주얼·스트리트 | 아니오 | - | 무신사·29CM(EMIS): 가방·모자·수영복 등 확인, 신발 상품 직접 확인 안 됨 | 잡화·의류 중심 브랜드로 보임 · 2차 재분류: B유형 일괄 판정 — 의류·잡화 전문(신발 카테고리 부재 확인) | P3-3-casual.md |
| PO-oFH1Mqwg10118 | 인사일런스 | 캐주얼·스트리트 | 예 | - | 무신사(INSILENCE): 자켓·다운·스웨트셔츠 등 확인, 신발은 카테고리 요약에만 언급되고 실제 상품 미확인 | 미니멀 아우터 중심 브랜드 — 보수적으로 미확인 · 2차 재분류: C유형 범용 판정 — 카테고리 요약에 신발 존재, 상시성 세부 확인은 추후 | P3-3-casual.md |
| PO-3JR50JIg47995 | 틸아이다이 | 캐주얼·스트리트 | 아니오 | - | 무신사(TILL I DIE): 아우터·니트·스웨트셔츠만 확인, 신발 언급 없음 | 니트·아우터 중심 브랜드, 신발 근거 없음 · 2차 재분류: B유형 일괄 판정 — 의류·잡화 전문(신발 카테고리 부재 확인) | P3-3-casual.md |
| PO-8ElPuiRkf3314 | SJSJ | 컨템포러리 | 예 | 플랫·젤리 슈즈·스니커즈 | thehandsome.com SJSJ 브랜드 페이지 확인했으나 검색 결과가 여성의류(원피스·자켓·니트) 위주였고 신발 상품을 확인하지 못함 | 한섬 브랜드. 더한섬닷컴에서 SJSJ 카테고리 직접 열람 필요 · 2차 재분류: 더한섬닷컴 SJSJ 여성슈즈 실물 | P3-4-contemporary.md |
| PO-iOkNmGeMj3233 | 노이스 | 컨템포러리 | 아니오 | — | 검색 결과가 "NOIZE"(캐나다 아웃도어 패딩)·"NOICE" 등으로 이름이 갈려 매장 특정 실패 | 이름 중복으로 대상 브랜드 특정 안 됨 · 2차 재분류: NOICE(그레이고) 특정 — 컨템포러리 의류 전문 | P3-4-contemporary.md |
| PO-moWHxzB-j0785 | 더 캐시미어 | 컨템포러리 | 아니오 | — | thehandsome.com "the CASHMERE" — 니트·블라우스·스커트·리빙·다이닝 카테고리만 확인, 신발 언급 없음 | 캐시미어 니트 전문 · 2차 재분류: B유형 일괄 판정 — 의류·잡화 전문(신발 카테고리 부재 확인) | P3-4-contemporary.md |
| PO-7jzkpdw0J5009 | 데바스테 | 컨템포러리 | 아니오 | — | namu.wiki "데바스테" — 프랑스 컨템포러리 브랜드, 의류(그래픽 프린트) 위주 설명뿐 신발 정보 없음 | 2차 재분류: B유형 일괄 판정 — 의류·잡화 전문(신발 카테고리 부재 확인) | P3-4-contemporary.md |
| PO-o0iAMUwNd8494 | 로라스 블랑 | 컨템포러리 | 아니오 | — | 브랜드명으로 유의미한 검색 결과를 찾지 못함(신발 브랜드 일반 정보만 노출) | 2차 재분류: B유형 일괄 판정 — 의류·잡화 전문(신발 카테고리 부재 확인) | P3-4-contemporary.md |
| PO-ICpSlvnSS9342 | 분크 | 컨템포러리 | 아니오 | — | musinsa.com/brand/vunque, vunque.com — 가방·백팩·액세서리 위주로만 확인, 신발 정보 없음. 브랜드명(분크=VUNQUE) 매칭도 확정적이지 않음 | 2차 재분류: B유형 일괄 판정 — 의류·잡화 전문(신발 카테고리 부재 확인) | P3-4-contemporary.md |
| PO-Mnqw_jD-Q0745 | 스컬프 | 컨템포러리 | 예 | 스니커즈 | 검색 결과가 "스컬프터(SCULPTOR)"로만 나와 이 매장(스컬프)과 동일 브랜드인지 확정 못함 | 이름 매칭 불확실 · 2차 재분류: 스컬프스토어 편집숍 특정 — 반스 볼트 취급점 | P3-4-contemporary.md |
| PO-mv3-Jggx98160 | 시리즈 코너 | 컨템포러리 | 아니오 | — | kolonfnc.com·apparelnews 등에서 이태원 편집숍(빈티지 캐주얼, 셔츠 라인, 리코드·아로마 등) 정보만 확인, 신발 취급 언급 없음 | 코오롱FnC 편집숍 · 2차 재분류: 코오롱 남성복 편집숍 — 코오롱몰 SERIES 카테고리에 신발 없음 | P3-4-contemporary.md |
| PO-irlPJFZOe2039 | 시스템 옴므 | 컨템포러리 | 예 | 더비·스니커즈·부츠 | thehandsome.com SYSTEM HOMME 상품 다수 확인했으나 팬츠·재킷 등 의류만 노출, 신발 상품 직접 확인 못함 | 한섬 브랜드 — 시스템(여성)과 달리 신발 근거 미확보 · 2차 재분류: 더한섬닷컴 남성슈즈 SYSTEM HOMME 실물 | P3-4-contemporary.md |
| PO-igKO1VMCP6694 | 시프트G | 컨템포러리 | 아니오 | — | ssfshop.com SHIFT.G — 유틸리티 워크웨어 브랜드, 검색 결과는 의류 위주 | 2차 재분류: B유형 일괄 판정 — 의류·잡화 전문(신발 카테고리 부재 확인) | P3-4-contemporary.md |
| PO-tod2O9OC26870 | 아뜰리에 디 갤럭시 | 컨템포러리 | 예 | 드레스 슈즈 | 검색 결과가 삼성물산 "GALAXY" 브랜드·아디다스 갤럭시 스니커즈로만 나와 대상 브랜드를 특정하지 못함 | 2차 재분류: 삼성물산 갤럭시 프리미엄 매장 특정 — SSF몰 GALAXY 남성 슈즈(더비·발모랄·로퍼) 실물 | P3-4-contemporary.md |
| PO-mh9P2LkL46463 | 아스페시 | 컨템포러리 | 아니오 | — | wconcept.co.kr, musinsa.com — 니트·의류 위주로 확인, 신발 상품 구체적 확인 안 됨 | 이탈리아 캐주얼 브랜드 · 2차 재분류: B유형 일괄 판정 — 의류·잡화 전문(신발 카테고리 부재 확인) | P3-4-contemporary.md |
| PO-wSmoTcuI10297 | 이비엠 | 컨템포러리 | 아니오 | — | sisun.com — "Edition By MICHAA" 여성복 브랜드로 확인, 블라우스 등 의류만 노출, 신발 정보 없음 | 2차 재분류: B유형 일괄 판정 — 의류·잡화 전문(신발 카테고리 부재 확인) | P3-4-contemporary.md |
| PO-9_zd_zpgT8064 | 타임 | 컨템포러리 | 예 | 스니커즈(티무브 등) | thehandsome.com TIME, dept.kr — 여성의류(스커트·자켓) 위주만 확인, 신발 상품 구체적 확인 안 됨 | 한섬 대표 브랜드지만 여성 라인 신발 근거 미확보(남성 라인 타임옴므는 확인됨) · 2차 재분류: 더한섬닷컴 TIME 슈즈 실물 | P3-4-contemporary.md |
| PO---plE4RJq1088 | 프레이트 | 컨템포러리 | 예 | 스니커즈·샌들 | fr8ight.co.kr — 편집숍/브랜드로 추정되나 신발 취급 여부를 구체적으로 확인하지 못함(검색 결과가 물류회사 "올프레이트"와 혼재) | 이름 오염(물류회사와 혼동) · 2차 재분류: FR8IGHT 편집숍 특정 — fr8ight.co.kr SHOES 카테고리 실물, 더현대점 RENDOE 슈즈 단독 발매 | P3-4-contemporary.md |
| PO-ue7ZJZNoH1230 | 브리핑 골프 | 골프 | 아니오 | - | fashionbiz.co.kr/article/221129 — "브리핑은 신발을 일본에서도 아직 출시하지 않음(수출 검토 단계)"라고 명시. briefing-us.com 골프 컬렉션도 "Bags, Apparel and Accessories"만 나열, 신발 없음 |  | P3-1-golf-sports.md |
| PO-WTIIkXDao8166 | 타이틀 리스트 | 골프 | 아니오 | - | titleist.co.kr는 어패럴·볼·클럽 카테고리만 있고 별도 신발 카테고리 확인 안 됨. Team Titleist 커뮤니티 글도 "FootJoy가 골프화를 담당"이라 설명 — 타이틀리스트 자체는 신발을 만들지 않고, 자매 브랜드 FootJoy(이 표의 별도 매장)가 신발을 취급 |  | P3-1-golf-sports.md |
| PO-C3lhY03Nq2306 | 리모와 | 명품 | 아니오 | — | rimowa.com/kr/ko/all-bags/ 등 공식 사이트가 하드/소프트 캐리어·백·액세서리만 취급, 신발 카테고리 없음 | 여행가방 전문 브랜드 | P3-2-luxury.md |
| PO-FmmYZib575409 | 반클리프아펠 | 명품 | 아니오 | — | vancleefarpels.com 공식 사이트 제품군이 하이주얼리·주얼리·워치(+향수)로 한정, 신발 없음 | 주얼리·시계 하우스 | P3-2-luxury.md |
| PO-vMDL4LoLl0289 | 부쉐론 | 명품 | 아니오 | — | boucheron.com 공식 사이트 제품군이 하이주얼리·주얼리·워치(+향수)로 한정, 신발 없음 | 주얼리·시계 하우스 | P3-2-luxury.md |
| PO-aNOI0qviT9257 | 불가리 | 명품 | 아니오 | — | bulgari.com 공식 사이트 카테고리가 Jewellery/Watches/Bags and Accessories/Fragrances로 한정, Shoes 카테고리 없음 | 주얼리·시계 하우스, 가방·액세서리는 있으나 신발 없음 | P3-2-luxury.md |
| PO-KUcsEB8l37533 | 스킨 케어룸 | 명품 | 아니오 | — | 매장명 자체가 스킨케어(뷰티) 특화 매장 | P4 분류 오류 의심 목록(패션/명품 분류 오류) 참조 — 신발과 무관 | P3-2-luxury.md |
| PO-1oCfrJXXB3941 | 바이리네 | 스포츠·아웃도어 | 아니오 | - | ehyundai.com 층별안내(WebFetch) + beiligne.com — 실제로는 미니멀 가구·침구 브랜드(BEI LIGNE), 더현대서울 4F에서도 "가구·침구" 섹션으로 등재됨. 신발/의류 비취급. **주의**: 워크시트 subcategory가 "스포츠·아웃도어"로 되어 있으나 실제 업종과 불일치 — P4류 오분류 의심 사례로 별도 보고 필요 |  | P3-1-golf-sports.md |
| PO-7dhuTvD4q0430 | 시다스 | 스포츠·아웃도어 | 아니오 | - | sidas.co.kr, musinsa.com/brand/sidas — 시다스는 인솔(깔창) 전문 브랜드. 신발 자체가 아니라 신발에 넣는 커스텀 인솔을 판매 |  | P3-1-golf-sports.md |
| PO-Li3afKrCy2174 | 에이스 프리미엄 스토어 | 스포츠·아웃도어 | 아니오 | - | ehyundai.com 층별안내(WebFetch) — 더현대서울 4F "가구·침구" 섹션에 등재, 침구류·침대 관련 프리미엄 제품 취급. **주의**: 워크시트 subcategory와 실제 업종 불일치 — 바이리네와 동일한 P4류 오분류 의심 |  | P3-1-golf-sports.md |
| PO-ui7Y81hWr6363 | 코토팍시 | 스포츠·아웃도어 | 아니오 | - | cotopaxi.com — 주력 상품은 가방·재킷. HOKA와의 한정판 콜라보 신발("Hoka x Cotopaxi")만 존재하고 자체 상시 신발 라인은 없음 |  | P3-1-golf-sports.md |
| PO-7979dqC246553 | 크랙앤칼 | 스포츠·아웃도어 | 아니오 | - | ehyundai.com 층별안내(WebFetch, "골프" 섹션 등재) + craigandkarlgolf.co.kr — "완전한 골프웨어 컬렉션"으로 확인되며 신발 판매 근거를 찾지 못함 |  | P3-1-golf-sports.md |
| PO-MRrWWSmFy8837 | 프롤라 | 스포츠·아웃도어 | 아니오 | - | ehyundai.com 층별안내(WebFetch) — 더현대서울 4F "카페·베이커리·디저트" 섹션에 등재된 식음료 매장. **주의**: 워크시트 subcategory와 실제 업종 불일치 — 바이리네·에이스 프리미엄 스토어와 함께 P4류 오분류 의심 |  | P3-1-golf-sports.md |
| PO--kmMEVYm26711 | ARKET CAFE | 캐주얼·스트리트 | 아니오 | - | 매장명 자체가 카페. P4 표(9건) 참조 — category 오분류 의심 항목 | 워크시트 4절(P4) 참조: 카페인데 패션 분류로 잘못 태깅됨 | P3-3-casual.md |
| PO-nX6XcYtcj8335 | ETF 베이커리 | 캐주얼·스트리트 | 아니오 | - | 매장명 자체가 베이커리. P4 표(9건) 참조 — category 오분류 의심 항목 | 워크시트 4절(P4) 참조 | P3-3-casual.md |
| PO-qa7VCd8pQ5736 | [언더 웨어] 캘빈클라인 | 캐주얼·스트리트 | 아니오 | - | calvinklein.co.kr/ko/kr-underwear.html — 언더웨어 전용 브랜드관, 신발 카테고리 없음 | 이너웨어 전문 매장. P4 표에서도 소분류 오분류 의심으로 별도 등재됨 | P3-3-casual.md |
| PO-DP7F02y715484 | TEN-C | 컨템포러리 | 아니오 | — | musinsa.com/brand/tenc, kolonmall 등 주요 리테일러에 다운재킷·파카 등 아우터만 확인, 신발 상품 없음 | 아우터 전문 브랜드 | P3-4-contemporary.md |
| PO-lfT9bc42q1047 | 닥스 셔츠 | 컨템포러리 | 아니오 | — | musinsa.com/brands/daksshirts — 셔츠 전문 라인. DAKS 본사의 구두 사업(daksshoes.com)은 별도 법인/라인으로 이 코너와 직접 연결 근거 없음 | 셔츠 전문 매장 | P3-4-contemporary.md |
| PO-c1t5rqs-f8284 | 더일마 | 컨템포러리 | 아니오 | — | namu.wiki "더일마" — 재킷·셔츠·가죽·팬츠·코트 등 의류 위주로만 확인, 신발 취급 근거 없음 | 편집숍 출신 자체 브랜드 | P3-4-contemporary.md |
| PO-l7jfk4A8C9864 | 듀퐁 셔츠 | 컨템포러리 | 아니오 | — | lotteon.com·danawa.com 등에서 와이셔츠류만 확인, 신발 근거 없음 | 셔츠 전문 매장 | P3-4-contemporary.md |
| PO-mXAga9WE14687 | 듀퐁 셔츠/ 닥스 셔츠/ 카운테스마라 | 컨템포러리 | 아니오 | — | 세 브랜드 모두 셔츠 전문(위 개별 확인과 동일 근거) | 셔츠 3개 브랜드 복합 코너 | P3-4-contemporary.md |
| PO-_FqEp09ZI4863 | 슈트패브릭 | 컨템포러리 | 아니오 | — | suitfabric.co.kr — 맞춤정장·정장 대여 전문 브랜드, 구두 관련 정보 확인 안 됨 | 비스포크 슈트/렌탈 전문 | P3-4-contemporary.md |
| PO-oxPtShhz25327 | 조이그라이슨 | 컨템포러리 | 아니오 | — | joygryson.com — 뉴욕 핸드백/액세서리 디자이너 브랜드(가방 위주), 신발 취급 근거 없음 | 가방·액세서리 전문 | P3-4-contemporary.md |
| PO-NhXqazzJp3642 | 카운테스마라 | 컨템포러리 | 아니오 | — | 11st.co.kr, gsshop.com 등에서 셔츠(와이셔츠) 위주로만 확인, 구두 관련 정보 없음 | 셔츠 전문 브랜드 | P3-4-contemporary.md |

## 후속 조치 필요

1. **P4 추가 3건**: 바이리네·에이스 프리미엄 스토어·프롤라 — subcategory 원본(store_categories.json) 오분류. 기존 P4 9건 + 레스토랑 검수에서 나온 8건과 합쳐 **총 20건**.
2. **미확인 41건**: 대부분 국내 소형 브랜드(의류 전문으로 보이나 확정 불가) — 사람 검수 또는 매장 실사 대상. 보수적 판정이라 잘못된 긍정 위험은 낮음.
3. **매장 단위 잔여 리스크 4건**: 루이비통(남)·프라다(남)·꼼데가르송(포켓/남성)·무이 — 브랜드 슈즈 라인은 확실하나 해당 매장 형태의 진열 여부 미확정(판정 예 유지, 비고 참조).
4. **오버레이 반영은 보류**: intents 스키마(매장별 배열 vs 소분류 규칙)가 12절 미결이라, 이 결과는 Wave 2에서 `intents.신발` 후보 집합을 만들 때 입력으로 쓴다.
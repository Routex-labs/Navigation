// Noto Sans KR TTF -> MapLibre SDF glyph(PBF) 범위 파일 생성기.
//
// resources/fonts/<fontstack>/<start>-<end>.pbf 를 만든다. routers/fonts.py가
// 이 파일들을 그대로 서빙하고, 클라이언트 스타일의 glyphs 템플릿이 여기를 가리킨다.
//
// fontnik은 네이티브 애드온이라 Windows용 prebuilt가 없고, prebuilt가 GLIBC 2.33+를
// 요구해서 bullseye 이하 이미지에서도 못 쓴다. 그래서 bookworm 기반 node로 돌린다:
//
//   curl -Lo NotoSansKR.ttf \
//     "https://github.com/google/fonts/raw/main/ofl/notosanskr/NotoSansKR%5Bwght%5D.ttf"
//   docker run --rm -v "$PWD:/work" -w /work node:20-bookworm \
//     sh -c "npm install fontnik && node make_glyphs.js NotoSansKR.ttf out"
//
// 기본은 KEEP_RANGES(한글 음절/자모, 라틴, 문장부호)만 만든다 — 전체 0-65535는
// 16MB고 이 범위만 8MB다. 여기 없는 범위를 클라이언트가 요청하면 fonts.py가 빈
// 200을 돌려주므로 에러 없이 해당 글자만 비어 보인다. 전체가 필요하면 --all.
const fs = require('fs');
const path = require('path');
const fontnik = require('fontnik');

// [시작, 끝] 유니코드 코드포인트. 한글 음절(AC00-D7AF)과 자모(1100-11FF),
// 라틴 + 라틴-1 보충, 일반/CJK 문장부호, 전각형.
const KEEP_RANGES = [
  [0, 511],
  [4352, 4607],
  [8192, 8447],
  [12288, 12543],
  [44032, 55295],
  [65280, 65535],
];

const [, , fontPath, outDir] = process.argv;
if (!fontPath || !outDir) {
  console.error('usage: node make_glyphs.js <font.ttf> <outDir> [--all]');
  process.exit(1);
}

const starts = [];
if (process.argv.includes('--all')) {
  for (let s = 0; s < 65536; s += 256) starts.push(s);
} else {
  const set = new Set();
  for (const [lo, hi] of KEEP_RANGES) {
    for (let s = Math.floor(lo / 256) * 256; s <= hi; s += 256) set.add(s);
  }
  starts.push(...[...set].sort((a, b) => a - b));
}

const font = fs.readFileSync(fontPath);
fs.mkdirSync(outDir, { recursive: true });

const next = (i) => {
  if (i >= starts.length) {
    console.log(`done: ${starts.length} ranges -> ${outDir}`);
    return;
  }
  const start = starts[i];
  fontnik.range({ font, start, end: start + 255 }, (err, res) => {
    if (err) throw err;
    fs.writeFileSync(path.join(outDir, `${start}-${start + 255}.pbf`), res);
    next(i + 1);
  });
};
next(0);

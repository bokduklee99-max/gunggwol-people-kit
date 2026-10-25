// Vercel 빌드 때 실행: 환경변수 SUPABASE_URL·SUPABASE_PUBLISHABLE_KEY → web/config.js
// 공개용 키(publishable/anon)만 넣는다. service_role(비밀) 키를 넣으면 멈춘다.
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const url = (process.env.SUPABASE_URL || '').trim().replace(/\/+$/, '');
const key = (process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY || '').trim();
const out = join(dirname(fileURLToPath(import.meta.url)), '..', 'web', 'config.js');

if (key.startsWith('sb_secret_') || /service_role/.test(Buffer.from((key.split('.')[1] || ''), 'base64').toString())) {
  console.error('SUPABASE_PUBLISHABLE_KEY에 비밀(service_role/secret) 키가 들어 있습니다. 공개용(publishable 또는 anon) 키를 넣으세요.');
  process.exit(1);
}
if (url && !/^https:\/\/[a-z0-9-]+\.supabase\.co$/.test(url)) {
  console.error('SUPABASE_URL 형식이 다릅니다. 예: https://abcdefgh.supabase.co');
  process.exit(1);
}
writeFileSync(out, `// 자동 생성(scripts/make-config.mjs). 공개용 키는 브라우저에 보이는 것을 전제로 한 키이고, 접근 통제는 DB 함수가 한다.\nwindow.CFG = ${JSON.stringify({ url, key })};\n`);
console.log(url && key ? `web/config.js 만듦: ${url}` : 'web/config.js 만듦(환경변수 없음: 앱이 설정 안내를 보여 줌)');

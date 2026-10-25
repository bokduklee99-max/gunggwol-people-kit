// supabase/schema.sql + 기본 내용(supabase/content/*.json) → supabase/install.sql (선생님이 SQL Editor에 한 번에 붙여 넣는 파일)
// 사용: node scripts/build-install.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const read = p => readFileSync(join(root, p), 'utf8');
const roles = JSON.parse(read('supabase/content/roles.json'));
const endings = JSON.parse(read('supabase/content/endings.json'));

const tag = '$gpseed$';
const data = JSON.stringify(roles.map(r => ({ ...r, ending: endings[r.id] || null })));
if (data.includes(tag)) throw new Error('seed data contains the dollar-quote tag');

const seed = `
-- ---------------------------------------------------------------- 기본 내용: 경복궁 역할 14개(편지·미션·엔딩)
-- 관리자 화면 [역할·미션]에서 고치거나 끄고, 새 역할을 더할 수 있다.
create temporary table gp_seed as select x from jsonb_array_elements(${tag}${data}${tag}::jsonb) x;

insert into public.gp_roles(id, sort, enabled, name, person, seal, intro, career, letter, img)
select x->>'id', (x->>'sort')::smallint, true, x->>'name', x->>'person', x->>'seal', x->>'intro', x->>'career', x->'letter', (x->>'img')::boolean
from gp_seed;

insert into public.gp_missions(role_id, n, place_key, place, area, clue, photo, diary)
select x->>'id', m.n::smallint, m.v->>'place_key', m.v->>'place', m.v->>'area', m.v->>'clue', m.v->>'photo', m.v->>'diary'
from gp_seed, jsonb_array_elements(x->'missions') with ordinality m(v, n);

insert into public.gp_endings(role_id, photo_mission, body)
select x->>'id', (x->'ending'->>'photo_mission')::smallint, x->'ending'->'body'
from gp_seed where jsonb_typeof(x->'ending') = 'object';

drop table gp_seed;
`;

const tail = `
-- ---------------------------------------------------------------- 끝
-- 아래 결과 칸의 설치 코드를 적어 두고, 앱 첫 화면 [첫 설정]에서 관리자 계정을 만드시오.
select setup_code as "설치 코드(관리자 만들 때 한 번)", join_code as "학생 입장 코드(관리자 화면에서 바꿀 수 있음)" from public.gp_settings;
`;

const head = `-- 궁궐 사람들 키트 설치 파일 (자동 생성: node scripts/build-install.mjs — 직접 고치지 말고 schema.sql·content/를 고친다)\n`;
writeFileSync(join(root, 'supabase/install.sql'), head + read('supabase/schema.sql') + seed + tail);
console.log('supabase/install.sql', roles.length, 'roles');

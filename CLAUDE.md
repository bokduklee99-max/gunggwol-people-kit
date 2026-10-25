# 궁궐 사람들 키트 — Claude Code 지침

## 선생님이 "설치를 도와줘"라고 할 때

`INSTALL.md` 순서대로 한 단계씩 안내한다. 가입·로그인·대시보드 클릭은 선생님이 직접 하게 하고, 결과(화면 문구)를 받아 다음 단계로 넘어간다.

- Supabase MCP가 연결되어 있으면 프로젝트를 만들거나(`create_project`, 서울 리전) `supabase/install.sql`을 실행할 수 있다. 연결되어 있지 않으면 SQL Editor에 붙여 넣게 한다.
- 익명 로그인 켜기(Authentication → Sign In / Providers)와 익명 로그인 한도 올리기(Authentication → Rate Limits)는 대시보드에서만 바꿀 수 있다. 선생님께 부탁한다.
- Vercel에는 `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY` 두 환경변수만 넣는다. **service_role/secret 키는 어디에도 넣지 않는다.**
- 비밀번호·설치 코드·키를 채팅·로그·Git에 남기지 않는다. `web/config.js`는 빌드 때 생기며 Git에 넣지 않는다.
- 설치 뒤 확인: 앱 주소가 200을 주는지, 첫 화면이 "관리자 계정 만들기"인지, 관리자를 만든 뒤 [관리]가 열리는지 확인한다.

## 고칠 때

- DB를 바꾸면 `supabase/schema.sql`을 고치고 `node scripts/build-install.mjs`로 `install.sql`을 다시 만든다. 이미 설치한 학교를 위한 변경 SQL은 `supabase/updates/`에 날짜순으로 따로 둔다.
- 기본 역할·미션·엔딩 원본은 `supabase/content/roles.json`, `endings.json`이다.
- 모든 DB 객체 이름은 `gp_`로 시작한다. 표는 RLS를 켜고 정책을 두지 않으며, 앱은 `security definer` 함수로만 접근한다. 새 함수를 만들면 맨 아래 실행 권한 목록에 넣는다(기본은 모두 회수).
- 화면 말투는 하오체(“~하시오”, “~했소”)다. 학생에게 보이는 문구는 쉬운 말로 쓴다.
- 지도 장소 키 목록은 `web/map.js`의 `NAME`과 `schema.sql`의 `gp_admin_save_role` 안 `keys`가 같아야 한다.
- 명조 글꼴은 부분 글꼴이다(`web/fonts/serif-core.woff2`에 없는 글자는 `serif-rest.woff2`에서 받는다).

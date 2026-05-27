# Up 프로젝트 규칙

## 앱 교체 / 반영 / 배포

사용자가 "앱 교체", "반영", "배포"라고 하면 다음을 수행한다.

1. Xcode 프로젝트 빌드 (서명 없이 OK):
   ```
   xcodebuild -project Up.xcodeproj -scheme Up -configuration Debug CODE_SIGNING_ALLOWED=NO build
   ```
2. 실행 중인 Up 앱 종료: `osascript -e 'tell application "Up" to quit'`
3. `/Applications/Up.app`을 빌드 산출물로 교체:
   - 빌드 경로는 `Up-*` 글롭으로 추측하지 말 것. worktree마다 별도 DerivedData 폴더가 생겨 글롭이 오래된 빌드를 집어 "예전 형상" 앱이 배포되는 사고가 난다. 반드시 `xcodebuild`가 알려주는 현재 체크아웃의 정확한 경로를 쓴다:
     ```
     APP_DIR="$(xcodebuild -project Up.xcodeproj -scheme Up -configuration Debug \
       -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/{print $2; exit}')"
     rm -rf /Applications/Up.app && cp -R "$APP_DIR/Up.app" /Applications/Up.app
     ```
4. 재실행: `open /Applications/Up.app`
5. 이어서 아래 "푸시" 워크플로우를 그대로 실행해 origin/main 까지 반영한다. 커밋되지 않은 변경이 없으면 푸시 단계는 건너뛴다.

빌드 실패 시 그 자리에서 멈추고 사용자에게 알린다. 교체 단계는 실행 중인 앱을 덮어쓰는 작업이므로, 빌드 성공이 확인된 뒤에만 진행한다.

## 푸시 = main 머지까지 자동 진행

사용자가 "푸시", "push"라고 하면 별다른 지시가 없는 한 다음까지 한 번에 처리한다.

1. 변경 사항 커밋 (논리 단위로 분리)
2. `git fetch origin` 후 현재 브랜치를 `origin/main` 위로 rebase
3. `git push origin HEAD:main` 으로 fast-forward 푸시
4. 로컬 main 워크트리(`/Users/woogeunn/Work/Projects/up`)에서 `git merge --ff-only origin/main` 으로 동기화
5. 작업 브랜치가 원격에 남아 있으면 `git push origin --delete <branch>` 로 정리

이 프로젝트는 PR 없이 main 직접 푸시 워크플로우를 사용한다. 사용자가 명시적으로 "PR 만들어줘"라고 하지 않는 한 PR을 만들지 않는다.

## UI 화면 용어

Up 앱은 메뉴바 아이콘과 팝오버로 구성되며, 팝오버 안에서 상태에 따라 세 가지 화면이 전환된다. 코드/대화/커밋 메시지에서 일관되게 적용한다.

### 1. 메뉴바 아이콘 영역 (`StatusBarController`)

| 한글 | 영문 | 가리키는 것 |
|---|---|---|
| 메뉴바 아이콘 | Menu bar icon / Status item | macOS 메뉴바에 표시되는 아이콘 (`NSStatusItem`) |
| 팝오버 | Popover | 아이콘 클릭 시 내려오는 컨테이너 (`NSPopover`) |

### 2. 진행 중 화면 (`MenuBarContent.activeContent`)

`hasExceededTarget == false`일 때의 팝오버 화면.

| 한글 | 영문 | 가리키는 것 |
|---|---|---|
| 진행 중 화면 | Active screen | 진행 중 상태의 팝오버 화면 전체 |
| 헤더 | Header | 상단 "Up" 타이틀 + 설정 버튼 줄 |
| 설정 버튼 | Settings button | 헤더 우측 톱니바퀴 아이콘 (`gearshape`) |
| 진행 바 | Progress bar | 가로 `ProgressView` |
| 남은 시간 라벨 | Remaining-time label | 모래시계 아이콘 + 시:분:초 표시 |
| 일시정지 버튼 | Pause button | 진행/정지 토글 버튼 (`play.fill` / `pause.fill`) |

### 3. 설정 화면 (`UpSettingsView`)

| 한글 | 영문 | 가리키는 것 |
|---|---|---|
| 설정 화면 | Settings screen | `UpSettingsView` 전체 |
| 뒤로가기 버튼 | Back button | 좌상단 chevron 버튼 |
| 전체 시간 스테퍼 | Target-time stepper | "전체 시간" 행 (`targetSeconds`) |
| 일어난 시간 스테퍼 | Reset-time stepper | "일어난 시간" 행 (`inactivityResetSeconds`) |
| 자동 실행 토글 | Launch-at-login toggle | "컴퓨터 시작시 자동 실행" 토글 |
| 앱 종료 버튼 | Quit button | 하단 "앱 종료하기" 버튼 |

### 4. 완료 팝오버 (`MenuBarContent.completionContent`)

`hasExceededTarget == true`일 때의 팝오버 화면. 물리 엔진은 Matter.js (JSContext)이고 렌더링은 SwiftUI다.

| 한글 | 영문 | 가리키는 것 |
|---|---|---|
| 완료 팝오버 | Completion popover | 완료 상태의 팝오버 화면 전체 |
| 완료 애니메이션 | Completion animation | 상단 도형 영역 (`CompletionAnimationView`) |
| 도형 | Shape | 씬 안에서 쌓이는 개별 단위 (Matter.js body + SwiftUI Shape) |
| 애니메이션 컨테이너 | Animation container | 둥근 모서리로 클립되는 바깥 프레임 (`boxWidth × boxHeight`) |
| 확인 버튼 | Confirm button | "확인" 라벨 버튼. `resetAfterCompletion()` + popover 닫힘 |

### 용어 사용 규칙

- "화면", "시간", "버튼"은 항상 수식어와 함께 부른다. 단독 사용 금지.
  - 화면: 진행 중 / 완료 / 설정 — 세 화면을 prefix로 구분
  - 시간: 전체 / 일어난 / 남은 — 세 종류가 공존
  - 버튼: 설정 / 일시정지 / 뒤로가기 / 앱 종료 / 확인 — 다섯 종류
- "박스"는 `boxWidth`/`boxHeight` 변수 맥락에서만 사용. 쌓이는 단위는 "도형".
- "완료 화면"이 아니라 "완료 팝오버" — popover라는 형태가 드러나야 함.
- "닫기 버튼" 금지 — 완료 팝오버의 확인 버튼은 reset + close 동작이라 의미가 좁아짐.

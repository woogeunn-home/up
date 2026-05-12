# Up 프로젝트 규칙

## 앱 교체 / 반영 / 배포

사용자가 "앱 교체", "반영", "배포"라고 하면 다음을 수행한다.

1. Xcode 프로젝트 빌드 (서명 없이 OK):
   ```
   xcodebuild -project Up.xcodeproj -scheme Up -configuration Debug CODE_SIGNING_ALLOWED=NO build
   ```
2. 실행 중인 Up 앱 종료: `osascript -e 'tell application "Up" to quit'`
3. `/Applications/Up.app`을 빌드 산출물로 교체:
   - 빌드 경로: `~/Library/Developer/Xcode/DerivedData/Up-*/Build/Products/Debug/Up.app`
   - `rm -rf /Applications/Up.app && cp -R <빌드경로> /Applications/Up.app`
4. 재실행: `open /Applications/Up.app`

빌드 실패 시 그 자리에서 멈추고 사용자에게 알린다. 교체 단계는 실행 중인 앱을 덮어쓰는 작업이므로, 빌드 성공이 확인된 뒤에만 진행한다.

## 푸시 = main 머지까지 자동 진행

사용자가 "푸시", "push"라고 하면 별다른 지시가 없는 한 다음까지 한 번에 처리한다.

1. 변경 사항 커밋 (논리 단위로 분리)
2. `git fetch origin` 후 현재 브랜치를 `origin/main` 위로 rebase
3. `git push origin HEAD:main` 으로 fast-forward 푸시
4. 로컬 main 워크트리(`/Users/woogeunn/Work/Projects/up`)에서 `git merge --ff-only origin/main` 으로 동기화
5. 작업 브랜치가 원격에 남아 있으면 `git push origin --delete <branch>` 로 정리

이 프로젝트는 PR 없이 main 직접 푸시 워크플로우를 사용한다. 사용자가 명시적으로 "PR 만들어줘"라고 하지 않는 한 PR을 만들지 않는다.

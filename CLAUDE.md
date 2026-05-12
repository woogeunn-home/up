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

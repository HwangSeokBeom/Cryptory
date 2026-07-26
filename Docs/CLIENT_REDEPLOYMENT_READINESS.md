# Cryptory iOS redeployment readiness

검증 기준일: 2026-07-26
상태: `SIGNED_RELEASE_READY_DEVICE_VALIDATION_PENDING`

## 릴리스 계약

- Bundle ID: `com.hwb.Cryptory`
- Apple Team ID: `63SB2B8YJ5`
- Firebase project: `cryptory-342cf`
- REST: `https://cryptory.duckdns.org`
- WebSocket: `wss://cryptory.duckdns.org`
- App Review mode에서는 주문·거래·송금·입출금·지갑·private trading 진입점이
  모두 비활성화되어야 한다.

## 완료된 검증

- Swift package resolution
- Debug/Release simulator build
- App Store distribution certificate를 사용한 signed Release archive와 IPA export
- signed IPA 식별자 `com.hwb.Cryptory`, Team `63SB2B8YJ5`
- production APNs entitlement, `get-task-allow=false`, `beta-reports-active=true`
- unit tests 408/408
- Release readiness script
- secret scan
- `git diff --check`
- 공개 REST health/readiness
- 공개 WebSocket handshake
- 리뷰 계정 회원가입·로그인
- FCM token 등록·삭제 API 계약
- `PRICE_ALERT` payload가 시세 차트로만 라우팅되고 거래성 notification type 및
  stale trading deep link는 무시·차단되는 회귀 테스트
- Firebase Admin project `cryptory-342cf` 운영 초기화
- 서버 readiness 브랜치의 FCM HTTP v1 전환, production dependency audit 0건,
  unit/integration tests 378/378
- 실제 운영 Firebase 자격증명으로 OAuth 및 FCM validate-only 요청 성공
  (`INVALID_ARGUMENT` synthetic token 응답으로 인증·API 도달 확인, 실제 메시지
  전송 없음)
- 가격 알림 worker 활성화와 운영 review 계정의 임시 FCM token 등록·삭제
- App Review 금지 endpoint의 `403 FEATURE_DISABLED_FOR_APP_STORE`
- Cryptory Legal의 모든 공개 페이지가 HTTPS 200으로 응답

이 결과는 컴파일, App Store 서명·패키징, 서버 계약과 Firebase 인증 경로의
증거다. 실제 APNs/FCM 기기 전달이나 TestFlight 설치의 증거는 아니다.

## 현재 차단 항목

1. 실제 TestFlight 기기의 APNs/FCM token으로 가격 알림 push와 deep link를
   검증하지 않았다.
2. 운영 database에는 활성 실제 기기 FCM token이 0개이고 연결된 iPhone이
   Xcode에서 unavailable 상태이므로 전달 시험을 시작할 수 없다.
3. Legal 페이지의 지원·개인정보 이메일은 확정했지만 운영 주체, 주소, 보관
   기간, 관할 등 법적 placeholder는 별도 확인이 필요하다.
4. 기존 앱이 오타 호스트 `crytory.duckdns.org`를 사용하는 버전이라면
   canonical 호스트 강제 업데이트 또는 별도 호환 계획이 필요하다.
5. TestFlight 업로드·설치와 review 계정의 실제 기기 회귀 검증은 수행하지
   않았다.

## App Store 업로드 전 최종 게이트

1. Firebase Admin/APNs 연결 후 실제 기기 가격 알림 전달 및 deep link 확인
2. deep link가 차트/정보 화면만 열고 거래·지갑 화면을 열지 않는지 확인
3. 실제 review/legal 문서와 지원 연락처 확인
4. 생성된 signed IPA를 별도 승인 후 TestFlight에 업로드
5. 리뷰 계정으로 로그인·세션 갱신·가격 알림 생성/삭제 회귀 검증
6. 실제 기기 token 등록을 확인한 뒤 가격 알림 전달과 차트 deep link 검증

현재 결론은 `READY_FOR_EXPLICIT_TESTFLIGHT_UPLOAD_APPROVAL`이다. signed IPA와
서버·딥링크 정적/자동 검증은 완료됐지만, 사용자가 TestFlight 업로드를 승인하고
실제 iPhone을 연결하기 전에는 실제 push 전달 완료를 주장하지 않는다.

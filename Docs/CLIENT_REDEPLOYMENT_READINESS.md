# Cryptory iOS redeployment readiness

검증 기준일: 2026-07-26
상태: `SERVER_READY_CLIENT_RELEASE_PENDING`

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
- unsigned device archive
- unit tests 407/407
- Release readiness script
- secret scan
- `git diff --check`
- 공개 REST health/readiness
- 공개 WebSocket handshake
- 리뷰 계정 회원가입·로그인
- FCM token 등록·삭제 API 계약
- Firebase Admin project `cryptory-342cf` 운영 초기화
- 가격 알림 worker 활성화와 운영 review 계정의 임시 FCM token 등록·삭제
- App Review 금지 endpoint의 `403 FEATURE_DISABLED_FOR_APP_STORE`
- Cryptory Legal의 모든 공개 페이지가 HTTPS 200으로 응답

이 결과는 컴파일, 패키징, 서버 계약의 증거이며 서명된 App Store archive나
실제 APNs/FCM 전달의 증거는 아니다.

## 현재 차단 항목

1. 실제 TestFlight 기기의 APNs/FCM token으로 가격 알림 push와 deep link를
   검증하지 않았다.
2. Legal 페이지의 지원·개인정보 이메일은 확정했지만 운영 주체, 주소, 보관
   기간, 관할 등 법적 placeholder는 별도 확인이 필요하다.
3. 기존 앱이 오타 호스트 `crytory.duckdns.org`를 사용하는 버전이라면
   canonical 호스트 강제 업데이트 또는 별도 호환 계획이 필요하다.
4. Distribution signing, production APNs entitlement, TestFlight 설치 검증은
   아직 수행하지 않았다.

## App Store 업로드 전 최종 게이트

1. Firebase Admin/APNs 연결 후 실제 기기 가격 알림 전달 및 deep link 확인
2. deep link가 차트/정보 화면만 열고 거래·지갑 화면을 열지 않는지 확인
3. 실제 review/legal 문서와 지원 연락처 확인
4. 서명된 Release archive에서 Bundle ID, Team ID, production entitlement 확인
5. 리뷰 계정으로 로그인·세션 갱신·가격 알림 생성/삭제 회귀 검증
6. 별도 승인 후에만 TestFlight/App Store Connect 업로드

현재 결론은 `NO-GO_FOR_APP_STORE_UPLOAD`이다. 서버 REST/WSS, Firebase와
리뷰 계정 검증은 가능하지만 실제 기기 push, 남은 법적 정보와 서명된 archive가
완료되기 전에는 업로드하지 않는다.

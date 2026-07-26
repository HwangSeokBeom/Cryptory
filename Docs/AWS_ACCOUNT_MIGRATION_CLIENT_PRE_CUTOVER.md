# AWS 계정 이전 전 iOS 준비

서버를 새 AWS 계정으로 옮겨도 iOS Release는 같은 public hostname을 사용한다.

```text
REST: https://cryptory.duckdns.org
WS:   wss://cryptory.duckdns.org
```

따라서 DNS cutover 전에는 앱의 endpoint를 새 IP로 직접 바꾸지 않는다.

이미 배포된 앱은 과거 오타 호스트 `crytory.duckdns.org`를 참조할 수 있다.
새 Release는 위 canonical 호스트를 사용하되, 서버의 DNS·TLS·Nginx는 기존
앱의 강제 업데이트가 완료될 때까지 두 호스트를 함께 지원해야 한다.

## 고정 계약

- Bundle ID: `com.hwb.Cryptory`
- Apple Team ID: `63SB2B8YJ5`
- Firebase project: `cryptory-342cf`
- minimum iOS: 18.0
- App Review channel: 주문, 거래, 송금, 입출금, 지갑, private trading API 비활성
- FCM platform: `IOS`
- 가격 알림: 업비트·빗썸, KRW/BTC

## Push 준비

1. Apple Developer의 App ID에서 Push Notifications capability를 확인한다.
2. Distribution provisioning profile을 재생성하거나 갱신한다.
3. Release archive의 signed entitlements에서 `aps-environment=production`을 확인한다.
4. Firebase APNs key/certificate 연결을 확인한다.
5. TestFlight 전 테스트 기기로 FCM token 등록과 가격 알림 push를 검증한다.

소스 entitlements와 xcconfig만으로 provisioning과 실제 APNs 전달이 증명되지는 않는다.

## App Review 회귀 검증

- Release feature flags는 환경변수로 거래 기능을 다시 켤 수 없어야 한다.
- stale 거래 deep link는 정보성 화면으로 우회하거나 차단해야 한다.
- 서버는 App Review mode에서 거래성 endpoint를 403으로 거절해야 한다.
- 가격 알림 push는 차트만 열고 주문/지갑 화면을 열지 않아야 한다.

## 서버 cutover 전

1. `scripts/verify_release_readiness.sh`
2. Swift package resolution
3. Debug simulator build
4. Release simulator build
5. 전체 unit tests
6. UI tests
7. unsigned device archive
8. secret scan과 `git diff --check`

## 서버 cutover 후, App Store 업로드 전

1. 새 서버의 `/health`와 `/ready` 확인
2. REST 로그인과 token refresh
3. 공개 WSS subscribe/reconnect
4. App Review 거래 endpoint 차단
5. FCM token 등록/삭제
6. 가격 알림 생성/전달/deep-link
7. signed Release archive/export

TestFlight/App Store 업로드는 서버 cutover 안정화와 rollback 관찰이 끝난 뒤 별도 승인으로 수행한다.

# Exchange API Architecture

## 목적

- 상단 헤더의 거래소 선택은 `CryptoViewModel.selectedExchange`를 단일 source of truth 로 사용한다.
- 거래소 메타데이터는 `Exchange` enum 에서 관리하고, 화면은 capability 기반으로 기능 노출 여부를 판단한다.
- 실제 거래소 연동은 화면 단위가 아니라 책임 단위로 나눈다.
  - `MarketData`: 시세, 호가, 체결, 캔들
  - `Trading`: 주문 가능 정보, 주문 생성/취소, 주문 상태
  - `Portfolio`: 잔고, 평균 매수가, 평가금액, 입출금/체결 이력
  - `KimchiPremium`: 국내 현재가, 해외 기준가, 환율, 환산 로직

## 거래소 메타데이터

현재 앱은 `Exchange` enum 의 metadata 를 통해 아래 정보를 가진다.

- `id`
- `displayName`
- `shortName`
- `iconImageName`
- `supportsOrder`
- `supportsAsset`
- `supportsChart`
- `supportsKimchiPremium`

권장 원칙:

- `selectedExchange` 는 "현재 화면이 참조하는 주 거래소"만 표현한다.
- 김프 탭은 `selectedExchange` 와 별개로 국내 거래소 집합 + 해외 기준 거래소 집합을 병렬로 참조한다.
- Binance 는 김프 기준가/해외 기준 가격용 provider 로 두고, 국내 거래소 CRUD 와는 분리한다.

## 서버 `.env` 준비 원칙

서버 작업자는 [server.env.example](/Users/hwangseokbeom/Documents/GitHub/Cryptory/server.env.example) 를 기준으로 환경변수를 채우면 된다.

공통 원칙:

- Public 시세/호가/차트만 쓸 때는 대부분 API 키가 없어도 된다.
- 주문/자산/private websocket 을 쓰려면 거래소 사이트에서 API Key 를 발급하고 허용 IP 를 등록해야 한다.
- 발급 시 권한은 최소 권한으로 분리한다.
  - 시세 전용
  - 주문 조회
  - 주문 실행
  - 자산 조회
- 서버는 사용자별 연결 정보를 DB 에 저장하고, `.env` 에는 거래소 앱 레벨 설정과 암호화 키만 둔다.
- 단일 운영 계정으로 자산/주문을 대행하지 말고, 거래소 연결별 사용자 키를 암호화 저장하는 구조를 권장한다.

거래소별 발급 요약:

- Upbit
  - 발급값: `Access Key`, `Secret Key`
  - 추가 설정: 허용 IP, `자산조회` `주문조회` `주문하기` 등 필요한 권한 체크
- Bithumb
  - 발급값: `API Key`, `Secret Key`
  - 추가 설정: 허용 IP, `자산조회` `주문조회` `주문하기` 등 활성화
  - 인증: JWT Bearer
- Coinone
  - 발급값: `Access Token`, `Secret Key`
  - 추가 설정: API 카테고리별 권한 선택
  - 인증: `X-COINONE-PAYLOAD`, `X-COINONE-SIGNATURE`
- Korbit
  - 발급값: `API Key`, `Secret Key`
  - 추가 설정: 권한 선택, 허용 정책 확인
  - 인증: 기본은 HMAC-SHA256, 환경에 따라 Ed25519 지원 가능

## 서버에 필요한 거래소별 연결 정보

### Upbit

- Base URL: `https://api.upbit.com`
- Public WS: `wss://api.upbit.com/websocket/v1`
- Private WS: `wss://api.upbit.com/websocket/v1/private`
- Credentials:
  - `UPBIT_ACCESS_KEY`
  - `UPBIT_SECRET_KEY`
- 필수 REST:
  - 시세 목록: ticker / market list
  - 차트: minute/day/week/month candle
  - 호가: orderbook
  - 최근 체결: trades/ticks
  - 주문 가능 정보: `GET /v1/orders/chance`
  - 주문 생성: `POST /v1/orders`
  - 주문 취소: `DELETE /v1/order`
  - 주문 조회: `GET /v1/orders`, `GET /v1/order`
  - 자산: account balances
- 필수 WS:
  - `ticker`
  - `orderbook`
  - `trade`
  - `candle.{unit}`
  - `myOrder`
  - `myAsset`

### Bithumb

- Base URL: `https://api.bithumb.com`
- Public/Private WS: `wss://ws-api.bithumb.com/websocket/v1`
- Credentials:
  - `BITHUMB_ACCESS_KEY`
  - `BITHUMB_SECRET_KEY`
- 필수 REST:
  - 거래 대상 목록: `GET /v1/market/all`
  - 현재가: `GET /v1/ticker`
  - 호가: `GET /v1/orderbook`
  - 최근 체결: `GET /v1/trades/ticks`
  - 차트: `GET /v1/candles/minutes/{unit}`, `GET /v1/candles/days`, `GET /v1/candles/weeks`, `GET /v1/candles/months`
  - 자산: `GET /v1/accounts`
  - 주문 가능 정보: `GET /v1/orders/chance`
  - 주문 생성: `POST /v1/orders`
  - 주문 취소: `DELETE /v1/order`
  - 주문 조회: `GET /v1/orders`, `GET /v1/order`
- 필수 WS:
  - `ticker`
  - `orderbook`
  - `trade`
  - `myOrder`
  - `myAsset`

### Coinone

- Base URL: `https://api.coinone.co.kr`
- Public WS: `wss://stream.coinone.co.kr`
- Private WS: `wss://stream.coinone.co.kr/v1/private`
- Credentials:
  - `COINONE_ACCESS_TOKEN`
  - `COINONE_SECRET_KEY`
- 필수 REST:
  - 거래 대상/정책: `GET /public/v2/markets`, `GET /public/v2/range_units`, `GET /public/v2/markets/{quote_currency}/{target_currency}`
  - 현재가: `GET /public/v2/ticker_new/{quote_currency}/{target_currency}`
  - 호가: `GET /public/v2/orderbook/{quote_currency}/{target_currency}`
  - 최근 체결: `GET /public/v2/trades/{quote_currency}/{target_currency}`
  - 차트: `GET /public/v2/chart/{quote_currency}/{target_currency}`
  - 자산: `POST /v2.1/account/balance/all`
  - 주문 생성: `POST /v2.1/order`
  - 주문 취소: `POST /v2.1/order/cancel`
  - 미체결: `POST /v2.1/order/active_orders`
  - 주문 상세: `POST /v2.1/order/detail`
  - 체결 내역: `POST /v2.1/order/completed_orders`, `POST /v2.1/order/completed_orders/all`
- 필수 WS:
  - `TICKER`
  - `ORDERBOOK`
  - `TRADE`
  - `CHART`
  - `MYORDER`
  - `MYASSET`

### Korbit

- Base URL: `https://api.korbit.co.kr`
- Public WS: `wss://ws-api.korbit.co.kr/v2/public`
- Private WS: `wss://ws-api.korbit.co.kr/v2/private`
- Credentials:
  - `KORBIT_API_KEY`
  - `KORBIT_SECRET_KEY`
- 필수 REST:
  - 거래쌍 정책: `GET /v2/tradingPairs`
  - 현재가: `GET /v2/tickers`
  - 호가: `GET /v2/orderbook`
  - 최근 체결: `GET /v2/trades`
  - 차트: `GET /v2/candles`
  - 자산: `GET /v2/balance`
  - 주문 생성: `POST /v2/orders`
  - 주문 취소: `DELETE /v2/orders`
  - 개별 주문: `GET /v2/orders`
  - 미체결: `GET /v2/openOrders`
  - 최근 주문 목록: `GET /v2/allOrders`
  - 최근 체결 목록: `GET /v2/myTrades`
- 필수 WS:
  - `ticker`
  - `orderbook`
  - `trade`
  - `myOrder`
  - `myTrade`
  - `myAsset`

## 화면 책임 기준 API 분류

### 1. 시세 탭

필요 데이터:

- 거래 대상 목록
- 현재가
- 24H 변동률
- 24H 거래대금/거래량
- 관심종목 행 갱신용 실시간 ticker

권장 책임:

- 초기 진입: REST snapshot
- 화면 유지: WebSocket ticker
- 행 선택 시: 선택 종목 상세 화면으로 symbol 전달

거래소별 권장 매핑:

- Upbit
  - REST: 거래쌍, 현재가
  - WS: `ticker`
- Bithumb
  - REST: `GET /v1/ticker`
  - WS: `ticker`
- Coinone
  - REST: `GET /public/v2/ticker_new/{quote_currency}/{target_currency}`
  - WS: `TICKER`
- Korbit
  - REST: `GET /v2/tickers`
  - WS: `ticker`

### 2. 차트 탭

필요 데이터:

- 캔들 조회
- 현재가/등락률
- 호가
- 최근 체결
- 차트 최신 봉 갱신
- 보조지표 계산용 OHLCV

권장 책임:

- 초기 진입: REST 캔들 + REST 호가 + REST 최근 체결
- 실시간 유지:
  - ticker: 현재가/등락률
  - orderbook: 호가
  - trades: 최근 체결
  - chart/candle websocket 이 있으면 최신 봉만 incremental merge

기간 대응:

- 앱 공통 period enum 을 두고 거래소 interval 문자열로 매핑한다.
- 거래소별 미지원 interval 은 nearest fallback 으로 변환한다.

추천 공통 interval 예시:

- `1m`, `3m`, `5m`, `15m`, `30m`, `1h`, `4h`, `1d`, `1w`

거래소별 차트 API:

- Upbit
  - REST: 분/일/주/월/연 캔들
  - WS: `candle.{unit}` 는 초/분 실시간 갱신용으로 사용
  - 주의: 체결이 없는 구간은 캔들이 생성되지 않는다.
- Bithumb
  - REST: `/v1/candles/minutes/{unit}`, `/v1/candles/days`, `/v1/candles/weeks`, `/v1/candles/months`
  - WS: public websocket 은 `ticker`, `orderbook`, `trade` 중심으로 보고, 차트 최신 봉은 trade/ticker 기반 합성 fallback 을 둔다.
- Coinone
  - REST: `GET /public/v2/chart/{quote_currency}/{target_currency}`
  - WS: `CHART`
  - 지원 interval: `1m`, `3m`, `5m`, `15m`, `30m`, `1h`, `2h`, `4h`, `6h`, `1d`, `1w`, `1mon`
- Korbit
  - REST: `GET /v2/candles`
  - WS: 별도 candle 채널 대신 `ticker` + `trade` 로 최신 상태를 반영하는 쪽이 안전하다.
  - 지원 interval: `1`, `5`, `15`, `30`, `60`, `240`, `1D`, `1W`

보조지표 계산 필드:

- `timestamp`
- `open`
- `high`
- `low`
- `close`
- `volume`
- 필요 시 `quoteVolume`

### 3. 주문 탭

필요 데이터:

- 주문 가능 마켓 목록
- 주문 가능 정책
  - 최소 주문 금액
  - 최소/최대 수량
  - 호가 단위
  - 지원 주문 타입
- 현재가
- 호가
- 주문 생성
- 주문 취소
- 미체결 주문 조회
- 주문 상세 조회
- 체결 내역 조회
- 주문 상태 실시간 반영

권장 책임:

- 주문 입력 전:
  - market metadata REST
  - current ticker REST/WS
  - orderbook REST/WS
- 주문 후:
  - REST create/cancel
  - private websocket 으로 optimistic status reconcile
  - private websocket 미지원/불안정 시 `order detail` polling fallback

거래소별 주문 API:

- Upbit
  - REST: 주문 가능 정보 조회, 주문 생성, 주문 취소, 주문 리스트 조회
  - WS: `myOrder`
  - 인증: private 필수
- Bithumb
  - REST: `GET /v1/orders/chance`, `POST /v1/orders`, `DELETE /v1/order`, `GET /v1/orders`, `GET /v1/order`
  - WS: `MyOrder`
  - 인증: JWT private 필수
- Coinone
  - REST:
    - 주문 가능 정보: `GET /public/v2/markets/{quote_currency}/{target_currency}`
    - 주문 생성: `POST /v2.1/order`
    - 주문 취소: `POST /v2.1/order/cancel`
    - 미체결 주문: `POST /v2.1/order/active_orders`
    - 주문 상세: `POST /v2.1/order/detail`
    - 체결 주문 조회: `POST /v2.1/order/completed_orders`, `POST /v2.1/order/completed_orders/all`
  - WS: `MYORDER`
  - 인증: private 필수
- Korbit
  - REST:
    - 주문 생성: `POST /v2/orders`
    - 주문 취소: `DELETE /v2/orders`
    - 개별 주문 조회: `GET /v2/orders`
    - 미체결 주문 조회: `GET /v2/openOrders`
    - 최근 주문 목록: `GET /v2/allOrders`
    - 최근 체결 내역: `GET /v2/myTrades`
  - WS: `myOrder`, `myTrade`
  - 인증: private 필수

### 4. 자산 탭

필요 데이터:

- 보유 자산 목록
- 사용 가능 수량
- 주문 중 묶인 수량
- 평균 매수가
- 총 평가금액
- 평가손익 / 수익률
- 최근 체결/입출금 이력

평가 계산 최소 필드:

- `currency/symbol`
- `balance`
- `available`
- `locked` 또는 `tradeInUse`
- `avgBuyPrice`
- 현재가 ticker

거래소별 자산 API:

- Upbit
  - REST: 전체 계좌 조회
  - WS: `myAsset`
- Bithumb
  - REST: `GET /v1/accounts`
  - WS: `MyAsset`
- Coinone
  - REST: `POST /v2.1/account/balance/all`
  - WS: `MYASSET`
- Korbit
  - REST: `GET /v2/balance`
  - WS: `myAsset`

폴링 정책:

- private websocket 이 있으면 websocket 우선
- 앱 재진입/foreground 복귀 시 REST snapshot 재동기화
- websocket reconnect 이후 반드시 REST snapshot 으로 정합성 복구

### 5. 김프 탭

필요 데이터 소스:

- 국내 거래소 현재가
  - Upbit / Bithumb / Coinone / Korbit ticker
- 해외 기준 가격
  - Binance BTC/USDT 또는 대상 코인/USDT
- 환율
  - USD/KRW 실시간 또는 주기적 REST snapshot
- 환산 기준
  - 직접 KRW 마켓이 없으면 `coin/USDT * USDKRW`
  - BTC 마켓만 있으면 `coin/BTC * BTC/USDT * USDKRW`

최소 필드:

- `symbol`
- `domesticPriceKRW`
- `globalPrice`
- `globalQuoteCurrency`
- `usdKrwRate`
- `convertedGlobalPriceKRW`
- `premiumPercent`
- `timestamp`

계산식:

- `convertedGlobalPriceKRW = globalPrice * usdKrwRate`
- `kimchiPremiumPercent = ((domesticPriceKRW - convertedGlobalPriceKRW) / convertedGlobalPriceKRW) * 100`

주의사항:

- 해외 기준 거래소와 국내 거래소의 심볼 체계가 다르므로 canonical symbol 매핑이 필요하다.
- 스테이블코인 기준이 `USDT`, `USDC`, `FDUSD` 등으로 바뀔 수 있으므로 `GlobalReferencePriceSource` 를 분리한다.
- 환율은 동일 timestamp 근처 데이터로 맞추고, stale data threshold 를 둔다.

## 권장 앱 구조

```swift
protocol ExchangeMarketDataProvider {
    var exchange: Exchange { get }
    func fetchTickerSnapshot(symbols: [String]) async throws -> [TickerSnapshot]
    func fetchCandles(symbol: String, interval: ChartInterval, limit: Int) async throws -> [Candle]
    func fetchOrderbook(symbol: String) async throws -> OrderbookSnapshot
    func fetchRecentTrades(symbol: String, limit: Int) async throws -> [TradeTick]
}

protocol ExchangeStreamingProvider {
    var exchange: Exchange { get }
    func subscribe(_ subscriptions: Set<ExchangeStreamSubscription>)
    func unsubscribeAll()
}

protocol ExchangeTradingProvider {
    var exchange: Exchange { get }
    func fetchOrderChance(symbol: String) async throws -> OrderChance
    func createOrder(_ request: ExchangeOrderRequest) async throws -> ExchangeOrderReceipt
    func cancelOrder(orderID: String, symbol: String) async throws
    func fetchOpenOrders(symbol: String?) async throws -> [ExchangeOrder]
    func fetchOrderDetail(orderID: String, symbol: String?) async throws -> ExchangeOrder
    func fetchRecentExecutions(symbol: String?) async throws -> [ExchangeExecution]
}

protocol ExchangePortfolioProvider {
    var exchange: Exchange { get }
    func fetchBalances() async throws -> [ExchangeBalance]
    func fetchAssetHistory() async throws -> AssetHistorySnapshot
}
```

앱 레이어에서는 아래처럼 registry 를 둔다.

```swift
struct ExchangeProviderRegistry {
    let marketData: [Exchange: ExchangeMarketDataProvider]
    let streaming: [Exchange: ExchangeStreamingProvider]
    let trading: [Exchange: ExchangeTradingProvider]
    let portfolio: [Exchange: ExchangePortfolioProvider]
}
```

## 확장 원칙

- 화면은 거래소별 endpoint 를 직접 알지 않는다.
- 모든 화면은 canonical domain model 만 소비한다.
- 거래소별 차이는 adapter 내부에서만 처리한다.
  - 심볼 포맷 차이
  - interval 차이
  - 주문 타입 차이
  - private 인증 차이
  - websocket 채널 차이
- websocket 이 없는 기능은 REST polling fallback 을 명시적으로 둔다.
- 신규 거래소 추가 시 수정 범위는 아래로 제한한다.
  - `Exchange` metadata 1곳
  - provider 구현체 추가
  - registry 등록
  - symbol mapper 추가
  - capability 테스트 추가

## 공식 문서

- Upbit: https://docs.upbit.com
- Bithumb: https://apidocs.bithumb.com
- Coinone: https://docs.coinone.co.kr
- Korbit: https://docs.korbit.co.kr

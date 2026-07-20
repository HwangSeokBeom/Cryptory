import XCTest
@testable import Cryptory

/// Regression coverage for the two shared-state flakes fixed on this branch.
///
/// 1. `AssetImageClient` failure state (terminal placeholder + URL-keyed
///    cooldown) polluted the `.shared` singleton across tests that reused the
///    same fixture image URL. Tests now inject namespaced instances; this
///    suite proves failure state cannot cross client-instance boundaries.
/// 2. `CandleAggregator` drops trades whose bucket is older than the last
///    candle. A test that stamped a live trade with its own `Date()` raced
///    the wall-clock minute boundary against the view model's candle
///    synthesis. These tests pin the aggregator's bucket semantics so the
///    fixed test (bucket-anchored timestamps) stays deterministic.
final class TestIsolationRegressionTests: XCTestCase {
    // MARK: - AssetImageClient instance isolation

    func testImageFailureStateDoesNotLeakAcrossClientInstances() async {
        // A file URL to a nonexistent path fails deterministically with no
        // network involved.
        let descriptor = AssetImageRequestDescriptor(
            marketIdentity: MarketIdentity(exchange: .upbit, marketId: "KRW-ISOTEST", symbol: "ISOTEST"),
            symbol: "ISOTEST",
            canonicalSymbol: "ISOTEST",
            imageURL: "/nonexistent/cryptory-isolation-test/\(UUID().uuidString).png",
            hasImage: true,
            localAssetName: nil
        )

        let pollutedClient = AssetImageClient(namespace: UUID().uuidString)
        let handle = pollutedClient.prepareImageRequest(for: descriptor, mode: .visible)
        if let outcomeTask = handle.outcomeTask {
            _ = await outcomeTask.value
        }

        XCTAssertEqual(
            pollutedClient.assetState(for: descriptor),
            .placeholderFinal,
            "the failed fetch must record a terminal failure in the requesting client"
        )

        // A different client instance — the situation every test is in after
        // the isolation fix — must not observe the failure.
        let freshClient = AssetImageClient(namespace: UUID().uuidString)
        XCTAssertNotEqual(
            freshClient.assetState(for: descriptor),
            .placeholderFinal,
            "terminal failure state must not leak across AssetImageClient instances"
        )
    }

    // MARK: - CandleAggregator bucket semantics

    private let bucket = 1_700_000_000 / 60 * 60

    private func candle(time: Int, close: Double) -> CandleData {
        CandleData(time: time, open: close - 1, high: close + 1, low: close - 2, close: close, volume: 10)
    }

    func testMergeUpdatesExistingBucketRegardlessOfWallClock() {
        // Trades stamped inside an existing candle's bucket must merge into
        // it — this is what the fixed chart test relies on, and it is
        // independent of the wall clock at merge time.
        let candles = [candle(time: bucket - 60, close: 124.8), candle(time: bucket, close: 125.0)]
        let merged = CandleAggregator.merge(
            snapshot: candles,
            price: 126.1,
            quantity: 0.25,
            timestamp: Date(timeIntervalSince1970: TimeInterval(bucket) + 1),
            timeframe: "1m"
        )

        XCTAssertNotNil(merged)
        XCTAssertEqual(merged?.didAppend, false)
        XCTAssertEqual(merged?.candles.count, 2)
        XCTAssertEqual(merged?.candles.last?.close, 126.1)
        XCTAssertEqual(merged?.candles.last?.volume, 11)
    }

    func testMergeDropsTradeFromClosedBucket() {
        // Documented policy: a trade older than the newest candle's bucket
        // (and matching no existing candle) is discarded rather than
        // rewriting history. This drop is what surfaced as the flake when a
        // test's Date() capture crossed a minute boundary before merge.
        let candles = [candle(time: bucket, close: 125.0)]
        let merged = CandleAggregator.merge(
            snapshot: candles,
            price: 126.1,
            quantity: 0.25,
            timestamp: Date(timeIntervalSince1970: TimeInterval(bucket - 120)),
            timeframe: "1m"
        )

        XCTAssertNotNil(merged)
        XCTAssertEqual(merged?.didAppend, false)
        XCTAssertEqual(merged?.candles.count, 1)
        XCTAssertEqual(merged?.candles.last?.close, 125.0, "closed buckets must not be rewritten by late trades")
    }
}

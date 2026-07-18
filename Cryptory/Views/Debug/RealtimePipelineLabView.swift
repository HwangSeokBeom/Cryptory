#if DEBUG
import SwiftUI

/// DEBUG-only diagnostics screen for the public market stream pipeline.
///
/// Shows the engine's bounded in-memory metrics (no payloads, no user data)
/// and offers simulations that act on the local engine only. The whole screen
/// is compiled out of Release builds.
///
/// Accessibility: standard Dynamic Type text styles throughout, state is
/// conveyed with text (never color alone), metric rows are marked
/// `updatesFrequently` so VoiceOver does not announce every refresh, and the
/// simulation buttons are full-width default-height tap targets.
struct RealtimePipelineLabView: View {
    @StateObject private var viewModel: RealtimePipelineLabViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(engine: MarketStreamEngine) {
        _viewModel = StateObject(wrappedValue: RealtimePipelineLabViewModel(engine: engine))
    }

    var body: some View {
        List {
            Section("Connection") {
                metricRow("State", viewModel.stateDescription)
                metricRow("Generation", "\(viewModel.snapshot.generation)")
                metricRow("Uptime", viewModel.uptimeDescription)
                metricRow("Active subscriptions", "\(viewModel.snapshot.activeSubscriptionCount)")
                metricRow("Upstream subscriptions", "\(viewModel.snapshot.upstreamSubscriptionCount)")
            }

            Section("Messages") {
                metricRow("Received", "\(viewModel.snapshot.messagesReceived)")
                metricRow("Decoded", "\(viewModel.snapshot.messagesDecoded)")
                metricRow("Decode failures", "\(viewModel.snapshot.decodeFailures)")
                metricRow("Emitted", "\(viewModel.snapshot.messagesEmitted)")
                metricRow("Tickers coalesced", "\(viewModel.snapshot.tickersCoalesced)")
                metricRow("Dropped (explicit)", "\(viewModel.snapshot.eventsDropped)")
                metricRow("Stale ignored", "\(viewModel.snapshot.staleEventsIgnored)")
            }

            Section("Latency") {
                metricRow("Latest", viewModel.latencyDescription(viewModel.snapshot.latestEventLatency))
                metricRow("p50", viewModel.latencyDescription(viewModel.snapshot.latencyP50))
                metricRow("p95", viewModel.latencyDescription(viewModel.snapshot.latencyP95))
                metricRow("Max buffer usage", "\(viewModel.snapshot.maxBufferUsage)")
            }

            Section("Reconnect & heartbeat") {
                metricRow("Reconnects", "\(viewModel.snapshot.reconnectCount)")
                metricRow("Consecutive failures", "\(viewModel.snapshot.consecutiveReconnectFailures)")
                metricRow("Last disconnect reason", viewModel.snapshot.lastDisconnectReason ?? "—")
                metricRow("Heartbeat successes", "\(viewModel.snapshot.heartbeatSuccessCount)")
                metricRow("Heartbeat failures", "\(viewModel.snapshot.heartbeatFailureCount)")
            }

            Section("Simulations (local engine only)") {
                Button("Simulate connection failure") {
                    viewModel.simulateConnectionFailure()
                }
                Button("Simulate heartbeat timeout") {
                    viewModel.simulateHeartbeatTimeout()
                }
                Button("Rapid subscription replacement") {
                    viewModel.simulateRapidSubscriptionReplacement()
                }
                Button("Replay 1k-ticker fixture burst") {
                    viewModel.replayFixtureBurst()
                }
                if let action = viewModel.lastActionDescription {
                    Text(action)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .animation(reduceMotion ? nil : .default, value: viewModel.snapshot)
        .navigationTitle("Realtime Pipeline Lab")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.startPolling() }
        .onDisappear { viewModel.stopPolling() }
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
        .accessibilityAddTraits(.updatesFrequently)
    }
}
#endif

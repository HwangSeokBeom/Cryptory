import Foundation
import Translation

enum TranslationState: String, Codable, Equatable, Hashable {
    case notRequested
    case preparing
    case translating
    case translated
    case failed
    case unavailable
    case originalOnly

    var badgeText: String? {
        switch self {
        case .translated:
            return "번역됨"
        case .failed:
            return "번역 실패 · 원문 표시 중"
        case .unavailable:
            return "번역 불가 · 원문 제공"
        case .originalOnly:
            return "원문 제공"
        case .notRequested, .preparing, .translating:
            return nil
        }
    }
}

struct TranslationRequestItem: Equatable {
    let id: String
    let text: String
    let sourceLanguage: String?
}

struct TranslationResultItem: Codable, Equatable {
    let id: String
    let originalText: String
    let translatedText: String?
    let sourceLanguage: String?
    let targetLanguage: String
    let provider: String?
    let state: TranslationState
}

struct TranslatableTextViewState: Equatable {
    let originalText: String
    let translatedText: String?
    let originalLanguage: String?
    let targetLanguage: String
    let state: TranslationState
    var showsOriginal: Bool

    var displayText: String {
        if showsOriginal {
            return originalText
        }
        return translatedText?.trimmedNonEmpty ?? originalText
    }

    var isShowingTranslation: Bool {
        showsOriginal == false && translatedText?.trimmedNonEmpty != nil
    }

    var translationBadgeText: String? {
        isShowingTranslation && state == .translated ? state.badgeText : nil
    }

    var toggleTitle: String? {
        guard translatedText?.trimmedNonEmpty != nil else { return nil }
        return showsOriginal ? "번역 보기" : "원문 보기"
    }
}

protocol ClientTranslationServiceProtocol {
    func translate(items: [TranslationRequestItem], targetLanguage: String, context: String, symbol: String?) async -> [TranslationResultItem]
}

actor TranslationCache {
    static let shared = TranslationCache()

    private let defaultsKey = "cryptory.translation.cache.v1"
    private var values: [String: TranslationResultItem] = [:]
    private var inFlight: [String: Task<TranslationResultItem, Never>] = [:]

    init() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: TranslationResultItem].self, from: data) else {
            return
        }
        values = decoded
    }

    func value(for key: String) -> TranslationResultItem? {
        values[key]
    }

    func setValue(_ value: TranslationResultItem, for key: String) {
        values[key] = value
        persist()
    }

    func task(for key: String) -> Task<TranslationResultItem, Never>? {
        inFlight[key]
    }

    func setTask(_ task: Task<TranslationResultItem, Never>, for key: String) {
        inFlight[key] = task
    }

    func removeTask(for key: String) {
        inFlight[key] = nil
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}

struct AppleTranslationService: ClientTranslationServiceProtocol {
    func translate(
        items: [TranslationRequestItem],
        targetLanguage: String,
        context: String,
        symbol: String?
    ) async -> [TranslationResultItem] {
        guard #available(iOS 26.0, *) else {
            AppLogger.debug(.network, "[AppleTranslation] context=\(context) status=unavailable reason=ios_below_26 itemCount=\(items.count)")
            return items.map {
                TranslationResultItem(
                    id: $0.id,
                    originalText: $0.text,
                    translatedText: nil,
                    sourceLanguage: $0.sourceLanguage,
                    targetLanguage: targetLanguage,
                    provider: "apple_translation",
                    state: .unavailable
                )
            }
        }

        return await AppleTranslationRuntime.translate(
            items: items,
            targetLanguage: targetLanguage,
            context: context,
            symbol: symbol
        )
    }
}

@available(iOS 26.0, *)
private enum AppleTranslationRuntime {
    static func translate(
        items: [TranslationRequestItem],
        targetLanguage: String,
        context: String,
        symbol: String?
    ) async -> [TranslationResultItem] {
        let target = Locale.Language(identifier: targetLanguage)
        let availability = LanguageAvailability()
        var grouped: [String: [TranslationRequestItem]] = [:]

        for item in items {
            let source = item.sourceLanguage?.trimmedNonEmpty ?? "en"
            grouped[source, default: []].append(item)
        }

        var results: [TranslationResultItem] = []
        for (sourceIdentifier, sourceItems) in grouped {
            let source = Locale.Language(identifier: sourceIdentifier)
            let status = await availability.status(from: source, to: target)
            guard status != .unsupported else {
                AppLogger.debug(.network, "[AppleTranslation] context=\(context) source=\(sourceIdentifier) target=\(targetLanguage) status=unsupported itemCount=\(sourceItems.count)")
                results += sourceItems.map {
                    TranslationResultItem(
                        id: $0.id,
                        originalText: $0.text,
                        translatedText: nil,
                        sourceLanguage: sourceIdentifier,
                        targetLanguage: targetLanguage,
                        provider: "apple_translation",
                        state: .unavailable
                    )
                }
                continue
            }

            let session = TranslationSession(installedSource: source, target: target)
            do {
                AppLogger.debug(.network, "[AppleTranslation] context=\(context) symbol=\(symbol ?? "nil") source=\(sourceIdentifier) target=\(targetLanguage) status=prepare itemCount=\(sourceItems.count)")
                try await session.prepareTranslation()
                let requests = sourceItems.map {
                    TranslationSession.Request(sourceText: $0.text, clientIdentifier: $0.id)
                }
                let responses = try await session.translations(from: requests)
                let byId = Dictionary(uniqueKeysWithValues: responses.compactMap { response -> (String, TranslationSession.Response)? in
                    guard let id = response.clientIdentifier else { return nil }
                    return (id, response)
                })
                for item in sourceItems {
                    let translated = byId[item.id]?.targetText.trimmedNonEmpty
                    results.append(
                        TranslationResultItem(
                            id: item.id,
                            originalText: item.text,
                            translatedText: translated,
                            sourceLanguage: sourceIdentifier,
                            targetLanguage: targetLanguage,
                            provider: "apple_translation",
                            state: translated == nil ? .failed : .translated
                        )
                    )
                }
                AppLogger.debug(.network, "[AppleTranslation] context=\(context) source=\(sourceIdentifier) target=\(targetLanguage) status=success itemCount=\(sourceItems.count) translatedCount=\(responses.count)")
            } catch {
                AppLogger.debug(.network, "[AppleTranslation] context=\(context) source=\(sourceIdentifier) target=\(targetLanguage) status=fallback_original error=\(error.localizedDescription)")
                results += sourceItems.map {
                    TranslationResultItem(
                        id: $0.id,
                        originalText: $0.text,
                        translatedText: nil,
                        sourceLanguage: sourceIdentifier,
                        targetLanguage: targetLanguage,
                        provider: "apple_translation",
                        state: .failed
                    )
                }
            }
        }
        return results
    }
}

struct TranslationUseCase {
    let service: ClientTranslationServiceProtocol
    let cache: TranslationCache
    let maxBatchSize: Int

    init(
        service: ClientTranslationServiceProtocol = AppleTranslationService(),
        cache: TranslationCache = .shared,
        maxBatchSize: Int = 20
    ) {
        self.service = service
        self.cache = cache
        self.maxBatchSize = maxBatchSize
    }

    func translate(
        items: [TranslationRequestItem],
        targetLanguage: String = "ko",
        context: String,
        symbol: String? = nil
    ) async -> [String: TranslationResultItem] {
        let normalizedItems = items.compactMap { item -> TranslationRequestItem? in
            guard let cleaned = Self.cleanText(item.text)?.trimmedNonEmpty else { return nil }
            return TranslationRequestItem(id: item.id, text: cleaned, sourceLanguage: item.sourceLanguage)
        }
        guard normalizedItems.isEmpty == false else { return [:] }

        var results: [String: TranslationResultItem] = [:]
        var missingByCacheKey: [String: TranslationRequestItem] = [:]
        var idsByCacheKey: [String: [String]] = [:]

        for item in normalizedItems {
            let key = cacheKey(item: item, targetLanguage: targetLanguage, context: context, symbol: symbol)
            idsByCacheKey[key, default: []].append(item.id)
            if let cached = await cache.value(for: key) {
                for id in idsByCacheKey[key] ?? [item.id] {
                    results[id] = remap(cached, to: id)
                }
                AppLogger.debug(.network, "[TranslationCache] context=\(context) id=\(item.id) hit=true")
            } else if missingByCacheKey[key] == nil {
                missingByCacheKey[key] = item
            }
        }

        let missing = Array(missingByCacheKey.values)
        for chunk in missing.chunked(into: maxBatchSize) {
            let translated = await service.translate(
                items: chunk,
                targetLanguage: targetLanguage,
                context: context,
                symbol: symbol
            )
            for result in translated {
                let request = chunk.first { $0.id == result.id } ?? TranslationRequestItem(id: result.id, text: result.originalText, sourceLanguage: result.sourceLanguage)
                let key = cacheKey(item: request, targetLanguage: targetLanguage, context: context, symbol: symbol)
                if result.state == .translated {
                    await cache.setValue(result, for: key)
                }
                for id in idsByCacheKey[key] ?? [result.id] {
                    results[id] = remap(result, to: id)
                }
            }
        }

        return results
    }

    func translateOne(
        id: String,
        text: String,
        sourceLanguage: String? = "en",
        targetLanguage: String = "ko",
        context: String,
        symbol: String? = nil
    ) async -> TranslationResultItem {
        let item = TranslationRequestItem(id: id, text: text, sourceLanguage: sourceLanguage)
        return await translate(items: [item], targetLanguage: targetLanguage, context: context, symbol: symbol)[id]
            ?? TranslationResultItem(id: id, originalText: text, translatedText: nil, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage, provider: "apple_translation", state: .failed)
    }

    private func remap(_ result: TranslationResultItem, to id: String) -> TranslationResultItem {
        TranslationResultItem(
            id: id,
            originalText: result.originalText,
            translatedText: result.translatedText,
            sourceLanguage: result.sourceLanguage,
            targetLanguage: result.targetLanguage,
            provider: result.provider,
            state: result.state
        )
    }

    private func cacheKey(item: TranslationRequestItem, targetLanguage: String, context: String, symbol: String?) -> String {
        let normalized = Self.normalizedText(item.text)
        return "\(context)|\(symbol ?? "-")|\(item.id)|\(item.sourceLanguage ?? "auto")|\(targetLanguage)|\(Self.stableHash(normalized))"
    }

    static func cleanText(_ value: String?) -> String? {
        guard var value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else {
            return nil
        }
        value = value
            .replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)</p\s*>"#, with: "\n\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)<p[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        value = value.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }

    private static func stableHash(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

import Foundation

struct TradeTimestampParseResult: Equatable {
    let date: Date?
    let displayText: String
    let source: String?
}

enum TradeTimestampParser {
    static func parse(
        candidates: [(source: String, rawValue: Any?)],
        logContext: String
    ) -> TradeTimestampParseResult {
        var firstNonNilCandidate: (source: String, rawValue: Any)?

        for candidate in candidates {
            guard let rawValue = candidate.rawValue else {
                continue
            }

            if firstNonNilCandidate == nil {
                firstNonNilCandidate = (candidate.source, rawValue)
            }

            if let parsed = parseSingle(rawValue, source: candidate.source, logContext: logContext) {
                let parsedDateDescription = parsed.date.map { debugFormatter.string(from: $0) } ?? "nil"
                AppLogger.debug(
                    .network,
                    "[TradeTimeDebug] raw=\(rawDescription(rawValue)) parsedDate=\(parsedDateDescription) display=\(parsed.displayText) source=\(candidate.source) context=\(logContext)"
                )
                return parsed
            }

            AppLogger.debug(
                .network,
                "[TradeTimeDebug] dropFallback reason=invalid_timestamp source=\(candidate.source) raw=\(rawDescription(rawValue)) context=\(logContext)"
            )
        }

        if firstNonNilCandidate == nil {
            AppLogger.debug(
                .network,
                "[TradeTimeDebug] dropFallback reason=missing_timestamp context=\(logContext)"
            )
        }

        return TradeTimestampParseResult(date: nil, displayText: "-", source: nil)
    }

    private static func parseSingle(
        _ rawValue: Any,
        source: String,
        logContext: String
    ) -> TradeTimestampParseResult? {
        switch rawValue {
        case let number as NSNumber:
            return parseNumericTimestamp(number.doubleValue, source: source, logContext: logContext)
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                return nil
            }

            if let timeOnlyDisplay = parseTimeOnlyDisplay(trimmed) {
                AppLogger.debug(
                    .network,
                    "[TradeTimeDebug] unit=clock_text inferredFrom=\(source) context=\(logContext)"
                )
                let todayDate = todayDateForTimeOnlyDisplay(timeOnlyDisplay)
                return TradeTimestampParseResult(
                    date: todayDate,
                    displayText: timeOnlyDisplay,
                    source: source
                )
            }

            if let timestamp = Double(trimmed) {
                return parseNumericTimestamp(timestamp, source: source, logContext: logContext)
            }

            if let date = iso8601Formatter.date(from: trimmed)
                ?? alternateISO8601Formatter.date(from: trimmed)
                ?? dateTimeFormatter.date(from: trimmed)
                ?? slashDateTimeFormatter.date(from: trimmed) {
                return TradeTimestampParseResult(
                    date: date,
                    displayText: displayFormatter.string(from: date),
                    source: source
                )
            }

            return nil
        default:
            return nil
        }
    }

    private static func parseNumericTimestamp(
        _ timestamp: Double,
        source: String,
        logContext: String
    ) -> TradeTimestampParseResult? {
        guard timestamp.isFinite, timestamp > 0 else {
            return nil
        }

        let absoluteValue = abs(timestamp)
        let unit: String
        let seconds: Double

        if absoluteValue >= 1_000_000_000_000_000 {
            unit = "microseconds"
            seconds = timestamp / 1_000_000
        } else if absoluteValue >= 1_000_000_000_000 {
            unit = "milliseconds"
            seconds = timestamp / 1_000
        } else {
            unit = "seconds"
            seconds = timestamp
        }

        guard seconds.isFinite, seconds > 0 else {
            return nil
        }

        AppLogger.debug(
            .network,
            "[TradeTimeDebug] unit=\(unit) inferredFrom=\(source) context=\(logContext)"
        )

        let date = Date(timeIntervalSince1970: seconds)
        return TradeTimestampParseResult(
            date: date,
            displayText: displayFormatter.string(from: date),
            source: source
        )
    }

    private static func parseTimeOnlyDisplay(_ rawValue: String) -> String? {
        if rawValue.count == 8,
           rawValue.filter(\.isNumber).count == 6,
           rawValue.contains(":"),
           let date = displayFormatter.date(from: rawValue) {
            return displayFormatter.string(from: date)
        }

        let digits = rawValue.filter(\.isNumber)
        guard digits.count == 6 else {
            return nil
        }

        let hour = Int(digits.prefix(2)) ?? -1
        let minute = Int(digits.dropFirst(2).prefix(2)) ?? -1
        let second = Int(digits.suffix(2)) ?? -1
        guard (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else {
            return nil
        }

        return String(format: "%02d:%02d:%02d", hour, minute, second)
    }

    private static func todayDateForTimeOnlyDisplay(_ display: String) -> Date? {
        guard let timeDate = displayFormatter.date(from: display) else {
            return nil
        }

        let calendar = Calendar(identifier: .gregorian)
        let todayComponents = calendar.dateComponents([.year, .month, .day], from: Date())
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: timeDate)
        return calendar.date(from: DateComponents(
            timeZone: TimeZone.autoupdatingCurrent,
            year: todayComponents.year,
            month: todayComponents.month,
            day: todayComponents.day,
            hour: timeComponents.hour,
            minute: timeComponents.minute,
            second: timeComponents.second
        ))
    }

    private static func rawDescription(_ rawValue: Any) -> String {
        if let string = rawValue as? String {
            return string
        }
        if let number = rawValue as? NSNumber {
            return number.stringValue
        }
        return String(describing: rawValue)
    }

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let slashDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter
    }()

    private static let debugFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZ"
        return formatter
    }()

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .autoupdatingCurrent
        return formatter
    }()

    private static let alternateISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .autoupdatingCurrent
        return formatter
    }()
}

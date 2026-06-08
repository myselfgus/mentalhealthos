import Foundation
import HealthOSCore

// MARK: - Clinical Chunking

/// Adaptive clinical text chunking for LLM input planning.
/// Swift port of `src/lib/llm/chunking.ts` preserving clinical discourse boundaries.
public enum ClinicalChunking {

    // MARK: - Types

    /// Kind of structural block detected in the text.
    public enum ChunkKind: String, Sendable {
        case heading
        case speakerTurn = "speaker_turn"
        case paragraph
        case listItem = "list_item"
        case sentence
        case oversize
    }

    /// Chunking strategy hint.
    public enum ChunkingMode: String, Sendable {
        case clinicalTranscript = "clinical-transcript"
        case clinicalDocument = "clinical-document"
        case adaptive
    }

    /// Configuration options for the chunking algorithm.
    public struct ChunkingOptions: Sendable {
        /// Target chunk size in tokens (input planning budget).
        public var targetTokens: Int
        /// Hard ceiling per chunk before fallback splitting.
        public var maxTokensPerChunk: Int
        /// Overlap tokens from previous chunk for analytical continuity. Use 0 for rewrite tasks.
        public var overlapTokens: Int
        /// Whether to detect and preserve structural boundaries.
        public var preserveBoundaries: Bool
        /// Add provenance micro-header to chunk text.
        public var includeMetadataHeader: Bool
        /// Strategy hint for block detection.
        public var mode: ChunkingMode
        /// Label for optional metadata header.
        public var sourceLabel: String

        public init(
            targetTokens: Int = 1800,
            maxTokensPerChunk: Int = 2400,
            overlapTokens: Int = 180,
            preserveBoundaries: Bool = true,
            includeMetadataHeader: Bool = false,
            mode: ChunkingMode = .adaptive,
            sourceLabel: String = "clinical_text"
        ) {
            self.targetTokens = targetTokens
            self.maxTokensPerChunk = maxTokensPerChunk
            self.overlapTokens = overlapTokens
            self.preserveBoundaries = preserveBoundaries
            self.includeMetadataHeader = includeMetadataHeader
            self.mode = mode
            self.sourceLabel = sourceLabel
        }
    }

    /// A single chunk produced by the algorithm, with provenance metadata.
    public struct ClinicalChunk: Sendable {
        public var index: Int
        public var total: Int
        public var text: String
        public var rawText: String
        public var tokenEstimate: Int
        public var charStart: Int
        public var charEnd: Int
        public var overlapFromPrevious: Bool
        public var overlapTokenEstimate: Int
        public var kinds: [ChunkKind]
        public var speakers: [String]
        public var headings: [String]
    }

    // MARK: - Internal Block Type

    private struct TextBlock {
        var text: String
        var kind: ChunkKind
        var charStart: Int
        var charEnd: Int
        var speaker: String?
        var heading: String?
    }

    // MARK: - Constants

    public static let defaultTargetTokens = 1800
    private static let defaultMaxTokens = 2400
    private static let defaultOverlapTokens = 180
    private static let minOversizeSplitTokens = 600

    // MARK: - Public API

    /// Estimates token count for a text string using chars/4 heuristic.
    public static func estimateTokens(_ text: String) -> Int {
        let count = text.count
        return (count + HealthOSDefaults.charsPerToken - 1) / HealthOSDefaults.charsPerToken
    }

    /// Simple API compatible with existing scripts — returns text chunks only.
    public static func splitIntoChunks(_ text: String, maxTokens: Int = defaultTargetTokens) -> [String] {
        let options = ChunkingOptions(
            targetTokens: max(minOversizeSplitTokens, Int(Double(maxTokens) * 0.85)),
            maxTokensPerChunk: maxTokens,
            overlapTokens: 0
        )
        return chunkClinicalText(text, options: options).map(\.text)
    }

    /// Full clinical chunking with structural boundary preservation and provenance metadata.
    public static func chunkClinicalText(
        _ text: String,
        options: ChunkingOptions = ChunkingOptions()
    ) -> [ClinicalChunk] {
        let normalized = normalizeText(text)
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let opts = normalizeOptions(options)

        let blocks: [TextBlock]
        if !opts.preserveBoundaries {
            blocks = splitOversizeBlock(
                TextBlock(text: normalized, kind: .paragraph, charStart: 0, charEnd: normalized.count),
                options: opts
            )
        } else {
            blocks = buildBlocks(normalized, options: opts)
        }

        let grouped = groupBlocks(blocks, options: opts)
        return finalizeChunks(grouped, options: opts)
    }

    // MARK: - Normalization

    private static func normalizeText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeOptions(_ options: ChunkingOptions) -> ChunkingOptions {
        var opts = options
        let maxTokens = opts.maxTokensPerChunk > 0 ? opts.maxTokensPerChunk : defaultMaxTokens
        opts.maxTokensPerChunk = maxTokens

        if opts.targetTokens <= 0 {
            opts.targetTokens = min(defaultTargetTokens, Int(Double(maxTokens) * 0.82))
        }

        return opts
    }

    // MARK: - Block Building

    private static func buildBlocks(_ text: String, options: ChunkingOptions) -> [TextBlock] {
        let primary: [TextBlock]
        if options.mode == .clinicalTranscript {
            primary = splitSpeakerTurns(text)
        } else {
            primary = splitStructuredBlocks(text)
        }

        return primary.flatMap { block -> [TextBlock] in
            if estimateTokens(block.text) <= options.maxTokensPerChunk {
                return [block]
            }
            return splitOversizeBlock(block, options: options)
        }
    }

    private static func splitStructuredBlocks(_ text: String) -> [TextBlock] {
        // Split on double newlines
        let pattern = "(?:^|\\n{2,})([\\s\\S]*?)(?=\\n{2,}|$)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [TextBlock(text: text, kind: .paragraph, charStart: 0, charEnd: text.count)]
        }

        let nsString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
        var blocks: [TextBlock] = []

        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let range = match.range(at: 1)
            let raw = nsString.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }

            let charStart = range.location
            let charEnd = charStart + raw.count
            let kind = classifyBlock(raw)

            blocks.append(TextBlock(
                text: raw,
                kind: kind,
                charStart: charStart,
                charEnd: charEnd,
                speaker: extractSpeaker(raw),
                heading: kind == .heading ? raw.replacingOccurrences(
                    of: "^#+\\s*", with: "", options: .regularExpression
                ) : nil
            ))
        }

        if blocks.isEmpty {
            return [TextBlock(
                text: text, kind: .paragraph, charStart: 0, charEnd: text.count,
                speaker: extractSpeaker(text)
            )]
        }

        return blocks
    }

    /// Speaker-turn aware splitting for clinical transcript mode.
    /// Matches: Falante N, Paciente, Profissional, Terapeuta, Psiquiatra, Dr(a). Name
    private static func splitSpeakerTurns(_ text: String) -> [TextBlock] {
        let pattern = "(^|\\n)(\\s*(?:Falante|Speaker)\\s+\\d+|Paciente|Profissional|Terapeuta|Psiquiatra|Dr\\.?\\s+[^:\\n]{1,80}|Dra\\.?\\s+[^:\\n]{1,80})\\s*[:：\\-]\\s*"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return splitStructuredBlocks(text)
        }

        let nsString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))

        if matches.isEmpty {
            return splitStructuredBlocks(text)
        }

        var blocks: [TextBlock] = []

        for i in 0..<matches.count {
            let current = matches[i]
            let charStart = current.range.location
            let charEnd: Int
            if i + 1 < matches.count {
                charEnd = matches[i + 1].range.location
            } else {
                charEnd = nsString.length
            }

            let raw = nsString.substring(with: NSRange(location: charStart, length: charEnd - charStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { continue }

            let speakerRange = current.range(at: 2)
            let speaker = speakerRange.location != NSNotFound
                ? nsString.substring(with: speakerRange).trimmingCharacters(in: .whitespacesAndNewlines)
                : nil

            blocks.append(TextBlock(
                text: raw,
                kind: .speakerTurn,
                charStart: charStart,
                charEnd: charEnd,
                speaker: speaker
            ))
        }

        // Capture any prefix text before the first speaker turn
        let firstMatchStart = matches[0].range.location
        if firstMatchStart > 0 {
            let prefix = nsString.substring(to: firstMatchStart)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty {
                blocks.insert(TextBlock(
                    text: prefix,
                    kind: .paragraph,
                    charStart: 0,
                    charEnd: prefix.count
                ), at: 0)
            }
        }

        return blocks
    }

    private static func classifyBlock(_ text: String) -> ChunkKind {
        // Heading: markdown # or TITLE-CASE:
        if text.range(of: "^#{1,6}\\s+\\S", options: .regularExpression) != nil {
            return .heading
        }
        if text.range(of: "^[A-ZÀ-Ú0-9][^.\\n]{2,80}:$", options: .regularExpression) != nil {
            return .heading
        }
        // List item
        if text.range(of: "^\\s*(?:[-*•]|\\d+[.)])\\s+", options: .regularExpression) != nil {
            return .listItem
        }
        // Speaker turn
        if extractSpeaker(text) != nil {
            return .speakerTurn
        }
        return .paragraph
    }

    private static func extractSpeaker(_ text: String) -> String? {
        let pattern = "^\\s*((?:Falante|Speaker)\\s+\\d+|Paciente|Profissional|Terapeuta|Psiquiatra|Dr\\.?\\s+[^:\\n]{1,80}|Dra\\.?\\s+[^:\\n]{1,80})\\s*[:：\\-]"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let nsString = text as NSString
        let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: min(200, nsString.length)))
        guard let match, match.numberOfRanges > 1 else { return nil }
        return nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Oversize Block Splitting

    private static func splitOversizeBlock(_ block: TextBlock, options: ChunkingOptions) -> [TextBlock] {
        let sentenceParts = splitSentences(block.text)
        let parts = sentenceParts.count > 1 ? sentenceParts : splitByTokenBudget(block.text, targetTokens: options.targetTokens)

        var output: [TextBlock] = []
        var cursor = block.charStart
        var current = ""
        var currentStart = block.charStart
        let splitKind: ChunkKind = sentenceParts.count > 1 ? .sentence : .oversize

        for part in parts {
            let proposed = current.isEmpty ? part : "\(current) \(part)"
            if !current.isEmpty && estimateTokens(proposed) > options.targetTokens {
                output.append(TextBlock(
                    text: current.trimmingCharacters(in: .whitespacesAndNewlines),
                    kind: splitKind,
                    charStart: currentStart,
                    charEnd: currentStart + current.count,
                    speaker: block.speaker,
                    heading: block.heading
                ))
                currentStart = cursor
                current = part
            } else {
                current = proposed
            }
            cursor += part.count + 1
        }

        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            output.append(TextBlock(
                text: current.trimmingCharacters(in: .whitespacesAndNewlines),
                kind: splitKind,
                charStart: currentStart,
                charEnd: block.charEnd,
                speaker: block.speaker,
                heading: block.heading
            ))
        }

        return output
    }

    private static func splitSentences(_ text: String) -> [String] {
        let pattern = "(?<=[.!?…])\\s+(?=[A-ZÀ-Ú0-9\"\"])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        let nsString = text as NSString
        var parts: [String] = []
        var lastEnd = 0
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            let range = NSRange(location: lastEnd, length: match.range.location - lastEnd)
            let part = nsString.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            if !part.isEmpty { parts.append(part) }
            lastEnd = match.range.location + match.range.length
        }

        let remaining = nsString.substring(from: lastEnd).trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty { parts.append(remaining) }

        return parts.count > 1 ? parts : []
    }

    private static func splitByTokenBudget(_ text: String, targetTokens: Int) -> [String] {
        let maxChars = targetTokens * HealthOSDefaults.charsPerToken
        let words = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var parts: [String] = []
        var current = ""

        for word in words {
            let proposed = current.isEmpty ? word : "\(current) \(word)"
            if !current.isEmpty && proposed.count > maxChars {
                parts.append(current)
                current = word
            } else {
                current = proposed
            }
        }

        if !current.isEmpty { parts.append(current) }
        return parts
    }

    // MARK: - Grouping

    private static func groupBlocks(_ blocks: [TextBlock], options: ChunkingOptions) -> [[TextBlock]] {
        var groups: [[TextBlock]] = []
        var current: [TextBlock] = []
        var currentTokens = 0

        for block in blocks {
            let blockTokens = estimateTokens(block.text)
            let wouldExceed = !current.isEmpty && currentTokens + blockTokens > options.targetTokens
            let hardExceed = !current.isEmpty && currentTokens + blockTokens > options.maxTokensPerChunk

            if wouldExceed || hardExceed {
                groups.append(current)
                current = buildOverlap(from: current, options: options)
                currentTokens = current.reduce(0) { $0 + estimateTokens($1.text) }
            }

            current.append(block)
            currentTokens += blockTokens
        }

        if !current.isEmpty { groups.append(current) }
        return groups
    }

    private static func buildOverlap(from blocks: [TextBlock], options: ChunkingOptions) -> [TextBlock] {
        guard options.overlapTokens > 0 else { return [] }

        var overlap: [TextBlock] = []
        var tokens = 0

        for i in stride(from: blocks.count - 1, through: 0, by: -1) {
            let block = blocks[i]
            let blockTokens = estimateTokens(block.text)
            if !overlap.isEmpty && tokens + blockTokens > options.overlapTokens { break }
            overlap.insert(block, at: 0)
            tokens += blockTokens
            if tokens >= options.overlapTokens { break }
        }

        return overlap
    }

    // MARK: - Finalization

    private static func finalizeChunks(_ groups: [[TextBlock]], options: ChunkingOptions) -> [ClinicalChunk] {
        groups.enumerated().map { index, group in
            let rawText = group.map(\.text).joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let hasOverlap = index > 0 && checkOverlap(group, previous: groups[index - 1])
            let overlapEstimate = hasOverlap ? computeOverlapTokens(group, previous: groups[index - 1]) : 0

            // Collect unique metadata
            let kinds = Array(Set(group.map(\.kind)))
            let speakers = Array(Set(group.compactMap(\.speaker)))
            let headings = Array(Set(group.compactMap(\.heading)))

            let charStart = group.map(\.charStart).min() ?? 0
            let charEnd = group.map(\.charEnd).max() ?? 0

            var text = rawText
            if options.includeMetadataHeader {
                let speakerStr = speakers.isEmpty ? "n/a" : speakers.joined(separator: ", ")
                let overlapStr = hasOverlap ? "sim ~\(overlapEstimate) tokens" : "não"
                text = [
                    "[HealthOS chunk \(index + 1)/\(groups.count)]",
                    "source=\(options.sourceLabel); chars=\(charStart)-\(charEnd); tokens~=\(estimateTokens(rawText)); overlap=\(overlapStr); speakers=\(speakerStr)",
                    "",
                    rawText,
                ].joined(separator: "\n")
            }

            return ClinicalChunk(
                index: index,
                total: groups.count,
                text: text,
                rawText: rawText,
                tokenEstimate: estimateTokens(rawText),
                charStart: charStart,
                charEnd: charEnd,
                overlapFromPrevious: hasOverlap,
                overlapTokenEstimate: overlapEstimate,
                kinds: kinds,
                speakers: speakers,
                headings: headings
            )
        }
    }

    private static func checkOverlap(_ group: [TextBlock], previous: [TextBlock]) -> Bool {
        guard !previous.isEmpty, !group.isEmpty else { return false }
        return group.contains { block in
            previous.contains { prev in
                prev.charStart == block.charStart && prev.charEnd == block.charEnd
            }
        }
    }

    private static func computeOverlapTokens(_ group: [TextBlock], previous: [TextBlock]) -> Int {
        group.filter { block in
            previous.contains { prev in
                prev.charStart == block.charStart && prev.charEnd == block.charEnd
            }
        }.reduce(0) { $0 + estimateTokens($1.text) }
    }
}

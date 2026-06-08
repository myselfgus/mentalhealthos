import Foundation

// MARK: - LLM Provider Protocol

/// Contract for any LLM backend (Claude, OpenAI, local models).
/// Conformers must be actor-isolated or otherwise `Sendable`.
public protocol LLMProvider: Sendable {
    /// Human-readable provider name (e.g. "Claude 3.5 Sonnet").
    var name: String { get }

    /// Send a completion request and return the full response.
    func complete(request: LLMRequest) async throws -> LLMResponse

    /// Stream tokens as they arrive. Default implementation falls back to `complete`.
    func stream(request: LLMRequest) async throws -> AsyncStream<String>
}

// Default streaming implementation that falls back to single completion
public extension LLMProvider {
    func stream(request: LLMRequest) async throws -> AsyncStream<String> {
        let response = try await complete(request: request)
        return AsyncStream { continuation in
            continuation.yield(response.content)
            continuation.finish()
        }
    }
}

// MARK: - LLM Request

/// Encapsulates everything needed for a single LLM call.
public struct LLMRequest: Sendable {
    public var systemPrompt: String?
    public var userPrompt: String
    public var model: String?
    public var temperature: Double
    public var timeoutSeconds: TimeInterval
    public var useCache: Bool
    public var maxOutputTokens: Int?
    public var responseFormat: LLMResponseFormat?

    public init(
        userPrompt: String,
        systemPrompt: String? = nil,
        temperature: Double = 0.3,
        timeoutSeconds: TimeInterval = 120,
        useCache: Bool = true,
        model: String? = nil,
        maxOutputTokens: Int? = nil,
        responseFormat: LLMResponseFormat? = nil
    ) {
        self.userPrompt = userPrompt
        self.systemPrompt = systemPrompt
        self.temperature = temperature
        self.timeoutSeconds = timeoutSeconds
        self.useCache = useCache
        self.model = model
        self.maxOutputTokens = maxOutputTokens
        self.responseFormat = responseFormat
    }
}

/// Hint for the LLM to constrain output format.
public enum LLMResponseFormat: String, Sendable {
    case text
    case json
}

// MARK: - LLM Response

/// Parsed response from an LLM call.
public struct LLMResponse: Sendable {
    public var content: String
    public var usage: LLMUsage?
    public var runtime: String
    public var model: String?
    public var cached: Bool

    public init(
        content: String,
        usage: LLMUsage? = nil,
        runtime: String,
        model: String? = nil,
        cached: Bool = false
    ) {
        self.content = content
        self.usage = usage
        self.runtime = runtime
        self.model = model
        self.cached = cached
    }
}

// MARK: - LLM Usage

/// Token usage statistics from a single LLM call.
public struct LLMUsage: Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var totalTokens: Int
    public var cacheReadTokens: Int?
    public var cacheWriteTokens: Int?

    public init(
        inputTokens: Int,
        outputTokens: Int,
        totalTokens: Int,
        cacheReadTokens: Int? = nil,
        cacheWriteTokens: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
    }
}

// MARK: - LLM Error

/// Errors common to all LLM providers.
public enum LLMError: Error, LocalizedError, Sendable {
    case missingAPIKey(provider: String)
    case invalidResponse(detail: String)
    case rateLimited(retryAfterSeconds: Int?)
    case serverError(statusCode: Int, message: String)
    case timeout(seconds: TimeInterval)
    case decodingFailed(detail: String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            "Chave de API ausente para o provedor \(provider). Configure a variável de ambiente."
        case .invalidResponse(let detail):
            "Resposta inválida do LLM: \(detail)"
        case .rateLimited(let retry):
            "Limite de taxa excedido.\(retry.map { " Tente novamente em \($0)s." } ?? "")"
        case .serverError(let code, let message):
            "Erro do servidor (\(code)): \(message)"
        case .timeout(let seconds):
            "Tempo limite excedido após \(Int(seconds))s."
        case .decodingFailed(let detail):
            "Falha ao decodificar resposta: \(detail)"
        case .cancelled:
            "Operação cancelada."
        }
    }
}

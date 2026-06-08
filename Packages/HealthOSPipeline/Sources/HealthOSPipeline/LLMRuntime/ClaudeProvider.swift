import Foundation
import HealthOSCore

// MARK: - Claude API Provider

/// Actor-based provider for the Anthropic Messages API.
/// Supports prompt caching via `cache_control` and exponential-backoff retry.
public actor ClaudeProvider: LLMProvider {

    // MARK: - Configuration

    public nonisolated let name: String = "Claude API"

    private let apiKey: String
    private let baseURL: URL
    private let defaultModel: String
    private let anthropicVersion: String = "2023-06-01"
    private let maxRetries: Int
    private let baseRetryDelayMs: Int
    private let session: URLSession

    // MARK: - Init

    /// Creates a Claude provider.
    /// - Parameters:
    ///   - apiKey: Optional explicit API key. Falls back to `ANTHROPIC_API_KEY` env var, then Keychain.
    ///   - model: Default model identifier (e.g. "claude-sonnet-4-20250514").
    ///   - baseURL: API endpoint override.
    ///   - maxRetries: Maximum retry attempts for transient failures.
    public init(
        apiKey: String? = nil,
        model: String = "claude-sonnet-4-20250514",
        baseURL: URL = URL(string: "https://api.anthropic.com")!,
        maxRetries: Int = HealthOSDefaults.Retry.maxAttempts
    ) throws {
        let resolvedKey: String
        if let key = apiKey, !key.isEmpty {
            resolvedKey = key
        } else if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !envKey.isEmpty {
            resolvedKey = envKey
        } else if let keychainKey = Self.readKeychain(service: "com.healthos.anthropic", account: "api-key") {
            resolvedKey = keychainKey
        } else {
            throw LLMError.missingAPIKey(provider: "Claude")
        }

        self.apiKey = resolvedKey
        self.defaultModel = model
        self.baseURL = baseURL
        self.maxRetries = maxRetries
        self.baseRetryDelayMs = HealthOSDefaults.Retry.baseDelayMs

        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
            "anthropic-version": anthropicVersion,
            "content-type": "application/json",
        ]
        self.session = URLSession(configuration: config)
    }

    // MARK: - LLMProvider Conformance

    public func complete(request: LLMRequest) async throws -> LLMResponse {
        let body = buildRequestBody(request: request, stream: false)
        let httpRequest = try buildHTTPRequest(body: body, timeout: request.timeoutSeconds)

        var lastError: Error = LLMError.invalidResponse(detail: "Nenhuma tentativa executada")

        for attempt in 0..<maxRetries {
            do {
                try Task.checkCancellation()

                let (data, response) = try await session.data(for: httpRequest)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

                switch statusCode {
                case 200:
                    return try parseResponse(data: data, model: request.model ?? defaultModel)

                case 429:
                    let retryAfter = parseRetryAfter(response as? HTTPURLResponse)
                    let delay = retryAfter ?? HealthOSDefaults.Retry.rateLimitDelayMs
                    if attempt < maxRetries - 1 {
                        try await Task.sleep(for: .milliseconds(delay))
                        continue
                    }
                    throw LLMError.rateLimited(retryAfterSeconds: delay / 1000)

                case 500...599:
                    let message = String(data: data, encoding: .utf8) ?? "Erro desconhecido"
                    if attempt < maxRetries - 1 {
                        let delay = baseRetryDelayMs * (1 << attempt)
                        try await Task.sleep(for: .milliseconds(delay))
                        continue
                    }
                    throw LLMError.serverError(statusCode: statusCode, message: message)

                default:
                    let message = String(data: data, encoding: .utf8) ?? "Erro desconhecido"
                    throw LLMError.serverError(statusCode: statusCode, message: message)
                }
            } catch is CancellationError {
                throw LLMError.cancelled
            } catch let error as LLMError {
                lastError = error
                if case .rateLimited = error, attempt < maxRetries - 1 { continue }
                if case .serverError = error, attempt < maxRetries - 1 { continue }
                throw error
            } catch let error as URLError where error.code == .timedOut {
                lastError = LLMError.timeout(seconds: request.timeoutSeconds)
                if attempt < maxRetries - 1 {
                    let delay = baseRetryDelayMs * (1 << attempt)
                    try await Task.sleep(for: .milliseconds(delay))
                    continue
                }
            } catch {
                lastError = error
                if attempt < maxRetries - 1 {
                    let delay = baseRetryDelayMs * (1 << attempt)
                    try await Task.sleep(for: .milliseconds(delay))
                    continue
                }
            }
        }

        throw lastError
    }

    public func stream(request: LLMRequest) async throws -> AsyncStream<String> {
        let body = buildRequestBody(request: request, stream: true)
        let httpRequest = try buildHTTPRequest(body: body, timeout: request.timeoutSeconds)

        let (bytes, response) = try await session.bytes(for: httpRequest)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard statusCode == 200 else {
            var errorData = Data()
            for try await byte in bytes { errorData.append(byte) }
            let message = String(data: errorData, encoding: .utf8) ?? "Erro de streaming"
            throw LLMError.serverError(statusCode: statusCode, message: message)
        }

        return AsyncStream { continuation in
            let task = Task {
                var buffer = ""
                for try await line in bytes.lines {
                    if line.hasPrefix("data: ") {
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }

                        if let data = payload.data(using: .utf8),
                           let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let type = event["type"] as? String {

                            if type == "content_block_delta",
                               let delta = event["delta"] as? [String: Any],
                               let text = delta["text"] as? String {
                                buffer += text
                                continuation.yield(text)
                            }
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    // MARK: - Request Building

    private func buildRequestBody(request: LLMRequest, stream: Bool) -> [String: Any] {
        var body: [String: Any] = [
            "model": request.model ?? defaultModel,
            "max_tokens": request.maxOutputTokens ?? 8192,
            "temperature": request.temperature,
            "stream": stream,
        ]

        // Build messages array
        var messages: [[String: Any]] = []

        // System prompt with optional cache_control
        if let systemPrompt = request.systemPrompt, !systemPrompt.isEmpty {
            var systemContent: [[String: Any]] = [
                [
                    "type": "text",
                    "text": systemPrompt,
                ]
            ]
            if request.useCache {
                systemContent[0]["cache_control"] = ["type": "ephemeral"]
            }
            body["system"] = systemContent
        }

        // User message
        var userContent: [[String: Any]] = [
            [
                "type": "text",
                "text": request.userPrompt,
            ]
        ]
        if request.useCache {
            userContent[0]["cache_control"] = ["type": "ephemeral"]
        }
        messages.append(["role": "user", "content": userContent])

        body["messages"] = messages
        return body
    }

    private func buildHTTPRequest(body: [String: Any], timeout: TimeInterval) throws -> URLRequest {
        let url = baseURL.appendingPathComponent("v1/messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("prompt-caching-2024-07-31", forHTTPHeaderField: "anthropic-beta")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Response Parsing

    private func parseResponse(data: Data, model: String) throws -> LLMResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.invalidResponse(detail: "Corpo da resposta não é JSON válido")
        }

        // Extract text content
        var textContent = ""
        if let content = json["content"] as? [[String: Any]] {
            for block in content {
                if let type = block["type"] as? String, type == "text",
                   let text = block["text"] as? String {
                    textContent += text
                }
            }
        }

        guard !textContent.isEmpty else {
            throw LLMError.invalidResponse(detail: "Resposta sem conteúdo de texto")
        }

        // Extract usage
        var usage: LLMUsage?
        if let usageJSON = json["usage"] as? [String: Any] {
            let inputTokens = usageJSON["input_tokens"] as? Int ?? 0
            let outputTokens = usageJSON["output_tokens"] as? Int ?? 0
            let cacheRead = usageJSON["cache_read_input_tokens"] as? Int
            let cacheWrite = usageJSON["cache_creation_input_tokens"] as? Int
            usage = LLMUsage(
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                totalTokens: inputTokens + outputTokens,
                cacheReadTokens: cacheRead,
                cacheWriteTokens: cacheWrite
            )
        }

        let responseModel = json["model"] as? String ?? model
        let cached = (usage?.cacheReadTokens ?? 0) > 0

        return LLMResponse(
            content: textContent,
            usage: usage,
            runtime: name,
            model: responseModel,
            cached: cached
        )
    }

    private func parseRetryAfter(_ response: HTTPURLResponse?) -> Int? {
        guard let retryStr = response?.value(forHTTPHeaderField: "retry-after"),
              let seconds = Int(retryStr) else { return nil }
        return seconds * 1000
    }

    // MARK: - Keychain Helper

    private static func readKeychain(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Claude API Error (Legacy/Extended)

/// Extended error type for Claude-specific API failures.
public enum ClaudeAPIError: Error, LocalizedError, Sendable {
    case invalidRequestBody
    case authenticationFailed
    case modelNotAvailable(model: String)
    case contentFiltered
    case overloaded

    public var errorDescription: String? {
        switch self {
        case .invalidRequestBody:
            "Corpo da requisição inválido para a API Claude."
        case .authenticationFailed:
            "Falha na autenticação com a API Claude."
        case .modelNotAvailable(let model):
            "Modelo \(model) não disponível."
        case .contentFiltered:
            "Conteúdo filtrado pela política de segurança."
        case .overloaded:
            "Serviço temporariamente sobrecarregado."
        }
    }
}

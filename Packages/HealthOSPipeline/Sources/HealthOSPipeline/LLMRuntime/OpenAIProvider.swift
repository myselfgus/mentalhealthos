import Foundation
import HealthOSCore

// MARK: - OpenAI-Compatible Provider

/// Actor-based provider for OpenAI Chat Completions API.
/// Also supports Cloudflare AI Gateway or any OpenAI-compatible endpoint.
public actor OpenAIProvider: LLMProvider {

    // MARK: - Configuration

    public nonisolated let name: String

    private let apiKey: String
    private let baseURL: URL
    private let defaultModel: String
    private let maxRetries: Int
    private let baseRetryDelayMs: Int
    private let session: URLSession

    // MARK: - Init

    /// Creates an OpenAI-compatible provider.
    /// - Parameters:
    ///   - apiKey: Optional explicit API key. Falls back to `OPENAI_API_KEY` env var.
    ///   - model: Default model identifier (e.g. "gpt-4o").
    ///   - baseURL: API endpoint (default: api.openai.com). Set to Cloudflare AI Gateway URL for routing.
    ///   - providerName: Human-readable name for this provider instance.
    ///   - maxRetries: Maximum retry attempts for transient failures.
    public init(
        apiKey: String? = nil,
        model: String = "gpt-4o",
        baseURL: URL = URL(string: "https://api.openai.com")!,
        providerName: String = "OpenAI",
        maxRetries: Int = HealthOSDefaults.Retry.maxAttempts
    ) throws {
        let resolvedKey: String
        if let key = apiKey, !key.isEmpty {
            resolvedKey = key
        } else if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !envKey.isEmpty {
            resolvedKey = envKey
        } else {
            throw LLMError.missingAPIKey(provider: providerName)
        }

        self.apiKey = resolvedKey
        self.defaultModel = model
        self.baseURL = baseURL
        self.name = providerName
        self.maxRetries = maxRetries
        self.baseRetryDelayMs = HealthOSDefaults.Retry.baseDelayMs

        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = [
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
                for try await line in bytes.lines {
                    if line.hasPrefix("data: ") {
                        let payload = String(line.dropFirst(6))
                        if payload.trimmingCharacters(in: .whitespaces) == "[DONE]" { break }

                        if let data = payload.data(using: .utf8),
                           let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let choices = event["choices"] as? [[String: Any]],
                           let delta = choices.first?["delta"] as? [String: Any],
                           let content = delta["content"] as? String {
                            continuation.yield(content)
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
            "temperature": request.temperature,
            "stream": stream,
        ]

        if let maxTokens = request.maxOutputTokens {
            body["max_tokens"] = maxTokens
        }

        // Build messages
        var messages: [[String: Any]] = []

        if let systemPrompt = request.systemPrompt, !systemPrompt.isEmpty {
            messages.append([
                "role": "system",
                "content": systemPrompt,
            ])
        }

        messages.append([
            "role": "user",
            "content": request.userPrompt,
        ])

        body["messages"] = messages

        // JSON mode
        if request.responseFormat == .json {
            body["response_format"] = ["type": "json_object"]
        }

        return body
    }

    private func buildHTTPRequest(body: [String: Any], timeout: TimeInterval) throws -> URLRequest {
        let url = baseURL.appendingPathComponent("v1/chat/completions")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Response Parsing

    private func parseResponse(data: Data, model: String) throws -> LLMResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.invalidResponse(detail: "Corpo da resposta não é JSON válido")
        }

        // Extract text from choices
        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.isEmpty else {
            throw LLMError.invalidResponse(detail: "Resposta sem conteúdo de texto")
        }

        // Extract usage
        var usage: LLMUsage?
        if let usageJSON = json["usage"] as? [String: Any] {
            let promptTokens = usageJSON["prompt_tokens"] as? Int ?? 0
            let completionTokens = usageJSON["completion_tokens"] as? Int ?? 0
            usage = LLMUsage(
                inputTokens: promptTokens,
                outputTokens: completionTokens,
                totalTokens: promptTokens + completionTokens
            )
        }

        let responseModel = json["model"] as? String ?? model

        return LLMResponse(
            content: content,
            usage: usage,
            runtime: name,
            model: responseModel,
            cached: false
        )
    }

    private func parseRetryAfter(_ response: HTTPURLResponse?) -> Int? {
        guard let retryStr = response?.value(forHTTPHeaderField: "retry-after"),
              let seconds = Int(retryStr) else { return nil }
        return seconds * 1000
    }
}

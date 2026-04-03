import Foundation

/// Parses the raw text response from the Gemini API into a `GeneratedCode` value.
enum CodeGenerationResponse {

    // MARK: - Errors

    enum ParseError: LocalizedError {
        case emptyResponse
        case jsonExtractionFailed(String)
        case jsonDecodingFailed(underlying: String)
        case missingHTMLPreview
        case missingReactCode

        var errorDescription: String? {
            switch self {
            case .emptyResponse:
                return "The model returned an empty response."
            case .jsonExtractionFailed(let detail):
                return "Could not extract JSON from model response: \(detail)"
            case .jsonDecodingFailed(let underlying):
                return "JSON decoding failed: \(underlying)"
            case .missingHTMLPreview:
                return "Response JSON is missing the 'htmlPreview' field."
            case .missingReactCode:
                return "Response JSON is missing the 'reactCode' field."
            }
        }
    }

    // MARK: - Public API

    /// Parses the raw model response text into a `GeneratedCode` value.
    ///
    /// The method first attempts structured JSON parsing, then falls back to
    /// regex-based extraction if the model wrapped the output in markdown fences
    /// or included additional text.
    ///
    /// - Parameter responseText: The raw text from the Gemini API response.
    /// - Returns: A parsed `GeneratedCode` instance.
    /// - Throws: `ParseError` if the response cannot be parsed.
    static func parse(_ responseText: String) throws -> GeneratedCode {
        let trimmed = responseText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            throw ParseError.emptyResponse
        }

        // Attempt 1: Extract JSON (handling optional code fences) and decode.
        let jsonString = extractJSON(from: trimmed)

        if let jsonData = jsonString.data(using: .utf8) {
            do {
                let decoded = try JSONDecoder().decode(JSONResponse.self, from: jsonData)
                return GeneratedCode(htmlPreview: decoded.htmlPreview, reactCode: decoded.reactCode)
            } catch {
                // Fall through to regex extraction.
            }
        }

        // Attempt 2: Regex-based field extraction as a fallback.
        return try extractViaRegex(from: trimmed)
    }

    // MARK: - JSON Extraction

    /// Extracts a JSON object string from text that may be wrapped in markdown code fences.
    private static func extractJSON(from text: String) -> String {
        // Try to find JSON inside ```json ... ``` or ``` ... ``` fences.
        if let fenceMatch = text.range(
            of: #"```(?:json)?\s*\n?([\s\S]*?)\n?\s*```"#,
            options: .regularExpression
        ) {
            let inside = text[fenceMatch]
            // Strip the fence markers themselves.
            let stripped = inside
                .replacingOccurrences(of: #"^```(?:json)?\s*\n?"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\n?\s*```$"#, with: "", options: .regularExpression)
            return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Try to find the outermost { ... } block.
        if let openIndex = text.firstIndex(of: "{"),
           let closeIndex = text.lastIndex(of: "}") {
            return String(text[openIndex...closeIndex])
        }

        return text
    }

    // MARK: - Regex Fallback

    /// Attempts to extract htmlPreview and reactCode fields using regex when JSON parsing fails.
    private static func extractViaRegex(from text: String) throws -> GeneratedCode {
        let htmlPreview = try extractField(named: "htmlPreview", from: text)
        let reactCode = try extractField(named: "reactCode", from: text)
        return GeneratedCode(htmlPreview: htmlPreview, reactCode: reactCode)
    }

    /// Extracts a string value for a given JSON field name using regex.
    ///
    /// Handles the pattern: `"fieldName": "value"` or `"fieldName": "value with \"escapes\""`
    private static func extractField(named fieldName: String, from text: String) throws -> String {
        // Match "fieldName" followed by : and a JSON string value.
        // We look for the field, then consume the string value carefully handling escapes.
        let pattern = #""\#(fieldName)"\s*:\s*""#
        guard let startRange = text.range(of: pattern, options: .regularExpression) else {
            switch fieldName {
            case "htmlPreview": throw ParseError.missingHTMLPreview
            case "reactCode": throw ParseError.missingReactCode
            default: throw ParseError.jsonExtractionFailed("Field '\(fieldName)' not found.")
            }
        }

        // Walk from the end of the match to find the closing unescaped quote.
        let valueStart = startRange.upperBound
        var index = valueStart
        var result = ""

        while index < text.endIndex {
            let char = text[index]

            if char == "\\" {
                // Consume the escaped character.
                let nextIndex = text.index(after: index)
                guard nextIndex < text.endIndex else { break }
                let escaped = text[nextIndex]
                switch escaped {
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                case "/": result.append("/")
                default: result.append("\\"); result.append(escaped)
                }
                index = text.index(after: nextIndex)
            } else if char == "\"" {
                // Unescaped quote means end of value.
                return result
            } else {
                result.append(char)
                index = text.index(after: index)
            }
        }

        throw ParseError.jsonExtractionFailed("Unterminated string value for field '\(fieldName)'.")
    }

    // MARK: - Internal Types

    /// Minimal Codable representation for decoding the expected JSON response.
    private struct JSONResponse: Codable {
        let htmlPreview: String
        let reactCode: String
    }
}

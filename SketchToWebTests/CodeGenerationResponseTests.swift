import XCTest
@testable import SketchToWeb

final class CodeGenerationResponseTests: XCTestCase {

    // MARK: - Valid JSON Parsing

    func testParseValidJSONWithBothFields() throws {
        let json = """
        {
            "htmlPreview": "<div class=\\"card\\">Hello</div>",
            "reactCode": "export default function Card() { return <div>Hello</div>; }"
        }
        """

        let result = try CodeGenerationResponse.parse(json)

        XCTAssertEqual(result.htmlPreview, "<div class=\"card\">Hello</div>")
        XCTAssertEqual(result.reactCode, "export default function Card() { return <div>Hello</div>; }")
    }

    // MARK: - Markdown Code Fence Handling

    func testParseJSONWrappedInMarkdownCodeFences() throws {
        let response = """
        Here is the generated code:

        ```json
        {
            "htmlPreview": "<button class=\\"btn-primary\\">Submit</button>",
            "reactCode": "import { Button } from \\"@/components/ui/button\\";\\nexport default function MyButton() { return <Button>Submit</Button>; }"
        }
        ```

        Let me know if you need changes.
        """

        let result = try CodeGenerationResponse.parse(response)

        XCTAssertEqual(result.htmlPreview, "<button class=\"btn-primary\">Submit</button>")
        XCTAssertTrue(result.reactCode.contains("import { Button }"))
        XCTAssertTrue(result.reactCode.contains("@/components/ui/button"))
    }

    // MARK: - Malformed JSON

    func testParseMalformedJSONThrowsError() {
        let malformed = "{ this is not valid json at all }"

        XCTAssertThrowsError(try CodeGenerationResponse.parse(malformed)) { error in
            // The parser should throw some form of ParseError when JSON is invalid
            // and regex fallback also fails to find the required fields.
            guard let parseError = error as? CodeGenerationResponse.ParseError else {
                XCTFail("Expected CodeGenerationResponse.ParseError but got \(type(of: error))")
                return
            }

            // Should indicate a missing field or extraction failure since the malformed
            // JSON doesn't contain valid htmlPreview or reactCode fields.
            switch parseError {
            case .missingHTMLPreview, .missingReactCode, .jsonExtractionFailed:
                break // Expected
            default:
                XCTFail("Unexpected ParseError case: \(parseError)")
            }
        }
    }

    // MARK: - Empty Response

    func testParseEmptyResponseThrowsEmptyResponseError() {
        XCTAssertThrowsError(try CodeGenerationResponse.parse("")) { error in
            guard let parseError = error as? CodeGenerationResponse.ParseError else {
                XCTFail("Expected CodeGenerationResponse.ParseError but got \(type(of: error))")
                return
            }

            switch parseError {
            case .emptyResponse:
                break // Expected
            default:
                XCTFail("Expected .emptyResponse but got \(parseError)")
            }
        }
    }

    // MARK: - Partial Fields

    func testParseResponseWithOnlyHTMLPreviewThrowsMissingReactCode() {
        let partialJSON = """
        {
            "htmlPreview": "<div>Partial</div>"
        }
        """

        // The Codable JSONResponse requires both fields, so decoding should fail.
        // The regex fallback should then fail to find reactCode.
        XCTAssertThrowsError(try CodeGenerationResponse.parse(partialJSON)) { error in
            guard let parseError = error as? CodeGenerationResponse.ParseError else {
                XCTFail("Expected CodeGenerationResponse.ParseError but got \(type(of: error))")
                return
            }

            switch parseError {
            case .missingReactCode:
                break // Expected
            default:
                XCTFail("Expected .missingReactCode but got \(parseError)")
            }
        }
    }

    func testParseResponseWithOnlyReactCodeThrowsMissingHTMLPreview() {
        let partialJSON = """
        {
            "reactCode": "export default function App() { return <div />; }"
        }
        """

        XCTAssertThrowsError(try CodeGenerationResponse.parse(partialJSON)) { error in
            guard let parseError = error as? CodeGenerationResponse.ParseError else {
                XCTFail("Expected CodeGenerationResponse.ParseError but got \(type(of: error))")
                return
            }

            switch parseError {
            case .missingHTMLPreview:
                break // Expected
            default:
                XCTFail("Expected .missingHTMLPreview but got \(parseError)")
            }
        }
    }

    // MARK: - Whitespace-Only Response

    func testParseWhitespaceOnlyResponseThrowsEmptyResponseError() {
        XCTAssertThrowsError(try CodeGenerationResponse.parse("   \n\t  ")) { error in
            guard let parseError = error as? CodeGenerationResponse.ParseError else {
                XCTFail("Expected CodeGenerationResponse.ParseError")
                return
            }

            switch parseError {
            case .emptyResponse:
                break // Expected
            default:
                XCTFail("Expected .emptyResponse but got \(parseError)")
            }
        }
    }
}

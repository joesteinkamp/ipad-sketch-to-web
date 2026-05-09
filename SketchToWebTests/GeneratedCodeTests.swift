import XCTest
@testable import SketchToWeb

/// Codable round-trip and structural tests for the conversion-pipeline output.
final class GeneratedCodeTests: XCTestCase {

    // MARK: - GeneratedCode

    func testCodableRoundTripPreservesAllFields() throws {
        let original = GeneratedCode(
            htmlPreview: "<div>Hello</div>",
            reactCode: "export default function App() { return <div>Hello</div>; }",
            componentTree: [
                GeneratedCode.ComponentNode(
                    type: "div",
                    props: ["className": "p-4"],
                    children: [GeneratedCode.ComponentNode(type: "Text")]
                )
            ]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GeneratedCode.self, from: data)

        XCTAssertEqual(decoded.htmlPreview, original.htmlPreview)
        XCTAssertEqual(decoded.reactCode, original.reactCode)
        XCTAssertEqual(decoded.componentTree?.count, 1)
        XCTAssertEqual(decoded.componentTree?[0].type, "div")
        XCTAssertEqual(decoded.componentTree?[0].props?["className"], "p-4")
        XCTAssertEqual(decoded.componentTree?[0].children?[0].type, "Text")
    }

    func testCodableHandlesNilComponentTree() throws {
        let original = GeneratedCode(
            htmlPreview: "<p>x</p>",
            reactCode: "<p>x</p>",
            componentTree: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GeneratedCode.self, from: data)
        XCTAssertNil(decoded.componentTree)
    }

    func testEquatableComparesAllFields() {
        let a = GeneratedCode(htmlPreview: "x", reactCode: "y", componentTree: nil)
        let b = GeneratedCode(htmlPreview: "x", reactCode: "y", componentTree: nil)
        let c = GeneratedCode(htmlPreview: "x", reactCode: "z", componentTree: nil)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    // MARK: - ComponentNode

    func testComponentNodeAutoAssignsUUID() {
        let a = GeneratedCode.ComponentNode(type: "Button")
        let b = GeneratedCode.ComponentNode(type: "Button")
        XCTAssertNotEqual(a.id, b.id, "Each node should get a fresh UUID")
    }

    func testComponentNodeAcceptsExplicitID() {
        let id = UUID()
        let node = GeneratedCode.ComponentNode(id: id, type: "Card")
        XCTAssertEqual(node.id, id)
    }

    func testComponentNodeCodableRoundTripPreservesID() throws {
        let id = UUID()
        let original = GeneratedCode.ComponentNode(id: id, type: "Input", props: ["type": "email"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GeneratedCode.ComponentNode.self, from: data)
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.type, "Input")
        XCTAssertEqual(decoded.props?["type"], "email")
    }

    func testComponentTreeCanRecurseSeveralLevels() throws {
        let leaf = GeneratedCode.ComponentNode(type: "Text", props: ["children": "Hi"])
        let middle = GeneratedCode.ComponentNode(type: "CardContent", children: [leaf])
        let root = GeneratedCode.ComponentNode(type: "Card", children: [middle])

        let data = try JSONEncoder().encode(root)
        let decoded = try JSONDecoder().decode(GeneratedCode.ComponentNode.self, from: data)
        XCTAssertEqual(decoded.children?[0].children?[0].type, "Text")
    }

    func testComponentNodeEquatable() {
        let id = UUID()
        let a = GeneratedCode.ComponentNode(id: id, type: "X")
        let b = GeneratedCode.ComponentNode(id: id, type: "X")
        let c = GeneratedCode.ComponentNode(id: UUID(), type: "X")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c, "Different IDs should make nodes non-equal")
    }
}

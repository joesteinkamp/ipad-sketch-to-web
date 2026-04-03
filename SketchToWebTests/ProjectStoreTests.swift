import XCTest
import SwiftData
import PencilKit
@testable import SketchToWeb

@MainActor
final class ProjectStoreTests: XCTestCase {

    private var container: ModelContainer!
    private var store: ProjectStore!

    override func setUp() {
        super.setUp()
        let schema = Schema([Project.self, ProjectFolder.self, Generation.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: schema, configurations: [config])
        store = ProjectStore(modelContext: container.mainContext)
    }

    override func tearDown() {
        container = nil
        store = nil
        super.tearDown()
    }

    // MARK: - Create

    func testCreateProjectInsertsIntoContext() {
        let project = store.createProject(name: "Test Project")
        XCTAssertEqual(project.name, "Test Project")
        XCTAssertNotNil(project.id)

        let descriptor = FetchDescriptor<Project>()
        let all = try! container.mainContext.fetch(descriptor)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.name, "Test Project")
    }

    // MARK: - Delete

    func testDeleteProjectRemovesFromContext() {
        let project = store.createProject(name: "To Delete")
        store.deleteProject(project)

        let descriptor = FetchDescriptor<Project>()
        let all = try! container.mainContext.fetch(descriptor)
        XCTAssertTrue(all.isEmpty)
    }

    // MARK: - Save Drawing

    func testSaveDrawingPersistsData() {
        let project = store.createProject(name: "Drawing Test")
        let drawing = PKDrawing()
        store.saveDrawing(drawing, to: project)

        XCTAssertEqual(project.drawingData, drawing.dataRepresentation())
        XCTAssertNotNil(project.thumbnailData)
    }

    // MARK: - Save Generation

    func testSaveGenerationUpdatesProject() {
        let project = store.createProject(name: "Gen Test")
        let code = GeneratedCode(htmlPreview: "<div>Hello</div>", reactCode: "function App() {}")
        store.saveGeneration(code, to: project)

        XCTAssertEqual(project.generatedHTML, "<div>Hello</div>")
        XCTAssertEqual(project.generatedReactCode, "function App() {}")
    }

    // MARK: - Error Surface

    func testLastSaveErrorIsNilOnSuccess() {
        _ = store.createProject(name: "Success")
        XCTAssertNil(store.lastSaveError)
    }
}

import ClipFlowCore
import Foundation
import Testing

@Suite("Snippet templates")
struct SnippetTemplateTests {
    @Test("extracts variables in first-appearance order and renders supplied values")
    func rendersVariables() {
        let body = "Hello {{name}}, your order {{order_id}} is ready for {{name}}."

        #expect(SnippetTemplateRenderer.variables(in: body) == ["name", "order_id"])
        #expect(
            SnippetTemplateRenderer.render(
                body,
                values: ["name": "Ada", "order_id": "2048"]
            ) == "Hello Ada, your order 2048 is ready for Ada."
        )
    }
}

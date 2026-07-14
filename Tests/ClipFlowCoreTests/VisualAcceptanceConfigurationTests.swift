import Testing
import ClipFlowCore
@testable import ClipFlowUI

@Suite("Visual acceptance configuration")
struct VisualAcceptanceConfigurationTests {
    @Test("probe argument is recognized exactly")
    func recognizesProbeArgument() {
        #expect(VisualAcceptanceConfiguration.isProbe(
            arguments: ["ClipFlowApp", "--clipflow-acceptance-probe"]
        ))
        #expect(!VisualAcceptanceConfiguration.isProbe(
            arguments: ["ClipFlowApp", "--clipflow-acceptance-probe-extra"]
        ))
    }

    @Test("safe capture requires flag token and isolated data directory")
    func requiresCompleteSafetyContract() {
        let complete = [
            "CLIPFLOW_VISUAL_ACCEPTANCE": "1",
            "CLIPFLOW_ACCEPTANCE_TOKEN": "capture-123",
            "CLIPFLOW_DEVELOPMENT_DATA_DIR": "/tmp/clipflow-capture"
        ]

        #expect(VisualAcceptanceConfiguration.validated(
            environment: complete,
            arguments: ["ClipFlowApp"]
        ) != nil)
        #expect(VisualAcceptanceConfiguration.validated(
            environment: complete.merging(["CLIPFLOW_VISUAL_ACCEPTANCE": "0"]) { _, new in new },
            arguments: ["ClipFlowApp"]
        ) == nil)
        #expect(VisualAcceptanceConfiguration.validated(
            environment: complete.merging(["CLIPFLOW_ACCEPTANCE_TOKEN": ""]) { _, new in new },
            arguments: ["ClipFlowApp"]
        ) == nil)
        #expect(VisualAcceptanceConfiguration.validated(
            environment: complete.merging(["CLIPFLOW_DEVELOPMENT_DATA_DIR": ""]) { _, new in new },
            arguments: ["ClipFlowApp"]
        ) == nil)
    }

    @Test("appearance density and browser settings use deterministic inputs")
    func parsesDeterministicPreferences() throws {
        let configuration = try #require(VisualAcceptanceConfiguration.validated(
            environment: [
                "CLIPFLOW_VISUAL_ACCEPTANCE": "1",
                "CLIPFLOW_ACCEPTANCE_TOKEN": "capture-456",
                "CLIPFLOW_DEVELOPMENT_DATA_DIR": "/tmp/clipflow-capture",
                "CLIPFLOW_LIST_DENSITY": "compact",
                "CLIPFLOW_SELECTED_KIND": "file"
            ],
            arguments: [
                "ClipFlowApp",
                "-appearanceMode", "dark",
                "-browserTabManagementEnabled", "NO"
            ]
        ))

        #expect(configuration.token == "capture-456")
        #expect(configuration.dataDirectory == "/tmp/clipflow-capture")
        #expect(configuration.appearanceMode == .dark)
        #expect(configuration.listDensity == .compact)
        #expect(!configuration.browserTabManagementEnabled)
        #expect(configuration.selectedKind == .file)
    }

    @Test("unknown selected kinds fall back to the default selection")
    func rejectsUnknownSelectedKind() throws {
        let configuration = try #require(VisualAcceptanceConfiguration.validated(
            environment: [
                "CLIPFLOW_VISUAL_ACCEPTANCE": "1",
                "CLIPFLOW_ACCEPTANCE_TOKEN": "capture-789",
                "CLIPFLOW_DEVELOPMENT_DATA_DIR": "/tmp/clipflow-capture",
                "CLIPFLOW_SELECTED_KIND": "future-kind"
            ],
            arguments: ["ClipFlowApp"]
        ))

        #expect(configuration.selectedKind == nil)
    }
}

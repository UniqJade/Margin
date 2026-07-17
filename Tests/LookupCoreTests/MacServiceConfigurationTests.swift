import Foundation
import Testing

@Suite("macOS Service configuration")
struct MacServiceConfigurationTests {
    @Test("Service is discoverable and routes to the Margin application")
    func serviceRegistrationProperties() throws {
        let plistURL = repositoryRoot.appendingPathComponent("Config/MacInfo.plist")
        let data = try Data(contentsOf: plistURL)
        let root = try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let services = try #require(root["NSServices"] as? [[String: Any]])
        let service = try #require(services.first)

        #expect(service["NSPortName"] as? String == "Margin")
        #expect(service["NSRequiredContext"] as? [String: Any] != nil)
        let sendTypes = try #require(service["NSSendTypes"] as? [String])
        #expect(sendTypes.contains("NSStringPboardType"))
        #expect(sendTypes.contains("public.utf8-plain-text"))
    }

    @Test("Public project defaults contain no personal signing identity")
    func publicSigningDefaultsAndCapabilities() throws {
        let projectSpec = try String(
            contentsOf: repositoryRoot.appendingPathComponent("project.yml"),
            encoding: .utf8
        )
        let macStart = try #require(projectSpec.range(of: "  BooksTranslatorMac:\n"))
        let macEnd = try #require(
            projectSpec.range(of: "  BooksTranslatorMacTests:\n", range: macStart.upperBound..<projectSpec.endIndex)
        )
        let macTarget = String(projectSpec[macStart.lowerBound..<macEnd.lowerBound])
        let defaults = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Config/BuildDefaults.xcconfig"),
            encoding: .utf8
        )
        let example = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Local.xcconfig.example"),
            encoding: .utf8
        )

        #expect(projectSpec.contains("configFiles:"))
        #expect(projectSpec.contains("Config/BuildDefaults.xcconfig"))
        #expect(projectSpec.contains("DEVELOPMENT_TEAM: $(MARGIN_DEVELOPMENT_TEAM)"))
        #expect(macTarget.contains("PRODUCT_BUNDLE_IDENTIFIER: $(MARGIN_MAC_BUNDLE_ID)"))
        #expect(defaults.contains("MARGIN_MAC_BUNDLE_ID = dev.example.BooksTranslator.mac"))
        #expect(defaults.contains("#include? \"../Local.xcconfig\""))
        #expect(example.contains("MARGIN_DEVELOPMENT_TEAM = YOUR_TEAM_ID"))
        #expect(!macTarget.contains("entitlements:"))
        #expect(!FileManager.default.fileExists(
            atPath: repositoryRoot.appendingPathComponent("Config/Mac.entitlements").path
        ))
    }

    @Test("Bundle, App Group, and Keychain values flow through local build settings")
    func identifiersUseBuildSettingIndirection() throws {
        let projectSpec = try String(
            contentsOf: repositoryRoot.appendingPathComponent("project.yml"),
            encoding: .utf8
        )
        let sharedConfiguration = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Apps/SharedUI/SharedConfiguration.swift"),
            encoding: .utf8
        )
        let iosEntitlements = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Config/iOS.entitlements"),
            encoding: .utf8
        )
        let actionEntitlements = try String(
            contentsOf: repositoryRoot.appendingPathComponent("Config/Action.entitlements"),
            encoding: .utf8
        )

        #expect(projectSpec.contains("PRODUCT_BUNDLE_IDENTIFIER: $(MARGIN_IOS_BUNDLE_ID)"))
        #expect(projectSpec.contains("PRODUCT_BUNDLE_IDENTIFIER: $(MARGIN_ACTION_BUNDLE_ID)"))
        #expect(iosEntitlements.contains("$(MARGIN_APP_GROUP_IDENTIFIER)"))
        #expect(actionEntitlements.contains("$(MARGIN_APP_GROUP_IDENTIFIER)"))
        #expect(iosEntitlements.contains("$(MARGIN_SHARED_KEYCHAIN_SUFFIX)"))
        #expect(actionEntitlements.contains("$(MARGIN_SHARED_KEYCHAIN_SUFFIX)"))
        #expect(sharedConfiguration.contains("MarginMacKeychainService"))
        #expect(sharedConfiguration.contains("MarginAppGroupIdentifier"))
        #expect(sharedConfiguration.contains("MarginSharedKeychainService"))
    }

    @Test("Install and verification scripts fail fast without local identity configuration")
    func personalInstallRequiresLocalConfiguration() throws {
        let installScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/install-mac.sh"),
            encoding: .utf8
        )
        let verifyScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/verify-mac-app.sh"),
            encoding: .utf8
        )

        #expect(installScript.contains("Local.xcconfig"))
        #expect(installScript.contains("MARGIN_MAC_BUNDLE_ID"))
        #expect(installScript.contains("MARGIN_MAC_KEYCHAIN_SERVICE"))
        #expect(verifyScript.contains("Local.xcconfig"))
        #expect(verifyScript.contains("MARGIN_MAC_BUNDLE_ID"))
        #expect(verifyScript.contains("MarginMacKeychainService"))
    }

    @Test("Mac test scheme unregisters temporary Margin builds after tests")
    func temporaryBuildCleanupIsWiredIntoTheScheme() throws {
        let projectSpec = try String(
            contentsOf: repositoryRoot.appendingPathComponent("project.yml"),
            encoding: .utf8
        )
        let cleanupScript = repositoryRoot.appendingPathComponent("scripts/unregister-derived-margin.sh")

        #expect(projectSpec.contains("postActions:"))
        #expect(projectSpec.contains("scripts/unregister-derived-margin.sh"))
        #expect(FileManager.default.isExecutableFile(atPath: cleanupScript.path))
    }

    @Test("Temporary build cleanup covers the main checkout and every worktree")
    func temporaryBuildCleanupCoversEveryWorktree() throws {
        let cleanupScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/unregister-derived-margin.sh"),
            encoding: .utf8
        )

        #expect(cleanupScript.contains("--git-common-dir"))
        #expect(cleanupScript.contains("workspace_root"))
        #expect(cleanupScript.contains("\"$lsregister\" -dump"))
        #expect(cleanupScript.contains("unregister_app"))
    }

    @Test("Temporary build cleanup removes stale LaunchServices paths once")
    func temporaryBuildCleanupRemovesStalePathsOnce() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MarginLaunchServicesTests-\(UUID().uuidString)")
        let fakeLaunchServices = directory.appendingPathComponent("lsregister")
        let log = directory.appendingPathComponent("unregistered.txt")
        let staleApp = directory
            .appendingPathComponent("Disposable/Build/Products/Debug/Margin.app")
            .path
        let installedApp = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Margin.app")
            .path
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fakeScript = """
        #!/bin/zsh
        if [[ "$1" == "-dump" ]]; then
            print -r -- "path:                       \(staleApp) (0x1234)"
            print -r -- "path:                       \(staleApp) (0x1234)"
            print -r -- "path:                       \(installedApp) (0x5678)"
            exit 0
        fi
        if [[ "$1" == "-u" ]]; then
            print -r -- "$2" >> "$MARGIN_TEST_LOG"
            exit 0
        fi
        exit 1
        """
        try fakeScript.write(to: fakeLaunchServices, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: fakeLaunchServices.path
        )

        let process = Process()
        process.executableURL = repositoryRoot.appendingPathComponent("scripts/unregister-derived-margin.sh")
        process.arguments = [directory.path]
        var environment = ProcessInfo.processInfo.environment
        environment["MARGIN_LSREGISTER_PATH"] = fakeLaunchServices.path
        environment["MARGIN_TEST_LOG"] = log.path
        process.environment = environment
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        #expect(process.terminationStatus == 0)
        let paths = try String(contentsOf: log, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        #expect(paths == [staleApp])
    }

    @Test("Repository-managed DerivedData stays out of Spotlight")
    func repositoryManagedDerivedDataUsesNoIndexDirectories() throws {
        let installScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/install-mac.sh"),
            encoding: .utf8
        )
        let testScript = try String(
            contentsOf: repositoryRoot.appendingPathComponent("scripts/test-mac.sh"),
            encoding: .utf8
        )
        let buildingGuide = try String(
            contentsOf: repositoryRoot.appendingPathComponent("docs/building.md"),
            encoding: .utf8
        )

        #expect(installScript.contains("XcodeDerivedData-Install.noindex"))
        #expect(testScript.contains("XcodeDerivedData-Mac.noindex"))
        #expect(buildingGuide.contains("-derivedDataPath .build/XcodeDerivedData.noindex"))
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}

// @ts-nocheck
import { execFileSync } from "child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "fs";
import { homedir } from "os";
import path from "path";
import { log } from "../../../../utils/logging/index.ts";
import { sessionStore } from "../../../../utils/session-store.ts";

const LOG_PREFIX = "[XCTestInput]";
const PROJECT_ROOT = path.join(
  homedir(),
  "Library",
  "Developer",
  "XcodeBuildMCP",
  "xctest-input-runner"
);
const PROJECT_NAME = "XCInputRunner";
const PROJECT_PATH = path.join(PROJECT_ROOT, `${PROJECT_NAME}.xcodeproj`);
const DERIVED_DATA_PATH = path.join(PROJECT_ROOT, "DerivedData");
const RUNNER_APP_DIR = path.join(PROJECT_ROOT, "RunnerApp");
const RUNNER_TESTS_DIR = path.join(PROJECT_ROOT, "RunnerUITests");
const PROJECT_YML_PATH = path.join(PROJECT_ROOT, "project.yml");
const RUNNER_APP_SWIFT_PATH = path.join(RUNNER_APP_DIR, "RunnerApp.swift");
const RUNNER_TESTS_SWIFT_PATH = path.join(RUNNER_TESTS_DIR, "InputRunnerUITests.swift");
const MAX_ERROR_OUTPUT_LENGTH = 12e3;
let xcodeMajorVersionCache;
let xcodegenPathCache;

function readActiveXcodeMajorVersion() {
  if (xcodeMajorVersionCache !== void 0) {
    return xcodeMajorVersionCache;
  }
  try {
    const output = execFileSync("/usr/bin/xcrun", ["xcodebuild", "-version"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"]
    });
    const match = output.match(/^Xcode\s+(\d+)/m);
    xcodeMajorVersionCache = match ? Number.parseInt(match[1], 10) : null;
  } catch {
    xcodeMajorVersionCache = null;
  }
  return xcodeMajorVersionCache;
}

function shouldUseXcode27XCTestInputFallback() {
  if (process.env.XCODEBUILDMCP_DISABLE_XCODE27_XCTEST_INPUT_FALLBACK === "1") {
    return false;
  }
  const majorVersion = readActiveXcodeMajorVersion();
  return majorVersion !== null && majorVersion >= 27;
}

function findXcodegenPath() {
  if (xcodegenPathCache !== void 0) {
    return xcodegenPathCache;
  }
  const candidates = ["/opt/homebrew/bin/xcodegen", "/usr/local/bin/xcodegen"];
  for (const candidate of candidates) {
    if (existsSync(candidate)) {
      xcodegenPathCache = candidate;
      return xcodegenPathCache;
    }
  }
  try {
    const output = execFileSync("/usr/bin/env", ["bash", "-lc", "command -v xcodegen"], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"]
    }).trim();
    xcodegenPathCache = output.length > 0 ? output : null;
  } catch {
    xcodegenPathCache = null;
  }
  return xcodegenPathCache;
}

function writeFileIfChanged(filePath, content) {
  if (existsSync(filePath)) {
    try {
      if (readFileSync(filePath, "utf8") === content) {
        return;
      }
    } catch {
      // Fall through and rewrite the file.
    }
  }
  writeFileSync(filePath, content, "utf8");
}

function b64(value) {
  return Buffer.from(value ?? "", "utf8").toString("base64");
}

function truncateOutput(output) {
  if (!output) {
    return "";
  }
  if (output.length <= MAX_ERROR_OUTPUT_LENGTH) {
    return output;
  }
  return `${output.slice(0, MAX_ERROR_OUTPUT_LENGTH)}\n... truncated ...`;
}

function formatCommandFailure(result) {
  return truncateOutput([result.error, result.output].filter(Boolean).join("\n").trim());
}

function createRunnerAppSource() {
  return `import SwiftUI

@main
struct RunnerApp: App {
    var body: some Scene {
        WindowGroup {
            Color.clear
        }
    }
}
`;
}

function createRunnerTestsSource() {
  return `import Foundation
import XCTest

final class InputRunnerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testTap() throws {
        let app = try targetApp()
        if let target = findElement(in: app, preferTextInput: false) {
            target.tap()
            return
        }
        try tapCoordinate(in: app)
    }

    func testTypeText() throws {
        let app = try targetApp()
        let text = decoded("TARGET_TEXT_B64")

        if let target = findElement(in: app, preferTextInput: true) {
            target.tap()
            if shouldReplaceExisting {
                clearExistingText(in: target)
            }
            target.typeText(text)
            return
        }

        try tapCoordinate(in: app)
        if shouldReplaceExisting {
            app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 256))
        }
        app.typeText(text)
    }

    private var shouldReplaceExisting: Bool {
        ProcessInfo.processInfo.environment["TARGET_REPLACE_EXISTING"] == "1"
    }

    private func targetApp() throws -> XCUIApplication {
        let bundleIdentifier = decoded("TARGET_BUNDLE_ID_B64")
        XCTAssertFalse(bundleIdentifier.isEmpty, "Missing TARGET_BUNDLE_ID_B64")

        let app = XCUIApplication(bundleIdentifier: bundleIdentifier)
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10), "Target app did not enter foreground: \\(bundleIdentifier)")
        return app
    }

    private func findElement(in app: XCUIApplication, preferTextInput: Bool) -> XCUIElement? {
        let identifier = decoded("TARGET_IDENTIFIER_B64")
        let label = decoded("TARGET_LABEL_B64")
        let value = decoded("TARGET_VALUE_B64")
        let role = decoded("TARGET_ROLE_B64")

        if !identifier.isEmpty {
            let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            if element.waitForExistence(timeout: 1) {
                return element
            }
        }

        let queries = candidateQueries(in: app, role: role, preferTextInput: preferTextInput)
        if let element = firstExistingElement(named: label, in: queries) {
            return element
        }
        if let element = firstExistingElement(named: value, in: queries) {
            return element
        }
        return nil
    }

    private func candidateQueries(in app: XCUIApplication, role: String, preferTextInput: Bool) -> [XCUIElementQuery] {
        let textInputQueries = [app.textFields, app.secureTextFields, app.textViews]
        if preferTextInput || role == "text-field" {
            return textInputQueries
        }
        switch role {
        case "button":
            return [app.buttons]
        case "switch":
            return [app.switches]
        case "tab":
            return [app.buttons, app.otherElements, app.descendants(matching: .any)]
        default:
            return [app.buttons, app.switches, app.textFields, app.secureTextFields, app.textViews, app.otherElements, app.descendants(matching: .any)]
        }
    }

    private func firstExistingElement(named name: String, in queries: [XCUIElementQuery]) -> XCUIElement? {
        guard !name.isEmpty else {
            return nil
        }
        for query in queries {
            let element = query[name].firstMatch
            if element.waitForExistence(timeout: 1) {
                return element
            }
        }
        return nil
    }

    private func clearExistingText(in element: XCUIElement) {
        let currentValue = (element.value as? String) ?? ""
        let placeholderValue = decoded("TARGET_VALUE_B64")
        if currentValue.isEmpty || currentValue == placeholderValue {
            return
        }
        let deleteCount = min(max(currentValue.count, 1), 512)
        element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: deleteCount))
    }

    private func tapCoordinate(in app: XCUIApplication) throws {
        let coordinate = try targetCoordinate(in: app)
        coordinate.tap()
    }

    private func targetCoordinate(in app: XCUIApplication) throws -> XCUICoordinate {
        let x = try requiredDouble("TARGET_X")
        let y = try requiredDouble("TARGET_Y")
        let frame = app.frame
        let dx = clamped((x - frame.minX) / max(frame.width, 1), lower: 0.01, upper: 0.99)
        let dy = clamped((y - frame.minY) / max(frame.height, 1), lower: 0.01, upper: 0.99)
        return app.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy))
    }

    private func decoded(_ name: String) -> String {
        guard let encoded = ProcessInfo.processInfo.environment[name],
              let data = Data(base64Encoded: encoded),
              let value = String(data: data, encoding: .utf8) else {
            return ""
        }
        return value
    }

    private func requiredDouble(_ name: String) throws -> CGFloat {
        guard let raw = ProcessInfo.processInfo.environment[name],
              let value = Double(raw) else {
            throw XCTSkip("Missing numeric environment value: \\(name)")
        }
        return CGFloat(value)
    }

    private func clamped(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
`;
}

function createProjectSpec(env) {
  const envLines = Object.entries(env).map(([key, value]) => `        ${key}: "${value}"`).join("\n");
  return `name: XCInputRunner
options:
  bundleIdPrefix: com.openai.xcodebuildmcp
  deploymentTarget:
    iOS: "17.0"
targets:
  RunnerApp:
    type: application
    platform: iOS
    sources:
      - RunnerApp
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.openai.xcodebuildmcp.XCInputRunner
      GENERATE_INFOPLIST_FILE: YES
  RunnerUITests:
    type: bundle.ui-testing
    platform: iOS
    sources:
      - RunnerUITests
    dependencies:
      - target: RunnerApp
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: com.openai.xcodebuildmcp.XCInputRunnerUITests
      GENERATE_INFOPLIST_FILE: YES
      TEST_TARGET_NAME: RunnerApp
schemes:
  RunnerUITests:
    build:
      targets:
        RunnerApp: all
        RunnerUITests: [test]
    test:
      targets:
        - RunnerUITests
      environmentVariables:
${envLines}
`;
}

function getApplicationLabel(snapshot) {
  return snapshot.payload.elements.find((element) => element.role === "application" && element.label)?.label ?? null;
}

function normalizeName(value) {
  return typeof value === "string" ? value.replace(/\s+/g, " ").trim().toLowerCase() : "";
}

function isInstalledUserApp(info) {
  return info?.ApplicationType === "User" || info?.IsDeveloperApp === 1 || info?.IsDeveloperApp === true;
}

async function readInstalledApps(simulatorId, executor) {
  const result = await executor(
    [
      "/bin/sh",
      "-c",
      '/usr/bin/xcrun simctl listapps "$1" --json | /usr/bin/plutil -convert json -o - -',
      "xcodebuildmcp-listapps",
      simulatorId
    ],
    `${LOG_PREFIX}: List installed apps`,
    false
  );
  if (!result.success) {
    throw new Error(`Failed to list installed simulator apps. ${formatCommandFailure(result)}`);
  }
  try {
    return JSON.parse(result.output);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`Failed to parse installed simulator apps: ${message}`);
  }
}

async function resolveBundleIdFromSnapshot(params) {
  const appLabel = getApplicationLabel(params.snapshot);
  let installedApps = null;
  if (appLabel) {
    installedApps = await readInstalledApps(params.simulatorId, params.executor);
    const label = normalizeName(appLabel);
    const records = Object.entries(installedApps).map(([bundleId, info]) => ({
      bundleId,
      info
    }));
    const matches = records.filter(({ info }) => {
      if (!info || typeof info !== "object") {
        return false;
      }
      const names = [
        info.CFBundleDisplayName,
        info.CFBundleName,
        info.CFBundleExecutable,
        info.Path ? path.basename(String(info.Path), ".app") : null
      ].map(normalizeName);
      return names.includes(label);
    });
    const userMatch = matches.find(({ info }) => isInstalledUserApp(info));
    if (userMatch) {
      return userMatch.bundleId;
    }
    if (matches[0]) {
      return matches[0].bundleId;
    }
  }

  const sessionBundleId = sessionStore.get("bundleId");
  if (typeof sessionBundleId === "string" && sessionBundleId.length > 0) {
    return sessionBundleId;
  }

  if (!installedApps) {
    installedApps = await readInstalledApps(params.simulatorId, params.executor);
  }
  const userApps = Object.entries(installedApps).filter(([, info]) => isInstalledUserApp(info));
  if (userApps.length === 1) {
    return userApps[0][0];
  }

  throw new Error(
    "Could not resolve target bundle identifier for XCTest input. Set session default bundleId or launch the target app through XcodeBuildMCP before retrying."
  );
}

function materializeRunnerProject(env) {
  const xcodegenPath = findXcodegenPath();
  if (!xcodegenPath) {
    throw new Error("Xcode 27 XCTest input fallback requires xcodegen, but xcodegen was not found in PATH, /opt/homebrew/bin, or /usr/local/bin.");
  }
  mkdirSync(RUNNER_APP_DIR, { recursive: true });
  mkdirSync(RUNNER_TESTS_DIR, { recursive: true });
  writeFileIfChanged(RUNNER_APP_SWIFT_PATH, createRunnerAppSource());
  writeFileIfChanged(RUNNER_TESTS_SWIFT_PATH, createRunnerTestsSource());
  writeFileIfChanged(PROJECT_YML_PATH, createProjectSpec(env));
  return xcodegenPath;
}

async function runInputAction(params) {
  const target = params.element.publicElement;
  const bundleId = await resolveBundleIdFromSnapshot({
    simulatorId: params.simulatorId,
    snapshot: params.snapshot,
    executor: params.executor
  });
  const env = {
    TARGET_BUNDLE_ID_B64: b64(bundleId),
    TARGET_ELEMENT_REF_B64: b64(target.ref),
    TARGET_ROLE_B64: b64(target.role ?? ""),
    TARGET_LABEL_B64: b64(target.label ?? ""),
    TARGET_VALUE_B64: b64(target.value ?? ""),
    TARGET_IDENTIFIER_B64: b64(target.identifier ?? ""),
    TARGET_X: String(params.activationPoint.x),
    TARGET_Y: String(params.activationPoint.y),
    TARGET_REPLACE_EXISTING: params.replaceExisting ? "1" : "0",
    TARGET_TEXT_B64: b64(params.text ?? "")
  };
  const xcodegenPath = materializeRunnerProject(env);
  const xcodegenResult = await params.executor(
    [xcodegenPath, "generate", "--spec", PROJECT_YML_PATH],
    `${LOG_PREFIX}: Generate XCTest input project`,
    false,
    { cwd: PROJECT_ROOT }
  );
  if (!xcodegenResult.success) {
    throw new Error(`Failed to generate XCTest input project. ${formatCommandFailure(xcodegenResult)}`);
  }

  const testMethod = params.action === "type-text" ? "testTypeText" : "testTap";
  const testResult = await params.executor(
    [
      "xcodebuild",
      "test",
      "-project",
      PROJECT_PATH,
      "-scheme",
      "RunnerUITests",
      "-destination",
      `platform=iOS Simulator,id=${params.simulatorId}`,
      "-derivedDataPath",
      DERIVED_DATA_PATH,
      `-only-testing:RunnerUITests/InputRunnerUITests/${testMethod}`
    ],
    `${LOG_PREFIX}: ${params.action}`,
    false,
    { cwd: PROJECT_ROOT }
  );
  if (!testResult.success) {
    throw new Error(`XCTest input action failed. ${formatCommandFailure(testResult)}`);
  }
  log("info", `${LOG_PREFIX}: ${params.action} succeeded for ${target.ref} on ${params.simulatorId}`);
}

export {
  runInputAction,
  shouldUseXcode27XCTestInputFallback
};

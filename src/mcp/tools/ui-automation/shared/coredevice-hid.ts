// @ts-nocheck
import { existsSync } from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { log } from "../../../../utils/logging/index.ts";
import { getDefaultCommandExecutor } from "../../../../utils/execution/index.ts";
import { DependencyError, SystemError } from "../../../../utils/errors.ts";

const LOG_PREFIX = "[CoreDeviceHID]";
const DEFAULT_SURFACE_ARGS = ["402", "874"];

function getCoreDeviceHIDPath() {
  const explicitPath = process.env.XCODEBUILDMCP_COREDEVICE_HID_CLI;
  if (explicitPath && existsSync(explicitPath)) {
    return explicitPath;
  }
  const moduleDir = path.dirname(fileURLToPath(import.meta.url));
  const packageBinary = path.resolve(moduleDir, "..", "bin", "coredevice_hid_cli");
  if (existsSync(packageBinary)) {
    return packageBinary;
  }
  const workspaceBinary = path.resolve(
    process.cwd(),
    ".codex-artifacts",
    "coredevice-hid-probe",
    "coredevice_hid_cli"
  );
  if (existsSync(workspaceBinary)) {
    return workspaceBinary;
  }
  return null;
}

function formatShimFailure(commandName, result) {
  const details = [result.error, result.output].filter(Boolean).join("\n").trim();
  return details.length > 0 ? `CoreDevice HID shim '${commandName}' failed: ${details}` : `CoreDevice HID shim '${commandName}' failed.`;
}

function isCoreDeviceHIDCapabilityFailure(error) {
  const message = error instanceof Error ? error.message : String(error);
  return message.includes("CoreDevice HID capability is absent") || message.includes("UniversalHID service is absent");
}

function getCoreDeviceHIDSurfaceArgs(snapshot) {
  const elements = snapshot?.elements ?? [];
  let maxX = 0;
  let maxY = 0;
  for (const element of elements) {
    const frame = element?.publicElement?.frame;
    if (!frame) {
      continue;
    }
    const x = Number(frame.x);
    const y = Number(frame.y);
    const width = Number(frame.width);
    const height = Number(frame.height);
    if (!Number.isFinite(x) || !Number.isFinite(y) || !Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0) {
      continue;
    }
    maxX = Math.max(maxX, x + width);
    maxY = Math.max(maxY, y + height);
  }
  if (maxX > 0 && maxY > 0) {
    return [String(Math.round(maxX)), String(Math.round(maxY))];
  }
  return DEFAULT_SURFACE_ARGS;
}

async function executeCoreDeviceHIDCommand(commandArgs, simulatorId, commandName, executor = getDefaultCommandExecutor()) {
  const binary = getCoreDeviceHIDPath();
  if (!binary) {
    throw new DependencyError("CoreDevice HID shim binary not found");
  }
  const fullCommand = [binary, simulatorId, ...commandArgs];
  try {
    const result = await executor(fullCommand, `${LOG_PREFIX}: ${commandName}`, false);
    if (!result.success) {
      throw new SystemError(formatShimFailure(commandName, result));
    }
    log("info", `${LOG_PREFIX}: ${commandName} succeeded on ${simulatorId}`);
    return result.output.trim();
  } catch (error) {
    if (error instanceof DependencyError || error instanceof SystemError) {
      throw error;
    }
    throw new SystemError(`Failed to execute CoreDevice HID shim: ${error instanceof Error ? error.message : String(error)}`);
  }
}

export {
  executeCoreDeviceHIDCommand,
  getCoreDeviceHIDPath,
  getCoreDeviceHIDSurfaceArgs,
  isCoreDeviceHIDCapabilityFailure
};

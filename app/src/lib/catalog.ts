import { invoke } from "@tauri-apps/api/core";
import type { CatalogData, DeploymentPlan, ValidationResult } from "./types";

export async function loadCatalog(): Promise<CatalogData> {
  return invoke<CatalogData>("load_catalog");
}

export async function validateSelection(
  packageIds: string[],
  templateIds: string[],
): Promise<ValidationResult> {
  return invoke<ValidationResult>("validate_selection", {
    packageIds,
    templateIds,
  });
}

export async function savePlan(plan: DeploymentPlan): Promise<string> {
  return invoke<string>("save_plan", { plan });
}

export async function runPlan(planPath: string): Promise<string> {
  return invoke<string>("run_plan", { planPath });
}

export async function listWslInstances(): Promise<string[]> {
  return invoke<string[]>("list_wsl_instances");
}

export async function isAdministrator(): Promise<boolean> {
  return invoke<boolean>("is_administrator");
}

export async function getWindowsUsername(): Promise<string> {
  return invoke<string>("get_windows_username");
}

export interface PtyOutput {
  kind: "stdout" | "stderr" | "exit";
  data: string;
}

export async function spawnPty(
  wslName: string,
  command: string,
): Promise<number> {
  return invoke<number>("spawn_pty", { wslName, command });
}

export async function writePty(sessionId: number, data: string): Promise<void> {
  return invoke("write_pty", { sessionId, data });
}

export async function resizePty(
  sessionId: number,
  cols: number,
  rows: number,
): Promise<void> {
  return invoke("resize_pty", { sessionId, cols, rows });
}

export async function killPty(sessionId: number): Promise<void> {
  return invoke("kill_pty", { sessionId });
}

import type {
  CatalogData,
  DeploymentPlan,
  GithubConfig,
  PackageDef,
  PlanPackage,
  PlanTemplate,
  ProjectFormState,
  SelectionState,
  TemplateDef,
  ValidationResult,
} from "./types";

export function slugify(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
}

export function expandPath(
  template: string,
  projectName: string,
  wslUser: string,
): string {
  let path = template.replace("{name}", projectName);
  if (path.startsWith("~")) {
    path = path.replace(/^~/, `/home/${wslUser || "user"}`);
  }
  return path;
}

function resolvePackageDependencies(
  selected: Set<string>,
  templateIds: string[],
  packages: PackageDef[],
  templates: TemplateDef[],
): Set<string> {
  const result = new Set(selected);
  result.add("base");

  for (const tplId of templateIds) {
    const tpl = templates.find((t) => t.id === tplId);
    if (!tpl) continue;
    for (const id of tpl.requiresPackages ?? []) result.add(id);
    for (const cap of tpl.requiresProvides ?? []) {
      for (const pkg of packages) {
        if (pkg.provides?.includes(cap)) result.add(pkg.id);
      }
    }
  }

  let changed = true;
  while (changed) {
    changed = false;
    for (const id of result) {
      const pkg = packages.find((p) => p.id === id);
      if (!pkg) continue;
      for (const req of pkg.requires ?? []) {
        if (!result.has(req)) {
          result.add(req);
          changed = true;
        }
      }
      for (const cap of pkg.requiresProvides ?? []) {
        for (const p of packages) {
          if (p.provides?.includes(cap) && !result.has(p.id)) {
            result.add(p.id);
            changed = true;
          }
        }
      }
    }
  }
  return result;
}

function sortPackages(ids: string[], packages: PackageDef[]): string[] {
  const sorted: string[] = [];
  const visited = new Set<string>();

  function visit(id: string) {
    if (visited.has(id)) return;
    visited.add(id);
    const pkg = packages.find((p) => p.id === id);
    if (pkg) {
      for (const req of pkg.requires ?? []) {
        if (ids.includes(req)) visit(req);
      }
    }
    if (ids.includes(id)) sorted.push(id);
  }

  for (const id of ids) visit(id);
  return sorted;
}

export function validateSelection(
  catalog: CatalogData,
  packageIds: string[],
  templateIds: string[],
): ValidationResult {
  const errors: string[] = [];
  const warnings: string[] = [];
  const pkgSet = new Set(packageIds);
  const tplSet = new Set(templateIds);

  for (const pkg of catalog.packages) {
    if (!pkgSet.has(pkg.id)) continue;
    for (const other of pkg.incompatibleWith ?? []) {
      if (pkgSet.has(other)) {
        errors.push(`Paquet '${pkg.id}' incompatible avec '${other}'`);
      }
    }
  }

  for (const tpl of catalog.templates) {
    if (!tplSet.has(tpl.id)) continue;
    for (const other of tpl.incompatibleWith ?? []) {
      if (tplSet.has(other)) {
        errors.push(`Template '${tpl.id}' incompatible avec '${other}'`);
      }
    }
  }

  if (templateIds.length === 0) {
    warnings.push("Aucun template sélectionné — seuls les paquets seront installés");
  }

  return { valid: errors.length === 0, errors, warnings };
}

export function buildPlan(
  catalog: CatalogData,
  project: ProjectFormState,
  selection: SelectionState,
): { plan: DeploymentPlan; validation: ValidationResult } {
  const slug = slugify(project.projectName);
  const resolved = resolvePackageDependencies(
    selection.packages,
    [...selection.templates],
    catalog.packages,
    catalog.templates,
  );

  const packageIds = sortPackages([...resolved], catalog.packages);
  const templateIds = [...selection.templates];
  const validation = validateSelection(catalog, packageIds, templateIds);

  let projectPath = project.projectPath.trim();
  if (!projectPath && templateIds.length > 0) {
    const tpl = catalog.templates.find((t) => t.id === templateIds[0]);
    if (tpl?.defaultPath) {
      projectPath = expandPath(
        tpl.defaultPath,
        project.projectName,
        project.wslUser,
      );
    }
  }
  if (!projectPath) {
    projectPath = `/home/${project.wslUser || "user"}/${project.projectName}`;
  }

  let domain: string | null = null;
  for (const tplId of templateIds) {
    const tpl = catalog.templates.find((t) => t.id === tplId);
    if (tpl?.domain) {
      domain = `${slug}.local`;
      break;
    }
  }

  const packages: PlanPackage[] = packageIds.map((id) => ({
    id,
    options: selection.packageOptions[id] ?? {},
  }));

  const templates: PlanTemplate[] = templateIds.map((id) => ({
    id,
    options: selection.templateOptions[id] ?? {},
  }));

  const plan: DeploymentPlan = {
    version: 1,
    project: {
      name: project.projectName,
      slug,
      path: projectPath,
      domain,
    },
    wsl: {
      name: project.wslName || `wsl-${slug}`,
      user: project.wslUser || "",
      createNew: project.createNew,
      memory: project.memory,
      processors: parseInt(project.processors, 10) || 4,
      swap: project.swap,
      distribution: catalog.wslDefaults.distribution,
    },
    packages,
    templates,
    github: selection.github,
  };

  return { plan, validation };
}

export function applyPreset(
  catalog: CatalogData,
  presetId: string,
  selection: SelectionState,
): SelectionState {
  const preset = catalog.presets.find((p) => p.id === presetId);
  if (!preset) return selection;

  const packages = new Set(preset.packages);
  const templates = new Set(preset.templates);
  const github: GithubConfig = preset.github ?? selection.github;

  return {
    packages,
    packageOptions: { ...(preset.packageOptions ?? {}) },
    templates,
    templateOptions: { ...(preset.templateOptions ?? {}) },
    github,
  };
}

export function defaultSelection(catalog: CatalogData): SelectionState {
  const packages = new Set<string>(["base"]);
  for (const pkg of catalog.packages) {
    if (pkg.defaultSelected) packages.add(pkg.id);
  }
  return {
    packages,
    packageOptions: {},
    templates: new Set(),
    templateOptions: {},
    github: {
      init: true,
      createRemote: "ask",
      visibility: "private",
      userName: "",
      userEmail: "",
    },
  };
}

export function defaultProjectForm(catalog: CatalogData): ProjectFormState {
  return {
    projectName: "mon-projet",
    projectPath: "",
    wslName: "",
    wslUser: "",
    createNew: true,
    memory: catalog.wslDefaults.memory,
    processors: String(catalog.wslDefaults.processors),
    swap: catalog.wslDefaults.swap,
  };
}

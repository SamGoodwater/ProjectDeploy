export interface CatalogOption {
  id: string;
  label: string;
  type: "select" | "boolean" | "text";
  choices?: string[];
  default?: string | boolean;
}

export interface PackageDef {
  id: string;
  label: string;
  description?: string;
  category: string;
  script: string;
  requires?: string[];
  requiresProvides?: string[];
  provides?: string[];
  incompatibleWith?: string[];
  defaultSelected?: boolean;
  hidden?: boolean;
  options?: CatalogOption[];
}

export interface TemplateDef {
  id: string;
  label: string;
  description?: string;
  script: string;
  requiresPackages?: string[];
  requiresProvides?: string[];
  incompatibleWith?: string[];
  interactive?: boolean;
  defaultPath?: string;
  domain?: boolean;
  options?: CatalogOption[];
  github?: { supported?: boolean; fields?: string[] };
}

export interface PresetDef {
  id: string;
  label: string;
  description?: string;
  packages: string[];
  packageOptions?: Record<string, Record<string, unknown>>;
  templates: string[];
  templateOptions?: Record<string, Record<string, unknown>>;
  github?: GithubConfig;
}

export interface WslDefaults {
  distribution: string;
  memory: string;
  processors: number;
  swap: string;
  fields: Array<{
    id: string;
    label: string;
    type: string;
    required?: boolean;
    default?: string | boolean;
    choices?: string[];
  }>;
}

export interface GithubConfig {
  init: boolean;
  createRemote: "none" | "ask" | "private" | "public";
  visibility: "private" | "public";
}

export interface PlanPackage {
  id: string;
  options: Record<string, unknown>;
}

export interface PlanTemplate {
  id: string;
  options: Record<string, unknown>;
}

export interface DeploymentPlan {
  version: number;
  project: {
    name: string;
    slug: string;
    path: string;
    domain?: string | null;
  };
  wsl: {
    name: string;
    user: string;
    createNew: boolean;
    memory: string;
    processors: number;
    swap: string;
    distribution: string;
  };
  packages: PlanPackage[];
  templates: PlanTemplate[];
  github: GithubConfig;
}

export interface CatalogData {
  packages: PackageDef[];
  templates: TemplateDef[];
  presets: PresetDef[];
  wslDefaults: WslDefaults;
}

export interface ValidationResult {
  valid: boolean;
  errors: string[];
  warnings: string[];
}

export interface ProjectFormState {
  projectName: string;
  projectPath: string;
  wslName: string;
  wslUser: string;
  createNew: boolean;
  memory: string;
  processors: string;
  swap: string;
}

export interface SelectionState {
  packages: Set<string>;
  packageOptions: Record<string, Record<string, unknown>>;
  templates: Set<string>;
  templateOptions: Record<string, Record<string, unknown>>;
  github: GithubConfig;
}

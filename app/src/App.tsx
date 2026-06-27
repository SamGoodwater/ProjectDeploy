import { useCallback, useEffect, useMemo, useState } from "react";
import {
  getWindowsUsername,
  isAdministrator,
  listWslInstances,
  loadCatalog,
  runPlan,
  savePlan,
} from "./lib/catalog";
import {
  applyPreset,
  buildPlan,
  defaultProjectForm,
  defaultSelection,
  slugify,
} from "./lib/graph";
import type {
  CatalogData,
  ProjectFormState,
  SelectionState,
} from "./lib/types";
import { Step1Project } from "./steps/Step1Project";
import { Step2Packages } from "./steps/Step2Packages";
import { Step3Templates } from "./steps/Step3Templates";
import { TerminalView } from "./components/Terminal";

const STEPS = ["Projet & WSL", "Paquets", "Templates", "Installation"];

export default function App() {
  const [step, setStep] = useState(0);
  const [catalog, setCatalog] = useState<CatalogData | null>(null);
  const [form, setForm] = useState<ProjectFormState | null>(null);
  const [selection, setSelection] = useState<SelectionState | null>(null);
  const [wslInstances, setWslInstances] = useState<string[]>([]);
  const [isAdmin, setIsAdmin] = useState(false);
  const [log, setLog] = useState("");
  const [running, setRunning] = useState(false);
  const [ptyCommand, setPtyCommand] = useState("");
  const [error, setError] = useState("");

  useEffect(() => {
    (async () => {
      try {
        const data = await loadCatalog();
        setCatalog(data);
        setForm(defaultProjectForm(data));
        setSelection(defaultSelection(data));
        const instances = await listWslInstances();
        setWslInstances(instances);
        setIsAdmin(await isAdministrator());
        const winUser = await getWindowsUsername();
        setForm((f) => (f ? { ...f, wslUser: winUser } : f));
      } catch (e) {
        setError(String(e));
      }
    })();
  }, []);

  const resolvedPackageIds = useMemo(() => {
    if (!catalog || !selection) return new Set<string>();
    const { plan } = buildPlan(catalog, form!, selection);
    return new Set(plan.packages.map((p) => p.id));
  }, [catalog, form, selection]);

  const planPreview = useMemo(() => {
    if (!catalog || !form || !selection) return null;
    return buildPlan(catalog, form, selection);
  }, [catalog, form, selection]);

  const applyPresetHandler = (presetId: string) => {
    if (!catalog || !selection) return;
    setSelection(applyPreset(catalog, presetId, selection));
  };

  const togglePackage = (id: string, checked: boolean) => {
    if (!selection) return;
    const next = new Set(selection.packages);
    if (checked) next.add(id);
    else if (id !== "base") next.delete(id);
    setSelection({ ...selection, packages: next });
  };

  const toggleTemplate = (id: string, checked: boolean) => {
    if (!selection) return;
    const next = new Set(selection.templates);
    if (checked) next.add(id);
    else next.delete(id);
    setSelection({ ...selection, templates: next });
  };

  const exportPlan = async () => {
    if (!catalog || !form || !selection || !planPreview?.validation.valid) return;
    const slug = slugify(form.projectName);
    const finalForm = { ...form, wslName: form.wslName || `wsl-${slug}` };
    const { plan } = buildPlan(catalog, finalForm, selection);
    const path = await savePlan(plan);
    setLog(`Plan exporté : ${path}\n`);
    alert(`Plan sauvegardé :\n${path}`);
  };

  const launchInstall = useCallback(async () => {
    if (!catalog || !form || !selection || !planPreview) return;
    if (!planPreview.validation.valid) return;

    setRunning(true);
    setStep(3);
    setLog("Génération du plan...\n");

    try {
      const slug = slugify(form.projectName);
      const wslName = form.wslName || `wsl-${slug}`;
      const finalForm = { ...form, wslName };

      const { plan } = buildPlan(catalog, finalForm, selection);
      const planPath = await savePlan(plan);
      setLog((l) => l + `Plan : ${planPath}\nLancement...\n`);

      const output = await runPlan(planPath);
      setLog((l) => l + output + "\n");

      const interactiveTpl = catalog.templates.find(
        (t) => selection.templates.has(t.id) && t.interactive,
      );
      if (interactiveTpl) {
        setPtyCommand(`cd '${plan.project.path}' && exec bash -l`);
        setLog((l) =>
          l +
          `\nTerminal interactif ouvert dans ${plan.project.path}\n` +
          `(templates interactifs : ${interactiveTpl.label})\n`,
        );
      }
    } catch (e) {
      setLog((l) => l + `\nErreur : ${e}\n`);
    } finally {
      setRunning(false);
    }
  }, [catalog, form, selection, planPreview]);

  if (error) {
    return (
      <div className="app-shell">
        <div className="alert error">{error}</div>
      </div>
    );
  }

  if (!catalog || !form || !selection || !planPreview) {
    return <div className="app-shell">Chargement...</div>;
  }

  const slug = slugify(form.projectName);
  const wslName = form.wslName || `wsl-${slug}`;

  return (
    <div className="app-shell">
      <header className="header">
        <h1>ProjectDeploy v2</h1>
        <p style={{ color: "#9aa5b1", margin: 0 }}>
          Assistant de déploiement WSL — catalogue JSON
        </p>
        {!isAdmin && (
          <div className="alert warning" style={{ marginTop: 12 }}>
            Exécution sans droits administrateur — création WSL et hosts
            peuvent échouer.
          </div>
        )}
      </header>

      {step < 3 && (
        <div className="preset-bar">
          {catalog.presets.map((p) => (
            <button
              key={p.id}
              type="button"
              className="secondary"
              onClick={() => applyPresetHandler(p.id)}
            >
              {p.label}
            </button>
          ))}
        </div>
      )}

      <nav className="stepper">
        {STEPS.map((label, i) => (
          <div key={label} className={`step${i === step ? " active" : ""}`}>
            {i + 1}. {label}
          </div>
        ))}
      </nav>

      {step === 0 && (
        <Step1Project
          defaults={catalog.wslDefaults}
          form={form}
          wslInstances={wslInstances}
          onChange={setForm}
        />
      )}

      {step === 1 && (
        <Step2Packages
          packages={catalog.packages}
          selected={selection.packages}
          options={selection.packageOptions}
          resolvedIds={resolvedPackageIds}
          onToggle={togglePackage}
          onOptionChange={(pkgId, optId, value) => {
            setSelection({
              ...selection,
              packageOptions: {
                ...selection.packageOptions,
                [pkgId]: {
                  ...(selection.packageOptions[pkgId] ?? {}),
                  [optId]: value,
                },
              },
            });
          }}
        />
      )}

      {step === 2 && (
        <Step3Templates
          templates={catalog.templates}
          selected={selection.templates}
          github={selection.github}
          recap={{
            projectName: form.projectName,
            projectPath: planPreview.plan.project.path,
            wslName,
            packageCount: planPreview.plan.packages.length,
          }}
          validationErrors={planPreview.validation.errors}
          validationWarnings={planPreview.validation.warnings}
          onToggle={toggleTemplate}
          onGithubChange={(github) => setSelection({ ...selection, github })}
        />
      )}

      {step === 3 && (
        <div className="console-panel panel">
          <h2>Installation</h2>
          <div className="console-log">{log}</div>
          {ptyCommand && (
            <TerminalView
              wslName={wslName}
              command={ptyCommand}
              active={!running}
              onExit={(code) =>
                setLog((l) => l + `\nTerminal terminé (code ${code})\n`)
              }
            />
          )}
        </div>
      )}

      <div className="actions">
        {step > 0 && step < 3 && (
          <button
            type="button"
            className="secondary"
            onClick={() => setStep((s) => s - 1)}
          >
            Retour
          </button>
        )}
        {step < 2 && (
          <button
            type="button"
            className="primary"
            onClick={() => setStep((s) => s + 1)}
          >
            Suivant
          </button>
        )}
        {step === 2 && (
          <>
            <button type="button" className="secondary" onClick={exportPlan}>
              Exporter le plan JSON
            </button>
            <button
              type="button"
              className="primary"
              disabled={!planPreview.validation.valid || running}
              onClick={launchInstall}
            >
              Lancer l'installation
            </button>
          </>
        )}
      </div>
    </div>
  );
}

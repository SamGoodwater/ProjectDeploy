import type { ProjectFormState, WslDefaults } from "../lib/types";

interface Props {
  defaults: WslDefaults;
  form: ProjectFormState;
  wslInstances: string[];
  onChange: (form: ProjectFormState) => void;
}

export function Step1Project({ defaults, form, wslInstances, onChange }: Props) {
  const update = (patch: Partial<ProjectFormState>) =>
    onChange({ ...form, ...patch });

  return (
    <div className="panel">
      <h2>Projet & WSL</h2>

      <div className="field">
        <label htmlFor="projectName">Nom du projet</label>
        <input
          id="projectName"
          value={form.projectName}
          onChange={(e) => update({ projectName: e.target.value })}
        />
      </div>

      <div className="field">
        <label htmlFor="projectPath">Chemin Linux (optionnel)</label>
        <input
          id="projectPath"
          placeholder="Auto selon le template"
          value={form.projectPath}
          onChange={(e) => update({ projectPath: e.target.value })}
        />
      </div>

      <div className="field">
        <label htmlFor="wslName">Nom de l'instance WSL</label>
        <input
          id="wslName"
          placeholder="wsl-mon-projet"
          value={form.wslName}
          onChange={(e) => update({ wslName: e.target.value })}
        />
      </div>

      <div className="field">
        <label htmlFor="wslUser">Utilisateur Debian</label>
        <input
          id="wslUser"
          placeholder="Utilisateur Windows par défaut"
          value={form.wslUser}
          onChange={(e) => update({ wslUser: e.target.value })}
        />
      </div>

      <div className="checkbox-row">
        <input
          type="checkbox"
          id="createNew"
          checked={form.createNew}
          onChange={(e) => update({ createNew: e.target.checked })}
        />
        <label htmlFor="createNew">Créer une nouvelle instance WSL Debian</label>
      </div>

      <div className="field">
        <label htmlFor="memory">Mémoire</label>
        <select
          id="memory"
          value={form.memory}
          onChange={(e) => update({ memory: e.target.value })}
        >
          {["4GB", "8GB", "16GB", "32GB"].map((v) => (
            <option key={v} value={v}>
              {v}
            </option>
          ))}
        </select>
      </div>

      <div className="field">
        <label htmlFor="processors">Processeurs</label>
        <select
          id="processors"
          value={form.processors}
          onChange={(e) => update({ processors: e.target.value })}
        >
          {["2", "4", "8", "16"].map((v) => (
            <option key={v} value={v}>
              {v}
            </option>
          ))}
        </select>
      </div>

      <div className="field">
        <label htmlFor="swap">Swap</label>
        <select
          id="swap"
          value={form.swap}
          onChange={(e) => update({ swap: e.target.value })}
        >
          {["0GB", "4GB", "8GB", "16GB"].map((v) => (
            <option key={v} value={v}>
              {v}
            </option>
          ))}
        </select>
      </div>

      {wslInstances.length > 0 && (
        <p style={{ color: "#9aa5b1", fontSize: "0.85rem" }}>
          WSL existantes : {wslInstances.join(", ")}
        </p>
      )}

      <p style={{ color: "#9aa5b1", fontSize: "0.85rem" }}>
        Distribution : {defaults.distribution}
      </p>
    </div>
  );
}

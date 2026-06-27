import type { GithubConfig, TemplateDef } from "../lib/types";

interface Props {
  templates: TemplateDef[];
  selected: Set<string>;
  github: GithubConfig;
  recap: {
    projectName: string;
    projectPath: string;
    wslName: string;
    packageCount: number;
  };
  validationErrors: string[];
  validationWarnings: string[];
  onToggle: (id: string, checked: boolean) => void;
  onGithubChange: (github: GithubConfig) => void;
}

export function Step3Templates({
  templates,
  selected,
  github,
  recap,
  validationErrors,
  validationWarnings,
  onToggle,
  onGithubChange,
}: Props) {
  const githubSupported = templates.some(
    (t) => selected.has(t.id) && t.github?.supported,
  );

  return (
    <>
      <div className="panel">
        <h2>Initialisation du projet</h2>

        {templates.map((tpl) => (
          <div key={tpl.id} className="checkbox-row">
            <input
              type="checkbox"
              checked={selected.has(tpl.id)}
              onChange={(e) => onToggle(tpl.id, e.target.checked)}
            />
            <div>
              <strong>{tpl.label}</strong>
              {tpl.interactive && (
                <small> — installation interactive (terminal)</small>
              )}
              {tpl.description && <small>{tpl.description}</small>}
            </div>
          </div>
        ))}
      </div>

      {githubSupported && (
        <div className="panel">
          <h2>GitHub</h2>
          <div className="checkbox-row">
            <input
              type="checkbox"
              checked={github.init}
              onChange={(e) =>
                onGithubChange({ ...github, init: e.target.checked })
              }
            />
            <label>Initialiser Git localement</label>
          </div>
          <div className="field">
            <label>Dépôt distant</label>
            <select
              value={github.createRemote}
              onChange={(e) =>
                onGithubChange({
                  ...github,
                  createRemote: e.target.value as GithubConfig["createRemote"],
                })
              }
            >
              <option value="none">Aucun</option>
              <option value="ask">Demander / privé si gh auth</option>
              <option value="private">Créer privé</option>
              <option value="public">Créer public</option>
            </select>
          </div>
          <div className="field">
            <label>Visibilité par défaut</label>
            <select
              value={github.visibility}
              onChange={(e) =>
                onGithubChange({
                  ...github,
                  visibility: e.target.value as GithubConfig["visibility"],
                })
              }
            >
              <option value="private">Privé</option>
              <option value="public">Public</option>
            </select>
          </div>
        </div>
      )}

      <div className="panel">
        <h2>Récapitulatif</h2>
        {validationErrors.map((e) => (
          <div key={e} className="alert error">
            {e}
          </div>
        ))}
        {validationWarnings.map((w) => (
          <div key={w} className="alert warning">
            {w}
          </div>
        ))}
        <dl className="recap">
          <dt>Projet</dt>
          <dd>{recap.projectName}</dd>
          <dt>Chemin</dt>
          <dd>{recap.projectPath}</dd>
          <dt>WSL</dt>
          <dd>{recap.wslName}</dd>
          <dt>Paquets</dt>
          <dd>{recap.packageCount}</dd>
          <dt>Templates</dt>
          <dd>{[...selected].join(", ") || "—"}</dd>
        </dl>
      </div>
    </>
  );
}

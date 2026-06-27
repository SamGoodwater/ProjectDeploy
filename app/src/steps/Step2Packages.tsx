import type { CatalogOption, PackageDef } from "../lib/types";

interface Props {
  packages: PackageDef[];
  selected: Set<string>;
  options: Record<string, Record<string, unknown>>;
  resolvedIds: Set<string>;
  onToggle: (id: string, checked: boolean) => void;
  onOptionChange: (
    pkgId: string,
    optId: string,
    value: string | boolean,
  ) => void;
}

export function Step2Packages({
  packages,
  selected,
  options,
  resolvedIds,
  onToggle,
  onOptionChange,
}: Props) {
  const visible = packages.filter((p) => !p.hidden);

  return (
    <div className="panel">
      <h2>Paquets à installer</h2>
      <p style={{ color: "#9aa5b1", marginTop: 0 }}>
        Les dépendances sont cochées automatiquement.
      </p>

      {visible.map((pkg) => {
        const isSelected = selected.has(pkg.id) || resolvedIds.has(pkg.id);
        const autoRequired = resolvedIds.has(pkg.id) && !selected.has(pkg.id);
        const disabled = pkg.id === "base" || autoRequired;

        return (
          <div
            key={pkg.id}
            className={`checkbox-row${disabled ? " disabled" : ""}`}
          >
            <input
              type="checkbox"
              checked={isSelected}
              disabled={disabled}
              onChange={(e) => onToggle(pkg.id, e.target.checked)}
            />
            <div>
              <strong>{pkg.label}</strong>
              {autoRequired && (
                <small> — requis par une dépendance</small>
              )}
              {pkg.description && <small>{pkg.description}</small>}
              {isSelected &&
                pkg.options?.map((opt) => (
                  <PackageOptionField
                    key={opt.id}
                    pkgId={pkg.id}
                    option={opt}
                    value={options[pkg.id]?.[opt.id]}
                    onChange={onOptionChange}
                  />
                ))}
            </div>
          </div>
        );
      })}
    </div>
  );
}

function PackageOptionField({
  pkgId,
  option,
  value,
  onChange,
}: {
  pkgId: string;
  option: CatalogOption;
  value: unknown;
  onChange: (pkgId: string, optId: string, value: string | boolean) => void;
}) {
  if (option.type === "select") {
    return (
      <div className="field" style={{ marginTop: 8 }}>
        <label>{option.label}</label>
        <select
          value={String(value ?? option.default ?? "")}
          onChange={(e) => onChange(pkgId, option.id, e.target.value)}
        >
          {(option.choices ?? []).map((c) => (
            <option key={c} value={c}>
              {c}
            </option>
          ))}
        </select>
      </div>
    );
  }

  if (option.type === "boolean") {
    return (
      <div className="checkbox-row">
        <input
          type="checkbox"
          checked={Boolean(value ?? option.default ?? false)}
          onChange={(e) => onChange(pkgId, option.id, e.target.checked)}
        />
        <label>{option.label}</label>
      </div>
    );
  }

  return (
    <div className="field" style={{ marginTop: 8 }}>
      <label>{option.label}</label>
      <input
        value={String(value ?? option.default ?? "")}
        onChange={(e) => onChange(pkgId, option.id, e.target.value)}
      />
    </div>
  );
}

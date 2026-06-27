use std::collections::{HashMap, HashSet};
use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::thread;

use portable_pty::{native_pty_system, CommandBuilder, PtySize};
use serde::Serialize;
use serde_json::Value;
use tauri::{AppHandle, Emitter, State};

struct PtySession {
    master: Arc<Mutex<Box<dyn portable_pty::MasterPty + Send>>>,
    writer: Arc<Mutex<Option<Box<dyn Write + Send>>>>,
}

#[derive(Default)]
pub struct PtyState {
    sessions: Mutex<HashMap<u64, PtySession>>,
}

fn repo_root() -> PathBuf {
    if let Ok(env) = std::env::var("PROJECT_DEPLOY_ROOT") {
        return PathBuf::from(env);
    }
    let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    manifest
        .join("..")
        .join("..")
        .canonicalize()
        .unwrap_or(manifest)
}

fn read_json(path: &Path) -> Result<Value, String> {
    let raw = fs::read_to_string(path).map_err(|e| e.to_string())?;
    serde_json::from_str(&raw).map_err(|e| e.to_string())
}

fn load_dir_json(dir: &Path) -> Result<Vec<Value>, String> {
    if !dir.exists() {
        return Ok(vec![]);
    }
    let mut items = vec![];
    let mut paths: Vec<_> = fs::read_dir(dir)
        .map_err(|e| e.to_string())?
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| p.extension().map(|x| x == "json").unwrap_or(false))
        .collect();
    paths.sort();
    for path in paths {
        items.push(read_json(&path)?);
    }
    Ok(items)
}

#[derive(Serialize)]
struct CatalogData {
    packages: Vec<Value>,
    templates: Vec<Value>,
    presets: Vec<Value>,
    #[serde(rename = "wslDefaults")]
    wsl_defaults: Value,
}

#[tauri::command]
fn load_catalog() -> Result<CatalogData, String> {
    let root = repo_root();
    let catalog = root.join("catalog");
    Ok(CatalogData {
        packages: load_dir_json(&catalog.join("packages"))?,
        templates: load_dir_json(&catalog.join("templates"))?,
        presets: load_dir_json(&catalog.join("presets"))?,
        wsl_defaults: read_json(&catalog.join("wsl").join("defaults.json"))?,
    })
}

#[derive(Serialize)]
struct ValidationResult {
    valid: bool,
    errors: Vec<String>,
    warnings: Vec<String>,
}

#[tauri::command]
fn validate_selection(
    package_ids: Vec<String>,
    template_ids: Vec<String>,
) -> Result<ValidationResult, String> {
    let root = repo_root();
    let catalog = root.join("catalog");
    let packages = load_dir_json(&catalog.join("packages"))?;
    let templates = load_dir_json(&catalog.join("templates"))?;

    let pkg_set: HashSet<String> = package_ids.into_iter().collect();
    let tpl_set: HashSet<String> = template_ids.into_iter().collect();
    let mut errors = vec![];
    let mut warnings = vec![];

    for pkg in &packages {
        let id = pkg.get("id").and_then(|v| v.as_str()).unwrap_or("");
        if !pkg_set.contains(id) {
            continue;
        }
        if let Some(bad) = pkg.get("incompatibleWith").and_then(|v| v.as_array()) {
            for other in bad {
                if let Some(o) = other.as_str() {
                    if pkg_set.contains(o) {
                        errors.push(format!("Paquet '{}' incompatible avec '{}'", id, o));
                    }
                }
            }
        }
    }

    for tpl in &templates {
        let id = tpl.get("id").and_then(|v| v.as_str()).unwrap_or("");
        if !tpl_set.contains(id) {
            continue;
        }
        if let Some(bad) = tpl.get("incompatibleWith").and_then(|v| v.as_array()) {
            for other in bad {
                if let Some(o) = other.as_str() {
                    if tpl_set.contains(o) {
                        errors.push(format!("Template '{}' incompatible avec '{}'", id, o));
                    }
                }
            }
        }
    }

    if tpl_set.is_empty() {
        warnings
            .push("Aucun template sélectionné — seuls les paquets seront installés".to_string());
    }

    Ok(ValidationResult {
        valid: errors.is_empty(),
        errors,
        warnings,
    })
}

#[tauri::command]
fn save_plan(plan: Value) -> Result<String, String> {
    let slug = plan
        .get("project")
        .and_then(|p| p.get("slug"))
        .and_then(|v| v.as_str())
        .unwrap_or("plan");
    let root = repo_root();
    let plans_dir = root.join("plans");
    fs::create_dir_all(&plans_dir).map_err(|e| e.to_string())?;
    let path = plans_dir.join(format!("{}.plan.json", slug));
    let content = serde_json::to_string_pretty(&plan).map_err(|e| e.to_string())?;
    fs::write(&path, content).map_err(|e| e.to_string())?;
    Ok(path.to_string_lossy().to_string())
}

#[tauri::command]
fn run_plan(plan_path: String) -> Result<String, String> {
    let root = repo_root();
    let script = root.join("cli").join("Execute-Plan.ps1");
    if !script.exists() {
        return Err(format!("Script introuvable : {}", script.display()));
    }

    let output = std::process::Command::new("powershell")
        .args([
            "-NoProfile",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            script.to_str().unwrap(),
            "-PlanFile",
            &plan_path,
            "-NonInteractive",
        ])
        .current_dir(&root)
        .output()
        .map_err(|e| e.to_string())?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    if !output.status.success() {
        return Err(format!("{}\n{}", stdout, stderr));
    }
    Ok(format!("{}{}", stdout, stderr))
}

#[tauri::command]
fn list_wsl_instances() -> Result<Vec<String>, String> {
    let output = std::process::Command::new("wsl")
        .args(["--list", "--quiet"])
        .output()
        .map_err(|e| e.to_string())?;
    let text = String::from_utf8_lossy(&output.stdout);
    let names: Vec<String> = text
        .split('\n')
        .map(|l| l.replace('\0', "").trim().to_string())
        .filter(|l| !l.is_empty())
        .collect();
    Ok(names)
}

#[tauri::command]
fn is_administrator() -> Result<bool, String> {
    #[cfg(windows)]
    {
        use std::ptr;
        use windows_sys::Win32::Foundation::BOOL;
        use windows_sys::Win32::Security::Authorization::{
            AllocateAndInitializeSid, CheckTokenMembership, FreeSid,
        };
        use windows_sys::Win32::Security::{DOMAIN_ALIAS_RID_ADMINS, SECURITY_BUILTIN_DOMAIN_RID};

        unsafe {
            let mut admins_group = ptr::null_mut();
            let mut domain = SECURITY_BUILTIN_DOMAIN_RID;
            let mut admins = DOMAIN_ALIAS_RID_ADMINS;
            let ok = AllocateAndInitializeSid(
                &mut domain,
                2,
                admins,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                &mut admins_group,
            );
            if ok == 0 {
                return Ok(false);
            }
            let mut is_member: BOOL = 0;
            CheckTokenMembership(ptr::null_mut(), admins_group, &mut is_member);
            FreeSid(admins_group);
            Ok(is_member != 0)
        }
    }
    #[cfg(not(windows))]
    {
        Ok(false)
    }
}

#[tauri::command]
fn get_windows_username() -> Result<String, String> {
    Ok(std::env::var("USERNAME").unwrap_or_else(|_| "dev".to_string()))
}

#[derive(Clone, Serialize)]
struct PtyOutput {
    kind: String,
    data: String,
}

#[tauri::command]
fn spawn_pty(
    app: AppHandle,
    state: State<PtyState>,
    wsl_name: String,
    command: String,
) -> Result<u64, String> {
    let session_id = uuid::Uuid::new_v4().as_u128() as u64;
    let pty_system = native_pty_system();
    let pair = pty_system
        .openpty(PtySize {
            rows: 24,
            cols: 80,
            pixel_width: 0,
            pixel_height: 0,
        })
        .map_err(|e| e.to_string())?;

    let mut cmd = CommandBuilder::new("wsl.exe");
    cmd.arg("-d")
        .arg(&wsl_name)
        .arg("-e")
        .arg("bash")
        .arg("-lc")
        .arg(&command);

    let mut child = pair
        .slave
        .spawn_command(cmd)
        .map_err(|e| e.to_string())?;
    drop(pair.slave);

    let master = Arc::new(Mutex::new(pair.master));
    let writer = Arc::new(Mutex::new(Some(
        master
            .lock()
            .map_err(|e| e.to_string())?
            .take_writer()
            .map_err(|e| e.to_string())?,
    )));

    let reader = master
        .lock()
        .map_err(|e| e.to_string())?
        .try_clone_reader()
        .map_err(|e| e.to_string())?;

    state
        .sessions
        .lock()
        .map_err(|e| e.to_string())?
        .insert(
            session_id,
            PtySession {
                master: master.clone(),
                writer: writer.clone(),
            },
        );

    let event_name = format!("pty-output-{}", session_id);
    let app_clone = app.clone();

    thread::spawn(move || {
        let mut reader = reader;
        let mut buf = [0u8; 8192];
        loop {
            match reader.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => {
                    let data = String::from_utf8_lossy(&buf[..n]).to_string();
                    let _ = app_clone.emit(
                        &event_name,
                        PtyOutput {
                            kind: "stdout".to_string(),
                            data,
                        },
                    );
                }
                Err(_) => break,
            }
        }
        let status = child.wait().unwrap_or_default();
        let _ = app_clone.emit(
            &event_name,
            PtyOutput {
                kind: "exit".to_string(),
                data: status.exit_code().to_string(),
            },
        );
    });

    Ok(session_id)
}

#[tauri::command]
fn write_pty(state: State<PtyState>, session_id: u64, data: String) -> Result<(), String> {
    let sessions = state.sessions.lock().map_err(|e| e.to_string())?;
    let session = sessions
        .get(&session_id)
        .ok_or("Session PTY introuvable")?;
    let mut guard = session.writer.lock().map_err(|e| e.to_string())?;
    if guard.is_none() {
        *guard = Some(
            session
                .master
                .lock()
                .map_err(|e| e.to_string())?
                .take_writer()
                .map_err(|e| e.to_string())?,
        );
    }
    if let Some(writer) = guard.as_mut() {
        writer.write_all(data.as_bytes()).map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
fn resize_pty(state: State<PtyState>, session_id: u64, cols: u16, rows: u16) -> Result<(), String> {
    let sessions = state.sessions.lock().map_err(|e| e.to_string())?;
    let session = sessions
        .get(&session_id)
        .ok_or("Session PTY introuvable")?;
    session
        .master
        .lock()
        .map_err(|e| e.to_string())?
        .resize(PtySize {
            rows,
            cols,
            pixel_width: 0,
            pixel_height: 0,
        })
        .map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
fn kill_pty(state: State<PtyState>, session_id: u64) -> Result<(), String> {
    state
        .sessions
        .lock()
        .map_err(|e| e.to_string())?
        .remove(&session_id);
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .manage(PtyState::default())
        .invoke_handler(tauri::generate_handler![
            load_catalog,
            validate_selection,
            save_plan,
            run_plan,
            list_wsl_instances,
            is_administrator,
            get_windows_username,
            spawn_pty,
            write_pty,
            resize_pty,
            kill_pty,
        ])
        .run(tauri::generate_context!())
        .expect("erreur au lancement Tauri");
}

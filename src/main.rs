use serde_json::Value;
use std::env;
use std::fs;
use std::io::{self, Read};
use std::process::{Command, Stdio};
use std::time::SystemTime;

fn main() {
    // 1. Read stdin — this is ALL that Claude Code blocks on
    let mut input = String::new();
    if io::stdin().read_to_string(&mut input).is_err() {
        return;
    }

    // 2. Fork: parent exits immediately, child does the work
    unsafe {
        let pid = libc::fork();
        if pid != 0 {
            return; // parent (pid > 0) or error (pid < 0): exit now
        }
        libc::setsid();
    }

    // --- Child process only ---
    let _ = play_sound(&input);
}

fn play_sound(input: &str) -> Option<()> {
    let json: Value = serde_json::from_str(input).ok()?;
    let event = json.get("hook_event_name")?.as_str()?;

    let category = match event {
        "SessionStart" => "greeting",
        "UserPromptSubmit" => "acknowledge",
        "Stop" => "complete",
        "Notification" => "alert",
        _ => return Some(()),
    };

    let plugin_root = env::var("CLAUDE_PLUGIN_ROOT").ok().unwrap_or_else(|| {
        let exe = env::current_exe().unwrap_or_default();
        exe.parent()
            .and_then(|p| p.parent())
            .map(|p| p.to_string_lossy().into_owned())
            .unwrap_or_else(|| ".".to_string())
    });

    let state_dir = "/tmp/doctor-who-sounds";
    fs::create_dir_all(state_dir).ok()?;

    let config_path = format!("{}/config.json", plugin_root);
    let config_str = fs::read_to_string(&config_path).ok()?;
    let config: Value = serde_json::from_str(&config_str).ok()?;

    if config.get("enabled").and_then(|v| v.as_bool()) == Some(false) {
        return Some(());
    }

    if let Some(cats) = config.get("categories") {
        if cats.get(category).and_then(|v| v.as_bool()) == Some(false) {
            return Some(());
        }
    }

    let volume = config
        .get("volume")
        .and_then(|v| v.as_f64())
        .unwrap_or(0.5);

    let active_pack = config
        .get("active_pack")
        .and_then(|v| v.as_str())
        .unwrap_or("new-who");

    let manifest_path = format!("{}/packs/{}/manifest.json", plugin_root, active_pack);
    let manifest_str = fs::read_to_string(&manifest_path).ok()?;
    let manifest: Value = serde_json::from_str(&manifest_str).ok()?;

    let sounds = manifest.get("sounds")?.get(category)?.as_array()?;
    if sounds.is_empty() {
        return Some(());
    }

    let last_file = format!("{}/last_{}", state_dir, category);
    let last_played = fs::read_to_string(&last_file).unwrap_or_default();
    let last_played = last_played.trim();

    let nanos = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .ok()?
        .subsec_nanos() as usize;

    let sound_file = if sounds.len() == 1 {
        sounds[0].as_str()?
    } else {
        let mut pick = "";
        for attempt in 0..3 {
            let idx = (nanos.wrapping_add(attempt * 7)) % sounds.len();
            pick = sounds[idx].as_str().unwrap_or("");
            if pick != last_played {
                break;
            }
        }
        pick
    };

    if sound_file.is_empty() {
        return Some(());
    }

    let sound_path = format!("{}/sounds/{}", plugin_root, sound_file);
    if fs::metadata(&sound_path).is_err() {
        return Some(());
    }

    let _ = fs::write(&last_file, sound_file);

    let player_cache = format!("{}/player", state_dir);
    let player = match fs::read_to_string(&player_cache) {
        Ok(cached) => {
            let cached = cached.trim().to_string();
            if !cached.is_empty() && player_exists(&cached) {
                cached
            } else {
                detect_and_cache_player(&player_cache)
            }
        }
        Err(_) => detect_and_cache_player(&player_cache),
    };

    if player.is_empty() {
        return Some(());
    }

    let mut cmd = Command::new(&player);
    match player.as_str() {
        "afplay" => {
            cmd.arg("-v").arg(volume.to_string()).arg(&sound_path);
        }
        "paplay" => {
            let vol = (volume * 65536.0) as u64;
            cmd.arg(format!("--volume={}", vol)).arg(&sound_path);
        }
        "mpv" => {
            let vol = (volume * 100.0) as u64;
            cmd.arg("--no-terminal")
                .arg(format!("--volume={}", vol))
                .arg(&sound_path);
        }
        "aplay" => {
            cmd.arg("-q").arg(&sound_path);
        }
        _ => return Some(()),
    }

    cmd.stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .ok()?;

    Some(())
}

fn player_exists(name: &str) -> bool {
    Command::new("which")
        .arg(name)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn detect_and_cache_player(cache_path: &str) -> String {
    for candidate in &["afplay", "paplay", "mpv", "aplay"] {
        if player_exists(candidate) {
            let _ = fs::write(cache_path, candidate);
            return candidate.to_string();
        }
    }
    String::new()
}

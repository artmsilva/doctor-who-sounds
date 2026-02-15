use serde_json::Value;
use std::env;
use std::fs;
use std::io::{self, Read, Write};
use std::os::unix::net::{UnixListener, UnixStream};
use std::process::{Command, Stdio};
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, SystemTime};

const STATE_DIR: &str = "/tmp/doctor-who-sounds";
const SOCKET_PATH: &str = "/tmp/doctor-who-sounds/daemon.sock";
const PID_PATH: &str = "/tmp/doctor-who-sounds/daemon.pid";

static RUNNING: AtomicBool = AtomicBool::new(true);

fn main() {
    let args: Vec<String> = env::args().collect();
    match args.get(1).map(|s| s.as_str()) {
        Some("--daemon") => run_daemon(),
        Some("--stop") => stop_daemon(),
        _ => run_client(),
    }
}

// ---------------------------------------------------------------------------
// Client mode (default) — what hooks call
// ---------------------------------------------------------------------------

fn run_client() {
    // Read stdin until EOF, capped at 8KB. Using take() + read_to_string()
    // because a bare read() can return partial data on a pipe, while
    // read_to_string() alone would consume megabytes on large hook payloads.
    let mut input = String::new();
    if io::stdin().take(8192).read_to_string(&mut input).is_err() || input.is_empty() {
        return;
    }

    // Try sending to daemon
    if send_to_daemon(&input) {
        return;
    }

    // Daemon not running — try to spawn it
    if ensure_daemon_running() && send_to_daemon(&input) {
        return;
    }

    // Fallback: fork-based direct play (original behavior, never breaks)
    fork_and_play(&input);
}

fn send_to_daemon(input: &str) -> bool {
    let mut stream = match UnixStream::connect(SOCKET_PATH) {
        Ok(s) => s,
        Err(_) => return false,
    };
    let _ = stream.set_write_timeout(Some(Duration::from_millis(100)));
    stream.write_all(input.as_bytes()).is_ok()
}

fn ensure_daemon_running() -> bool {
    let exe = match env::current_exe() {
        Ok(e) => e,
        Err(_) => return false,
    };

    // Spawn daemon process detached
    let child = Command::new(&exe)
        .arg("--daemon")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();

    if child.is_err() {
        return false;
    }

    // Wait for socket to appear (up to 20 * 10ms = 200ms)
    for _ in 0..20 {
        std::thread::sleep(Duration::from_millis(10));
        if UnixStream::connect(SOCKET_PATH).is_ok() {
            return true;
        }
    }

    false
}

fn fork_and_play(input: &str) {
    unsafe {
        let pid = libc::fork();
        if pid != 0 {
            return; // parent or error: exit
        }
        libc::setsid();
    }
    let _ = play_sound(input);
}

// ---------------------------------------------------------------------------
// Daemon mode (--daemon) — long-running socket listener
// ---------------------------------------------------------------------------

fn run_daemon() {
    // Detach from parent session
    unsafe {
        libc::setsid();
    }

    let _ = fs::create_dir_all(STATE_DIR);

    // Clean up stale socket/PID from crashed daemon
    cleanup_stale_daemon();

    // Write PID file atomically (O_CREAT | O_EXCL via create_new)
    let pid = std::process::id();
    match fs::OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(PID_PATH)
    {
        Ok(mut f) => {
            let _ = f.write_all(pid.to_string().as_bytes());
        }
        Err(ref e) if e.kind() == io::ErrorKind::AlreadyExists => {
            // Another daemon won the race
            return;
        }
        Err(_) => return,
    }

    // Bind socket
    let listener = match UnixListener::bind(SOCKET_PATH) {
        Ok(l) => l,
        Err(_) => {
            let _ = fs::remove_file(PID_PATH);
            return;
        }
    };

    // Non-blocking so we can poll RUNNING flag
    let _ = listener.set_nonblocking(true);

    // Install signal handlers
    unsafe {
        libc::signal(libc::SIGTERM, handle_signal as libc::sighandler_t);
        libc::signal(libc::SIGINT, handle_signal as libc::sighandler_t);
        // Auto-reap child processes (afplay/paplay/mpv) — without this,
        // every finished audio player becomes a zombie for the daemon's lifetime
        libc::signal(libc::SIGCHLD, libc::SIG_IGN);
    }

    // Accept loop — each connection handled in its own thread so
    // play_sound() never blocks the next accept()
    while RUNNING.load(Ordering::Relaxed) {
        match listener.accept() {
            Ok((stream, _)) => {
                std::thread::spawn(move || {
                    let _ = stream.set_read_timeout(Some(Duration::from_secs(1)));
                    let mut buf = String::new();
                    if (&stream).take(8192).read_to_string(&mut buf).is_ok()
                        && !buf.is_empty()
                    {
                        let _ = play_sound(&buf);
                    }
                });
            }
            Err(ref e) if e.kind() == io::ErrorKind::WouldBlock => {
                std::thread::sleep(Duration::from_millis(10));
            }
            Err(_) => {
                std::thread::sleep(Duration::from_millis(10));
            }
        }
    }

    // Cleanup on exit
    let _ = fs::remove_file(SOCKET_PATH);
    let _ = fs::remove_file(PID_PATH);
}

fn cleanup_stale_daemon() {
    if let Ok(pid_str) = fs::read_to_string(PID_PATH) {
        if let Ok(pid) = pid_str.trim().parse::<i32>() {
            // Check if process is still alive
            let alive = unsafe { libc::kill(pid, 0) == 0 };
            if alive {
                return; // daemon is running, don't touch anything
            }
        }
    }
    // Stale files — clean up
    let _ = fs::remove_file(SOCKET_PATH);
    let _ = fs::remove_file(PID_PATH);
}

extern "C" fn handle_signal(_sig: libc::c_int) {
    RUNNING.store(false, Ordering::Relaxed);
}

// ---------------------------------------------------------------------------
// Stop mode (--stop) — send SIGTERM to running daemon
// ---------------------------------------------------------------------------

fn stop_daemon() {
    let pid_str = match fs::read_to_string(PID_PATH) {
        Ok(s) => s,
        Err(_) => {
            eprintln!("No daemon running (no PID file)");
            return;
        }
    };

    let pid: i32 = match pid_str.trim().parse() {
        Ok(p) => p,
        Err(_) => {
            eprintln!("Invalid PID file");
            let _ = fs::remove_file(PID_PATH);
            let _ = fs::remove_file(SOCKET_PATH);
            return;
        }
    };

    unsafe {
        libc::kill(pid, libc::SIGTERM);
    }

    // Wait up to 2 seconds for clean shutdown
    for _ in 0..20 {
        std::thread::sleep(Duration::from_millis(100));
        if fs::metadata(PID_PATH).is_err() {
            return; // daemon cleaned up
        }
    }

    // Daemon didn't clean up — force cleanup
    let _ = fs::remove_file(SOCKET_PATH);
    let _ = fs::remove_file(PID_PATH);
}

// ---------------------------------------------------------------------------
// Sound playback — reused by both daemon and fork fallback
// ---------------------------------------------------------------------------

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

    fs::create_dir_all(STATE_DIR).ok()?;

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

    let last_file = format!("{}/last_{}", STATE_DIR, category);
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

    let player_cache = format!("{}/player", STATE_DIR);
    let player = match fs::read_to_string(&player_cache) {
        Ok(cached) => {
            let cached = cached.trim().to_string();
            if !cached.is_empty() {
                // Trust the cache — the player binary doesn't vanish mid-session.
                // The old code called `which` on every event (~3-5ms per fork+exec).
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

use chrono::Local;
// used for colored strings in terminal
use colored::*;
use std::collections::HashMap;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::time::timeout;

// ───────────────────────────────── constants ────────────────────────────────
const VERSION: &str = "0.9.7";
const TICKET_MESSAGE_LENGTH: usize = 772;
const PACKET_DELAY_MS: u64 = 250;
const TCP_TIMEOUT_CHECK_MS: u64 = 10_000;
const TCP_TIMEOUT_CONNECTED_MS: u64 = 31_000;
const RCV_BUF_SIZE: usize = 4096;

const TICKET_FIELDS: [usize; 49] = [
    4, 5, 30, 30, 20, 10, 16, 5, 20, 30, 2, 1, 17, 5, 10, 10, 5, 5, 5, 1, 16, 7, 1, 2, 10, 5, 40, 40, 10,
    10, 10, 10, 1, 2, 2, 2, 30, 5, 10, 1, 17, 30, 5, 5, 5, 5, 5, 6, 6,
];
const FIELDS_NAMES: [&str; 49] = [
    "TicketLabel",
    "TicketVersion",
    "CalledNumber",
    "ChargedNumber",
    "ChargedUserName",
    "ChargedCostCenter",
    "ChargedCompany",
    "ChargedPartyNode",
    "Subaddress",
    "CallingNumber",
    "CallType",
    "CostType",
    "EndDateTime",
    "ChargeUnits",
    "CostInfo",
    "Duration",
    "TrunkIdentity",
    "TrunkGroupIdentity",
    "TrunkNode",
    "PersonalOrBusiness",
    "AccessCode",
    "SpecificChargeInfo",
    "BearerCapability",
    "HighLevelComp",
    "DataVolume",
    "UserToUserVolume",
    "ExternalFacilities",
    "InternalFacilities",
    "CallReference",
    "SegmentsRate1",
    "SegmentsRate2",
    "SegmentsRate3",
    "ComType",
    "X25IncomingFlowRate",
    "X25OutgoingFlowRate",
    "Carrier",
    "InitialDialledNumber",
    "WaitingDuration",
    "EffectiveCallDuration",
    "RedirectedCallIndicator",
    "StartDateTime",
    "ActingExtensionNumber",
    "CalledNumberNode",
    "CallingNumberNode",
    "InitialDialledNumberNode",
    "ActingExtensionNumberNode",
    "TransitTrunkGroupIdentity",
    "NodeTimeOffset",
    "TimeDlt",
];
const CDR_FIELDS_LENGTH: [usize; 9] = [9, 20, 4, 11, 9, 9, 9, 5, 20];
const EA_CALL_TYPES: [&str; 16] = [
    "OC", "OCP", "PN", "LN", "IC", "ICP", "UN", "PO", "POP", "IP", "PIP", "PPO", "PPI", "PIC", "LL", "LT",
];

// protocol marks
const INIT_MESSAGE: [u8; 3] = [0x00, 0x01, 0x53];
const START_MESSAGE: [u8; 4] = [0x00, 0x02, 0x00, 0x00];
const FULL_TEST_REPLY: [u8; 10] = [0x00, 0x08, 0x54, 0x45, 0x53, 0x54, 0x5F, 0x52, 0x53, 0x50]; // 00-08 + TEST_RSP
const TICKET_READY_MARK: [u8; 2] = [0x03, 0x04];
const TICKET_MARK: [u8; 2] = [0x01, 0x00];
const TEST_MARK: [u8; 2] = [0x00, 0x08];
const EMPTY_TICKET: [u8; 4] = [0x01, 0x00, 0x01, 0x00];
const CDR_TICKET: [u8; 4] = [0x01, 0x00, 0x02, 0x00];
const MAO_TICKET: [u8; 4] = [0x01, 0x00, 0x06, 0x00];
const VOIP_TICKET: [u8; 4] = [0x01, 0x00, 0x07, 0x00];
const START_MSG: [u8; 2] = [0x00, 0x01];
const MAIN_ROLE: u8 = 0x50;

// exit codes
const EA_ERROR_HOST: i32 = 1;
const EA_ERROR_PORT: i32 = 2;
const EA_ERROR_BYTES: i32 = 3;
const EA_ERROR_NOT_MAIN: i32 = 4;
const EA_SCRIPT_RUNNING: i32 = 5;
const EA_USER_CTRL_C: i32 = 6;
const EA_WRONG_DATA: i32 = 7;
const EA_CONNECTION_CLOSED: i32 = 8;

#[derive(Debug, Clone)]
struct Config {
    cpu1: String,
    cpu2: String,
    port: u16,
    working_dir: PathBuf,
    logging: bool,
    debugging: bool,
    cdr_print: bool,
    cdr_beep: bool,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            cpu1: "192.168.92.55".into(),
            cpu2: "".into(),
            port: 2533,
            working_dir: std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")),
            logging: false,
            debugging: true,
            cdr_print: true,
            cdr_beep: false,
        }
    }
}

// ───────────────────────────────── helpers ─────────────────────────────────
fn hex_dash(bytes: &[u8]) -> String {
    bytes
        .iter()
        .map(|b| format!("{:02X}", b))
        .collect::<Vec<_>>()
        .join("-")
}
fn hex_dump(bytes: &[u8]) -> String {
    let mut s = String::new();
    for (i, chunk) in bytes.chunks(16).enumerate() {
        s.push_str(&format!("{:04X}: ", i * 16));
        for b in chunk {
            s.push_str(&format!("{:02X} ", b));
        }
        s.push('\n');
    }
    s
}
fn field_index(name: &str) -> usize {
    FIELDS_NAMES.iter().position(|&n| n == name).unwrap()
}
fn debug_log(enabled: bool, msg: &str) {
    if enabled {
        eprintln!("{}", format!("[DEBUG] {}", msg).dimmed());
    }
}
fn log_to_file(path: &Path, line: &str) {
    let mut f = OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .unwrap();
    let _ = writeln!(f, "{}", line);
}
fn clear_lock_file(p: &Path) {
    let _ = fs::remove_file(p);
}
fn get_ini_content(path: &Path) -> HashMap<String, String> {
    let mut map = HashMap::new();
    if let Ok(txt) = fs::read_to_string(path) {
        for line in txt.lines() {
            let line = line.trim();
            if line.is_empty() || line.starts_with(';') || line.starts_with('#') || line.starts_with('[') {
                continue;
            }
            if let Some(eq) = line.find('=') {
                let k = line[..eq].trim().to_string();
                let v = line[eq + 1..].trim().to_string();
                map.insert(k, v);
            }
        }
    }
    map
}
fn load_config(exe_dir: &Path) -> Config {
    let ini_path = exe_dir.join("eacc.ini");
    let mut cfg = Config::default();
    cfg.working_dir = exe_dir.to_path_buf();

    if ini_path.exists() {
        println!("Loading parameters from {}", ini_path.display());
        let m = get_ini_content(&ini_path);
        if let Some(v) = m.get("CPU1") { cfg.cpu1 = v.clone(); }
        if let Some(v) = m.get("CPU2") { cfg.cpu2 = v.clone(); }
        if let Some(v) = m.get("Port") { if let Ok(p) = v.parse() { cfg.port = p; } }
        if let Some(v) = m.get("WorkingDir") { if !v.is_empty() { cfg.working_dir = PathBuf::from(v); } }
        if let Some(v) = m.get("Logging") { cfg.logging = v == "1"; }
        if let Some(v) = m.get("Debugging") { cfg.debugging = v == "1"; }
        if let Some(v) = m.get("CDRPrint") { cfg.cdr_print = v == "1"; }
        if let Some(v) = m.get("CDRBeep") { cfg.cdr_beep = v == "1"; }
    } else {
        println!("File not found: {} , loading default parameters.", ini_path.display());
    }
    // ensure working dir
    let _ = fs::create_dir_all(&cfg.working_dir);
    cfg
}

async fn test_connection_oxe(cfg: &Config) -> Result<(String, String), i32> {
    // try cpu1 then cpu2 (if configured) via TCP connect to port
    let mut main = cfg.cpu1.clone();
    let mut stby = cfg.cpu2.clone();

    async fn can_connect(host: &str, port: u16) -> bool {
        let addr = format!("{}:{}", host, port);
        timeout(Duration::from_millis(TCP_TIMEOUT_CHECK_MS), TcpStream::connect(&addr))
            .await
            .is_ok()
    }

    print!("Host {} reachable : ", cfg.cpu1);
    std::io::stdout().flush().unwrap();
    if can_connect(&cfg.cpu1, cfg.port).await {
        println!("{}", "OK".green());
    } else {
        println!("{}", "NOK".red());
        if !cfg.cpu2.is_empty() {
            debug_log(cfg.debugging, "Checking 2nd CPU address");
            print!("Host {} reachable : ", cfg.cpu2);
            std::io::stdout().flush().unwrap();
            if can_connect(&cfg.cpu2, cfg.port).await {
                println!("{}", "OK".green());
                main = cfg.cpu2.clone();
                stby = cfg.cpu1.clone();
            } else {
                println!("{}", "NOK".red());
                println!("No connection to the host. Exiting.");
                return Err(EA_ERROR_HOST);
            }
        } else {
            println!("No connection to the host. Exiting.");
            return Err(EA_ERROR_HOST);
        }
    }
    // verify port open on main
    print!("Connection to {} on port {} : ", main, cfg.port);
    std::io::stdout().flush().unwrap();
    if can_connect(&main, cfg.port).await {
        println!("{}", "OK".green());
    } else {
        println!("{}", "NOK".red());
        debug_log(cfg.debugging, &format!("Ethernet Account port {} closed on {}, exiting", cfg.port, main));
        return Err(EA_ERROR_PORT);
    }
    Ok((main, stby))
}

fn process_one_ticket(
    process_ticket: &str,
    cdr_counter: &mut u64,
    cdr_file: &Path,
    print_out: bool,
    debugging: bool,
    mao_counter: u64,
    voip_counter: u64,
) {
    // split by TICKET_FIELDS lengths
    let mut fields: Vec<String> = Vec::with_capacity(TICKET_FIELDS.len());
    let mut pos = 0usize;
    for &len in &TICKET_FIELDS {
        if pos + len <= process_ticket.len() {
            fields.push(process_ticket[pos..pos + len].to_string());
            pos += len;
        } else if pos < process_ticket.len() {
            fields.push(process_ticket[pos..].to_string());
            pos = process_ticket.len();
        } else {
            fields.push(String::new());
        }
    }
    *cdr_counter += 1;
    debug_log(debugging, &format!("Tickets Processed {}, {}, {}", cdr_counter, mao_counter, voip_counter));

    let start = field_index("CalledNumber");
    for i in start..fields.len() {
        fields[i] = fields[i].trim().to_string();
    }

    if print_out {
        let charged = fields[field_index("ChargedNumber")].clone();
        let called = fields[field_index("CalledNumber")].clone();
        let ct_raw = fields[field_index("CallType")].trim().to_string();
        let ct_idx: usize = ct_raw.parse().unwrap_or(6);
        let ct_str = EA_CALL_TYPES.get(ct_idx).unwrap_or(&"UN").to_string();

        // StartDateTime = "yyyyMMdd HH:mm:ss" -> date part
        let sdt = fields[field_index("StartDateTime")].clone();
        let date_part = sdt.split_whitespace().next().unwrap_or("");
        let date_fmt = if date_part.len() == 8 {
            // parse yyyyMMdd
            if let Ok(d) = chrono::NaiveDate::parse_from_str(date_part, "%Y%m%d") {
                d.format("%m/%d/%Y").to_string()
            } else {
                date_part.to_string()
            }
        } else {
            date_part.to_string()
        };
        let edt = fields[field_index("EndDateTime")].clone();
        let time_part = edt.split_whitespace().nth(1).unwrap_or("").to_string();

        let dur_secs: u64 = fields[field_index("Duration")].trim().parse().unwrap_or(0);
        let wait_secs: u64 = fields[field_index("WaitingDuration")].trim().parse().unwrap_or(0);
        let dur_str = {
            let d = Duration::from_secs(dur_secs);
            format!("{:02}:{:02}:{:02}", d.as_secs() / 3600, (d.as_secs() % 3600) / 60, d.as_secs() % 60)
        };
        let wait_str = {
            let d = Duration::from_secs(wait_secs);
            format!("{:02}:{:02}:{:02}", d.as_secs() / 3600, (d.as_secs() % 3600) / 60, d.as_secs() % 60)
        };
        let tg = fields[field_index("TrunkGroupIdentity")].clone();
        let init = fields[field_index("InitialDialledNumber")].clone();

        let cols = [
            charged, called, ct_str, date_fmt, time_part, dur_str, wait_str, tg, init,
        ];
        // print table row: │ with widths CDR_FIELDS_LENGTH
        let mut row = String::new();
        row.push('│');
        for (i, col) in cols.iter().enumerate() {
            let w = CDR_FIELDS_LENGTH[i];
            // right align within width
            row.push_str(&format!("{:>width$}│", col, width = w));
        }
        println!("{}", row);
    }

    // write to .cdr file: fields[2..] tab-joined
    if fields.len() > 2 {
        let line = fields[2..].join("\t");
        let mut f = OpenOptions::new().create(true).append(true).open(cdr_file).unwrap();
        let _ = writeln!(f, "{}", line);
    }
}

// ─────────────────────────────────── main ───────────────────────────────────
#[tokio::main]
async fn main() -> std::io::Result<()> {
    let banner = format!(
        "Yet Another Ethernet Accounting Ticket Loader Script by Jeepers-Gitters@github.com. v.{} ©2026",
        VERSION
    );
    println!("{}", banner.black().on_yellow());
    println!();

    let exe_dir = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|x| x.to_path_buf()))
        .unwrap_or_else(|| std::env::current_dir().unwrap());
    println!("Running in {}", exe_dir.display());

    let cfg = load_config(&exe_dir);
    if cfg.debugging {
        println!("Running with Debugging enabled");
    }
    if !cfg.cpu2.is_empty() {
        println!("Configured {} as Main CPU and {} as StandBy CPU", cfg.cpu1, cfg.cpu2);
    } else {
        println!("Configured {} as Main CPU and no StandBy CPU", cfg.cpu1);
    }
    for (k, v) in [
        ("CPU1", cfg.cpu1.clone()),
        ("CPU2", cfg.cpu2.clone()),
        ("Port", cfg.port.to_string()),
        ("WorkingDir", cfg.working_dir.display().to_string()),
        ("Logging", (cfg.logging as u8).to_string()),
        ("Debugging", (cfg.debugging as u8).to_string()),
        ("CDRPrint", (cfg.cdr_print as u8).to_string()),
        ("CDRBeep", (cfg.cdr_beep as u8).to_string()),
    ] {
        debug_log(cfg.debugging, &format!("{} : {}", k, v));
    }

    let log_file = cfg.working_dir.join("log.txt");
    let lock_file = cfg.working_dir.join(".lock");

    if lock_file.exists() {
        eprintln!("{}", format!("Found {}. The script is already running or crashed. Check for running script or delete {} file. Exiting.", lock_file.display(), lock_file.display()).red());
        std::process::exit(EA_SCRIPT_RUNNING);
    }
    // create lock
    fs::write(&lock_file, "")?;
    // ensure removal on exit
    let lock_clone = lock_file.clone();
    let ctrlc_flag = Arc::new(AtomicBool::new(false));
    let flag2 = ctrlc_flag.clone();
    tokio::spawn(async move {
        let _ = tokio::signal::ctrl_c().await;
        flag2.store(true, Ordering::SeqCst);
    });

    // table decorations
    let top = format!(
        "┍---------┬--------------------┬----┬-----------┬---------┬---------┬---------┬-----┬--------------------┑"
    );
    let bottom = format!(
        "┡---------┼--------------------┼----┼-----------┼---------┼---------┼---------┼-----┼--------------------┥"
    );
    let header = {
        let titles = ["Extn ", "External", "Type", "StartDate", "StartTime", "Duration", "Waiting", "TG", "InitialNumber"];
        let mut r = String::from("│");
        for (i, t) in titles.iter().enumerate() {
            r.push_str(&format!("{:>width$}│", t, width = CDR_FIELDS_LENGTH[i]));
        }
        r
    };

    let spatial = !cfg.cpu2.is_empty();
    let mut start_counter: u64 = 0;
    let mut global_cdr: u64 = 0;
    let mut mao_counter: u64 = 0;
    let mut voip_counter: u64 = 0;

    // outer do-while switchover loop
    loop {
        debug_log(cfg.debugging, &format!("Enter main loop {}", start_counter));

        let (mut oxe_main, mut oxe_stby) = match test_connection_oxe(&cfg).await {
            Ok(v) => v,
            Err(code) => {
                clear_lock_file(&lock_file);
                std::process::exit(code);
            }
        };

        // connect
        let addr = format!("{}:{}", oxe_main, cfg.port);
        let mut stream = match timeout(Duration::from_millis(TCP_TIMEOUT_CHECK_MS), TcpStream::connect(&addr)).await {
            Ok(Ok(s)) => s,
            _ => {
                eprintln!("Failed to connect to {}", addr);
                clear_lock_file(&lock_file);
                std::process::exit(EA_ERROR_HOST);
            }
        };

        // log start
        log_to_file(&log_file, &format!("{} Start script {}", Local::now().format("%Y/%m/%d %H:%M:%S "), start_counter));

        // preamble: send INIT
        stream.write_all(&INIT_MESSAGE).await?;
        let mut rcv = vec![0u8; RCV_BUF_SIZE];
        let n = match timeout(Duration::from_millis(TCP_TIMEOUT_CONNECTED_MS), stream.read(&mut rcv)).await {
            Ok(Ok(n)) => n,
            _ => 0,
        };
        if cfg.logging && n > 0 {
            log_to_file(&log_file, &hex_dump(&rcv[..n]));
        }
        debug_log(cfg.debugging, &format!("Received {} bytes : {}", n, hex_dash(&rcv[..n])));

        // handle preamble response
        let mut preamble_ok = false;
        match n {
            2 => {
                if rcv[..n] == START_MSG {
                    debug_log(cfg.debugging, "Start sequence reply received, waiting for role...");
                    let n2 = match timeout(Duration::from_millis(TCP_TIMEOUT_CONNECTED_MS), stream.read(&mut rcv)).await {
                        Ok(Ok(v)) => v,
                        _ => 0,
                    };
                    if cfg.logging && n2 > 0 {
                        log_to_file(&log_file, &hex_dump(&rcv[..n2]));
                    }
                    if n2 == 1 && rcv[0] == MAIN_ROLE {
                        debug_log(cfg.debugging, "Role is Main. Link Established");
                        preamble_ok = true;
                    } else {
                        eprintln!("{}", format!("Role is not Main {} ", hex_dash(&rcv[..n2])).red());
                        clear_lock_file(&lock_file);
                        std::process::exit(EA_ERROR_NOT_MAIN);
                    }
                } else {
                    debug_log(cfg.debugging, "Possibly not OXE. Check CPU IP-address setting.");
                }
            }
            3 => {
                if rcv[0..2] == START_MSG && rcv[2] == MAIN_ROLE {
                    println!("{}", "Start sequence reply received, waiting for role...".yellow());
                    println!("{}", "Role is Main. Link Established\n".yellow());
                    preamble_ok = true;
                }
            }
            5 => {
                if rcv[0..2] == START_MSG && rcv[2] == MAIN_ROLE && rcv[3..5] == TICKET_READY_MARK {
                    println!("{}", "Start sequence reply received, waiting for role...".yellow());
                    println!("{}", "Role is Main. Link Established\n".yellow());
                    preamble_ok = true;
                }
            }
            _ => {
                eprintln!("Too many bytes received. Wrong connection possible.");
                clear_lock_file(&lock_file);
                std::process::exit(EA_ERROR_BYTES);
            }
        }
        if preamble_ok {
            println!("{}", top);
            println!("{}", header);
            println!("{}", bottom);
        }

        let cdr_file = cfg.working_dir.join(format!("{}.cdr", oxe_main));
        let mao_file = cfg.working_dir.join(format!("{}.mao", oxe_main));
        let voip_file = cfg.working_dir.join(format!("{}.voip", oxe_main));

        // send START_MESSAGE
        stream.write_all(&START_MESSAGE).await?;
        let keep_alive_start = Instant::now();
        let mut msg_counter: u64 = 1;

        // state for buffer processing
        let mut ticket_truncated = false;
        let mut trunc_part: Vec<u8> = Vec::new();
        let mut ticket_ready = false;
        let mut keep_alive_req = false;

        // read loop
        loop {
            if ctrlc_flag.load(Ordering::SeqCst) {
                println!("\nCTRL-C pressed. Stopping script...");
                log_to_file(&log_file, &format!("{} Stop script", Local::now().format("%Y/%m/%d %H:%M:%S")));
                clear_lock_file(&lock_file);
                std::process::exit(EA_USER_CTRL_C);
            }

            let mut buf = vec![0u8; RCV_BUF_SIZE];
            let read_res = timeout(Duration::from_millis(TCP_TIMEOUT_CONNECTED_MS), stream.read(&mut buf)).await;
            let n = match read_res {
                Ok(Ok(0)) => {
                    // connection closed
                    break;
                }
                Ok(Ok(v)) => v,
                Ok(Err(_)) | Err(_) => {
                    // timeout -> continue to check keepalive, but break if no data long time
                    // treat as disconnect
                    break;
                }
            };
            msg_counter += 1;
            let data = &buf[..n];
            if cfg.logging {
                log_to_file(&log_file, &hex_dump(data));
            }

            // small packets handling
            if n == 1 || n == 2 || n == 3 || n == 5 || n == 8 {
                let elapsed = format!("{:02}.{:02}:{:02}:{:02}", keep_alive_start.elapsed().as_secs()/86400, (keep_alive_start.elapsed().as_secs()%86400)/3600, (keep_alive_start.elapsed().as_secs()%3600)/60, keep_alive_start.elapsed().as_secs()%60);
                match n {
                    1 => debug_log(cfg.debugging, &format!("{} Unknown command. Check logs.", elapsed)),
                    2 => {
                        if data == TICKET_READY_MARK {
                            debug_log(cfg.debugging, "Ticket Ready.");
                            ticket_ready = true;
                        } else if data == TEST_MARK {
                            debug_log(cfg.debugging, "Test Command.");
                            keep_alive_req = true;
                        }
                    }
                    8 => {
                        if data == b"TEST_REQ" {
                            debug_log(cfg.debugging, "TEST_REQ received");
                            if keep_alive_req || true {
                                tokio::time::sleep(Duration::from_millis(PACKET_DELAY_MS)).await;
                                let _ = stream.write_all(&FULL_TEST_REPLY).await;
                                debug_log(cfg.debugging, " TEST_REP sent");
                                keep_alive_req = false;
                            }
                        }
                    }
                    _ => {}
                }
                // also handle generic TEST_REQ detection for 8 bytes
                if n == 8 && data == b"TEST_REQ" {
                    tokio::time::sleep(Duration::from_millis(PACKET_DELAY_MS)).await;
                    let _ = stream.write_all(&FULL_TEST_REPLY).await;
                    debug_log(cfg.debugging, " TEST_REP sent (direct)");
                }
                debug_log(cfg.debugging, &format!("{} Received {} bytes.", elapsed, n));
                continue;
            }

            // default: buffer processing (large packet)
            let mut buffer_buf: Vec<u8> = data.to_vec();
            debug_log(cfg.debugging, &format!("Read Buffer: {}", buffer_buf.len()));
            let mut start_ptr: usize = 0;

            if keep_alive_req {
                tokio::time::sleep(Duration::from_millis(PACKET_DELAY_MS)).await;
                let _ = stream.write_all(&FULL_TEST_REPLY).await;
                debug_log(cfg.debugging, " TEST_REP sent");
                keep_alive_req = false;
                start_ptr += 8; // EATestRequest length
                if start_ptr >= buffer_buf.len() {
                    continue;
                }
            }
            if ticket_truncated {
                let mut new_buf = trunc_part.clone();
                new_buf.extend_from_slice(&buffer_buf);
                buffer_buf = new_buf;
                debug_log(cfg.debugging, "Appended data from previous packets.");
                ticket_truncated = false;
                ticket_ready = true;
            }

            let mut iteration = 0usize;
            while start_ptr < buffer_buf.len() {
                iteration += 1;
                if buffer_buf.len() - start_ptr < 2 {
                    break;
                }
                let mark = &buffer_buf[start_ptr..start_ptr + 2];
                if mark == TICKET_READY_MARK {
                    ticket_ready = true;
                    start_ptr += 2;
                } else if mark == TICKET_MARK {
                    debug_log(cfg.debugging, &format!("{} Start buffer processing..", keep_alive_start.elapsed().as_secs()));
                } else if mark == TEST_MARK {
                    debug_log(cfg.debugging, &format!("{} Test Command.", keep_alive_start.elapsed().as_secs()));
                    // reply immediately
                    tokio::time::sleep(Duration::from_millis(PACKET_DELAY_MS)).await;
                    let _ = stream.write_all(&FULL_TEST_REPLY).await;
                    debug_log(cfg.debugging, &format!("{} TEST_REP sent", keep_alive_start.elapsed().as_secs()));
                    start_ptr += 10; // 00-08 + 8 bytes TEST_REQ
                    continue;
                } else {
                    eprintln!("{}", format!("Wrong data...Check logs. {} ", hex_dash(mark)).red());
                    clear_lock_file(&lock_file);
                    std::process::exit(EA_WRONG_DATA);
                }

                if start_ptr + TICKET_MESSAGE_LENGTH > buffer_buf.len() {
                    let left = buffer_buf.len() - start_ptr;
                    debug_log(cfg.debugging, &format!(" BufferLoop:{} Pointer:{} Left:{} Length:{} ", iteration, start_ptr, left, buffer_buf.len()));
                    if ticket_ready {
                        debug_log(cfg.debugging, &format!("Bytes left:{} . Next ticket is truncated.", left));
                        ticket_truncated = true;
                        trunc_part = buffer_buf[start_ptr..].to_vec();
                    }
                    break;
                }

                let ticket_data = &buffer_buf[start_ptr..start_ptr + TICKET_MESSAGE_LENGTH];
                let process_ticket = String::from_utf8_lossy(ticket_data).to_string();
                let left = buffer_buf.len() - start_ptr;
                debug_log(cfg.debugging, &format!(" BufferLoop:{} Pointer:{} Left:{} Length:{} ", iteration, start_ptr, left, buffer_buf.len()));

                if ticket_ready {
                    let flag = &ticket_data[0..4];
                    match flag {
                        _ if flag == EMPTY_TICKET => {
                            ticket_ready = false;
                            start_ptr += TICKET_MESSAGE_LENGTH;
                        }
                        _ if flag == CDR_TICKET => {
                            if !ticket_truncated {
                                if cfg.cdr_beep {
                                    print!("\x07");
                                    let _ = std::io::stdout().flush();
                                }
                                process_one_ticket(
                                    &process_ticket,
                                    &mut global_cdr,
                                    &cdr_file,
                                    cfg.cdr_print,
                                    cfg.debugging,
                                    mao_counter,
                                    voip_counter,
                                );
                                ticket_ready = false;
                            }
                            start_ptr += TICKET_MESSAGE_LENGTH;
                        }
                        _ if flag == MAO_TICKET => {
                            // MAO: substring(4, indexOf(0x0A)-4) replace "=" with "\t"
                            if let Some(pos) = ticket_data.iter().position(|&b| b == 0x0A) {
                                if pos > 4 {
                                    let mao_raw = String::from_utf8_lossy(&ticket_data[4..pos]).to_string();
                                    let mao_line = mao_raw.replace('=', "\t");
                                    // append to file
                                    let mut f = OpenOptions::new().create(true).append(true).open(&mao_file).unwrap();
                                    let _ = writeln!(f, "{}", mao_line);
                                    if cfg.cdr_print {
                                        for part in mao_line.split(';') {
                                            if part.is_empty() { continue; }
                                            let fields: Vec<&str> = part.split('\t').collect();
                                            if fields.len() >= 2 {
                                                println!("{} {} : {}", fields[0], fields[1], fields.len());
                                            }
                                        }
                                    }
                                }
                            }
                            mao_counter += 1;
                            ticket_ready = false;
                            start_ptr += TICKET_MESSAGE_LENGTH;
                        }
                        _ if flag == VOIP_TICKET => {
                            let mut f = OpenOptions::new().create(true).append(true).open(&voip_file).unwrap();
                            let _ = f.write_all(&ticket_data[4..]);
                            voip_counter += 1;
                            ticket_ready = false;
                            start_ptr += TICKET_MESSAGE_LENGTH;
                        }
                        _ if flag[0..2] == TEST_MARK && flag[2..4] == [0x54, 0x45] => {
                            // 00-08-54-45 -> TEST_REQ in buffer
                            println!("{}", "Test_REQ received in buffer -1.".cyan());
                            ticket_truncated = false;
                            ticket_ready = false;
                            start_ptr = buffer_buf.len();
                        }
                        _ => {
                            // NOP or unknown
                            if flag == [0x00, 0x00, 0x00, 0x00] {
                                debug_log(cfg.debugging, "Buffer processed. Skipping..");
                                start_ptr += TICKET_MESSAGE_LENGTH;
                            } else {
                                eprintln!("{}", format!("Unknown ticket type. Check {}. {:02X?}", log_file.display(), flag).red());
                                start_ptr += TICKET_MESSAGE_LENGTH;
                            }
                        }
                    }
                } else {
                    // not ready, just advance?
                    start_ptr += TICKET_MESSAGE_LENGTH;
                }
            } // while buffer
        } // read loop

        // connection closed handling
        println!("Connection closed from server. Exiting");
        // try switchover
        if spatial {
            debug_log(cfg.debugging, &format!("Possible CPU switch over from {} to {}", oxe_main, oxe_stby));
            // check standby reachable
            let stby_addr = format!("{}:{}", oxe_stby, cfg.port);
            if timeout(Duration::from_millis(TCP_TIMEOUT_CHECK_MS), TcpStream::connect(&stby_addr)).await.is_ok() {
                debug_log(cfg.debugging, &format!("New Main CPU {}", oxe_stby));
                debug_log(cfg.debugging, "Restarting script for the new Main CPU");
                // swap? next loop will test again, but we can set oxe_main = stby
            }
        }
        tokio::time::sleep(Duration::from_secs(10)).await;
        start_counter += 1;

        // original: while (SpatialConfiguration || CPUSwitchover) -> always true, infinite retry
        // break only if not spatial and no switchover? We keep infinite.
        // For non-spatial, we still retry once then exit? Original loops while true.
        // To avoid infinite tight loop, continue.
        if !spatial {
            // if no standby, exit after disconnect
            debug_log(cfg.debugging, &format!("Disconnect from {}. Uptime {}  Tickets received: {}, {}, {}", oxe_main, keep_alive_start.elapsed().as_secs(), global_cdr, mao_counter, voip_counter));
            break;
        }
    }

    clear_lock_file(&lock_clone);
    println!("Done.");
    // remove lock guard
    let _ = fs::remove_file(&lock_file);
    Ok(())
}

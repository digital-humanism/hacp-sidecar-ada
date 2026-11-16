//! hacp-rs-core-runner — Protocol v1 Core direct-conformance runner.
//!
//! This additive runner selects the Core-compatible evaluation path.
//! The existing hacp-rs-runner retains Authorization-v2 semantics.

use hacp_rs::runner;

/// Embedded conformance test public key (harness/keys/KEYS.md). TEST ONLY.
const TEST_PUBKEY_HEX: &str =
    "9d17f1bbcc0845865e670f526413fb7a510380798fe300b6c98e28f3a3b0fdb3";

fn main() {
    if let Err(e) = runner::run_core(TEST_PUBKEY_HEX) {
        eprintln!("{{\"error\":\"RUNNER_ERROR\",\"message\":\"{}\"}}", e);
        std::process::exit(1);
    }
}

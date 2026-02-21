fn main() {
    // Tell cargo to recompile when these compile-time env vars change.
    // Without this, option_env!() values get cached and won't update.
    println!("cargo:rerun-if-env-changed=SUPABASE_URL");
    println!("cargo:rerun-if-env-changed=SUPABASE_PUBLISHABLE_KEY");
    println!("cargo:rerun-if-env-changed=UNBOUND_WEB_APP_URL");
    println!("cargo:rerun-if-env-changed=UNBOUND_PRESENCE_DO_HEARTBEAT_URL");
    println!("cargo:rerun-if-env-changed=UNBOUND_PRESENCE_DO_TOKEN");
    println!("cargo:rerun-if-env-changed=UNBOUND_PRESENCE_DO_TTL_MS");
}

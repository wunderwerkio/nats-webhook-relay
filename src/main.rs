use core::panic;
use std::env;

use log::info;
use nats::NatsClient;
use url::Url;
use webhook::WebhookActorHandle;

mod nats;
mod webhook;

/// Get env var by `key`.
/// Panics if not found.
fn get_env_var(key: &str) -> String {
    env::var(key).unwrap_or_else(|_| {
        panic!("Required env var {key} not set!");
    })
}

/// Program entrypoint.
#[tokio::main]
async fn main() {
    // Load env vars.
    _ = dotenvy::from_filename(".env.local");
    _ = dotenvy::dotenv();

    // Read env vars.
    let webhook_destination = get_env_var("WEBHOOK_DESTINATION");
    let nats_address = get_env_var("NATS_ADDRESS");
    let nats_user = get_env_var("NATS_USER");
    let nats_pass = get_env_var("NATS_PASS");
    let nats_subject_prefix = get_env_var("NATS_SUBJECT_PREFIX");
    let nats_relayed_subject_prefix = get_env_var("NATS_RELAYED_SUBJECT_PREFIX");

    // Validate webhook destination.
    _ = Url::parse(&webhook_destination).unwrap_or_else(|err| {
        panic!("The value in WEBHOOK_DESTINATION is not a valid URL: {err}");
    });

    // Setup logger.
    // Disable timestamp logging.
    env_logger::builder().format_timestamp(None).init();

    info!(target: "app", "Starting {} {}", env!("CARGO_PKG_NAME"), env!("CARGO_PKG_VERSION"));
    info!(target: "app", "NATS messages at {}.> will be relayed to {} and republished under the {}.> subject", nats_subject_prefix, webhook_destination, nats_relayed_subject_prefix);

    // Start app.
    let webhook_handle = WebhookActorHandle::new(webhook_destination.to_string());
    let nats = NatsClient::connect(
        &nats_address,
        &nats_user,
        &nats_pass,
        nats_subject_prefix,
        nats_relayed_subject_prefix,
        webhook_handle,
    )
    .await;

    // Subscribe to messages indefinetly.
    nats.subscribe().await;
}

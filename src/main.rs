use core::panic;
use std::env;

use log::info;
use nats::NatsClient;
use webhook::WebhookActorHandle;

mod nats;
mod webhook;

fn get_env_var(key: &str) -> String {
    env::var(key).unwrap_or_else(|_| {
        panic!("Required env var {key} not set!");
    })
}

#[tokio::main]
async fn main() {
    // Load env vars.
    _ = dotenvy::from_filename(".env.local");
    _ = dotenvy::dotenv();

    // Read env vars.
    let webhook_destination = get_env_var("WEBHOOK_DESTINATION");
    let nats_host = get_env_var("NATS_HOST");
    let nats_user = get_env_var("NATS_USER");
    let nats_pass = get_env_var("NATS_PASS");

    // Setup logger.
    env_logger::builder()
        .format_timestamp(None)
        .init();

    info!(target: "app", "Starting nextjs-cache-relay {}", env!("CARGO_PKG_VERSION"));
    info!(target: "app", "NATS messages at cms.cache.> will be relayed to {} and republished under the nextjs.cache.> subject", webhook_destination);

    // Start app.
    let webhook_handle = WebhookActorHandle::new(webhook_destination.to_string());
    let nats = NatsClient::connect(&nats_host, &nats_user, &nats_pass, webhook_handle).await;

    nats.subscribe().await;
}

use anyhow::anyhow;
use log::{error, info};
use reqwest::Client;
use tokio::sync::{mpsc, oneshot};

enum ActorMessage {
    SendEventWebhook {
        payload: String,
        respond_to: oneshot::Sender<anyhow::Result<()>>,
    },
}

/// The actor struct.
struct WebhookActor {
    receiver: mpsc::Receiver<ActorMessage>,

    destination: String,
    client: Client,
}

impl WebhookActor {
    /// Create new WebhookActor.
    fn new(receiver: mpsc::Receiver<ActorMessage>, destination: String) -> Self {
        // Create the HTTP client.
        // Add support for compression and set a user agent.
        let client = Client::builder()
            .gzip(true)
            .brotli(true)
            .deflate(true)
            .user_agent(concat!(
                env!("CARGO_PKG_NAME"),
                "/",
                env!("CARGO_PKG_VERSION")
            ))
            .build()
            .unwrap();

        Self {
            receiver,

            client,
            destination,
        }
    }

    /// Send given `payload` as webhook.
    ///
    /// Payload is expected to be valid JSON.
    /// Request is sent via POST as `application/json`.
    ///
    /// Success status code is expected to be 200.
    pub async fn send_webhook(&self, payload: String) -> anyhow::Result<()> {
        let res = self
            .client
            .post(self.destination.clone())
            .body(payload)
            .header("Content-Type", "application/json")
            .send()
            .await?;

        let status = res.status();
        if status != 200 {
            error!(target: "app::webhook", "Could not send webhook: {}", status);

            return Err(anyhow!("Invalid status code: {}!", status));
        }

        info!(target: "app::webhook", "Relayed message via webhook to {}", self.destination);

        Ok(())
    }

    /// Handle actor messages.
    async fn handle_message(&mut self, msg: ActorMessage) {
        match msg {
            ActorMessage::SendEventWebhook {
                payload,
                respond_to,
            } => {
                let res = self.send_webhook(payload).await;
                _ = respond_to.send(res);
            }
        }
    }
}

/// Run the actor and listen for actor messages.
async fn run_actor(mut actor: WebhookActor) {
    while let Some(msg) = actor.receiver.recv().await {
        actor.handle_message(msg).await;
    }
}

/// The actor handle.
/// Can be used safely across thread boundaries.
/// Just clone the handle.
#[derive(Clone)]
pub struct WebhookActorHandle {
    sender: mpsc::Sender<ActorMessage>,
}

impl WebhookActorHandle {
    /// Create new webhook actor handle.
    pub fn new(destination: String) -> Self {
        let (sender, receiver) = mpsc::channel(8);
        let actor = WebhookActor::new(receiver, destination);

        // Spawn the single actor instance.
        tokio::spawn(run_actor(actor));

        Self { sender }
    }

    /// Send given `payload` as webhook.
    ///
    /// Payload is expected to be valid JSON.
    /// Request is sent via POST as `application/json`.
    ///
    /// Success status code is expected to be 200.
    pub async fn send_webhook(&self, payload: String) -> anyhow::Result<()> {
        let (tx, rx) = oneshot::channel();
        let msg = ActorMessage::SendEventWebhook {
            payload,
            respond_to: tx,
        };

        _ = self.sender.send(msg).await;
        rx.await?
    }
}

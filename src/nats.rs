use core::panic;
use futures_util::StreamExt;

use async_nats::{Client, ConnectOptions, Message};
use log::{debug, error, info};

use crate::webhook::WebhookActorHandle;

/// Struct to connect to NATS server
/// and handle messages.
pub struct NatsClient {
    client: Client,
    subject_prefix: String,
    relayed_subject_prefix: String,
    webhook_handle: WebhookActorHandle,
}

impl NatsClient {
    /// Connect to NATS server.
    /// Creates a new instance of NatsClient after
    /// successfully connecting to NATS.
    ///
    /// Panics on initial connection error.
    /// Lost connections are automatically reconnected (indefinetly.)
    pub async fn connect(
        address: &str,
        user: &str,
        pass: &str,
        subject_prefix: String,
        relayed_subject_prefix: String,
        webhook_handle: WebhookActorHandle,
    ) -> Self {
        info!(target: "app::nats", "Connecting to NATS at {}", address);

        // Create client with user + password.
        let client = ConnectOptions::with_user_and_password(user.to_owned(), pass.to_owned())
            // Log various events.
            .event_callback(|event| async move {
                match event {
                    async_nats::Event::Connected => {
                        info!(target: "app::nats", "Connected to NATS successfully");
                    }
                    async_nats::Event::Disconnected => {
                        error!(target: "app::nats", "Connection to NATS server lost");
                    }
                    async_nats::Event::ClientError(err) => {
                        error!(target: "app::nats", "NATS client error: {err}");
                    }
                    other => {
                        debug!(target: "app::nats", "Other event: {other}")
                    }
                }
            })
            // Connect to server.
            .connect(address)
            .await
            // Make sure connection is successful.
            .unwrap_or_else(|err| {
                panic!("Could not connect to NATS: {err}");
            });

        Self {
            client,
            subject_prefix,
            relayed_subject_prefix,
            webhook_handle,
        }
    }

    /// Republish a message with given body under the rewritten subject.
    /// Replaces the configured `subject_prefix` in the message subject with
    /// the `relayed_subject_prefix`.
    async fn republish_relayed_message(&self, subject: &str, body: String) {
        let sub = subject.replace(&self.subject_prefix, &self.relayed_subject_prefix);

        if let Err(err) = self.client.publish(sub.clone(), body.into()).await {
            error!(target: "app::nats", "Could not publish {sub}: {err}");
        }

        info!(target: "app::nats", "Relayed message via subject {sub} to NATS");
    }

    /// Handle incoming message from NATS server.
    async fn handle_message(&self, message: Message) {
        let sub = message.subject.to_string();
        info!(target: "app::nats", "Incoming message {sub}");

        // Parse message as UTF-8 string.
        let msg_str = match String::from_utf8(message.payload.into()) {
            Ok(v) => v,
            Err(err) => {
                error!(target: "app::nats", "Could not decode message payload: {err}");
                return;
            }
        };

        // Send received message via webhook to next.js.
        if let Err(_) = self.webhook_handle.send_webhook(msg_str.clone()).await {
            return;
        }

        // Re-publish the message on a new subject.
        // Only if the webhook was sent successfuly.
        self.republish_relayed_message(&message.subject, msg_str)
            .await
    }

    /// Subscribe to the subject and handle messages.
    /// This method is blocks.
    pub async fn subscribe(&self) {
        let subject = format!("{}.>", self.subject_prefix);

        let mut subscriber = self
            .client
            .subscribe(subject.clone())
            .await
            .unwrap_or_else(|err| {
                panic!("Could not subscribe to {subject} subject: {err}");
            });

        info!(target: "app::nats", "Subscribing to {subject}");

        // Wait for messages.
        while let Some(msg) = subscriber.next().await {
            self.handle_message(msg).await;
        }
    }
}

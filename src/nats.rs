use core::panic;
use futures_util::StreamExt;

use async_nats::{Client, ConnectOptions, Message};
use log::{debug, error, info};

use crate::webhook::WebhookActorHandle;

pub struct NatsClient {
    client: Client,
    webhook_handle: WebhookActorHandle,
}

impl NatsClient {
    pub async fn connect(
        url: &str,
        user: &str,
        pass: &str,
        webhook_handle: WebhookActorHandle,
    ) -> Self {
        info!(target: "app::nats", "Connecting to NATS at {}", url);

        let client = ConnectOptions::with_user_and_password(user.to_owned(), pass.to_owned())
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
            .connect(url)
            .await
            .unwrap_or_else(|err| {
                panic!("Could not connect to NATS: {err}");
            });

        Self {
            client,
            webhook_handle,
        }
    }

    async fn handle_cache_message(&self, message: Message) {
        let sub = message.subject.to_string();
        info!(target: "app::nats", "Incoming message {sub}");

        let res = String::from_utf8(message.clone().payload.into());
        if let Err(err) = res {
            error!(target: "app::nats", "Could not decode message: {err}");
            return;
        }

        let msg = res.unwrap();

        if let Err(_) = self.webhook_handle.send_webhook_event(msg).await {
            return;
        }

        self.publish_relayed_message(message).await
    }

    async fn publish_relayed_message(&self, message: Message) {
        let sub = message.subject.replace("cms", "nextjs");

        if let Err(err) = self.client.publish(sub.clone(), message.payload).await {
            error!(target: "app::nats", "Could not publish {sub}: {err}");
        }

        info!(target: "app::nats", "Relayed message via subject {sub} to NATS");
    }

    async fn subscribe_to_cache(&self) {
        let mut subscriber = self
            .client
            .subscribe("cms.cache.>")
            .await
            .unwrap_or_else(|err| {
                panic!("Could not subscribe to cms.cache.> subject: {err}");
            });

        info!(target: "app::nats", "Subscribing to cms.cache.>");

        while let Some(msg) = subscriber.next().await {
            self.handle_cache_message(msg).await;
        }
    }

    pub async fn subscribe(&self) {
        tokio::join!(self.subscribe_to_cache());
    }
}

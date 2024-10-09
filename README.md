# Next.js Cache Relay

The Next.js Cache Relay is a program that connects to a NATS server and listens
a specific subject. Whenever a message is published on that subject, the message
is sent to a URL via Webhook POST request. Additionally the same message is
re-published under a new subject after the Webhook request was successfully sent.

## Why is this needed?

A decoupled stack offers a lot of flexibility due to the backend and frontend being
separated. This means for example, that a local Next.js installation can connect
to a preview or production backend.

When using Next.js's cache for `fetch` requests, those cached responses must be somehow
invalidated. This is typically done by sending a webhook from the backend to the
Next.js deployment. However, this does not work when using a local Next.js instance
running on localhost.

By not sending the webhook directly from the backend to the frontend but instead
sending it as a message to a specific subject to NATS, this relay can listen for
those messages regardless of running on the production system or local on a
development machine.

The actual webhook is then dispatched by the relay, which can reach the local deployment.

## Race conditions

Whenever an action from the backend leads to cache invalidation in Next.js
the following two actions need to be executed:

- Inform the Next.js Server-Side to invalidate the cache.
- Inform the running instance in the browser to refresh the router.

However the order in which those actions are executed is crucial!
If the browser refreshes the router before the cache is invalidated on the
server side, the refresh does nothing.

Therefore we need a reliable way to make sure that the server side has invalidated
the cache before informing the browser.

To achieve this the relay republishes the original message under a new subject
**after** the webhook was sent successfully.

![Diagram](assets/nextjs-cache-relay-diagram.png?raw=true "Diagram")

## Configuration

Configuration is done solely via environment variables.
Dotenv files (`.env` and `.env.local`) files are loaded automatically.

|Variable|Description|Example|
|--------|-----------|-------|
|WEBHOOK_DESTINATION|URL to where to send the webhook to. This should be an endpoint of your Next.js app that handles the cache invalidation.|`http://localhost:3000/api/cache/webhook`|
|NATS_HOST|NATS server connect url, must start with `nats://` protocol.|`nats://my-natsserver.com`|
|NATS_USER|Username for NATS server.|`user`|
|NATS_PASS|Password for NATS server.|`pass`|
|NATS_SUBJECT_PREFIX|Subject prefix to listen on.|`cms.cache`|
|NATS_RELAYED_SUBJECT_PREFIX|Rewritten relayed subject prefox to republish the message on.|`relayed.cache`|

> [!NOTE]
> The relay subscribes to all child subjects via `NATS_SUBJECT_PREFIX`
> (e.g. `cms.cache.>`) and republishes the received message to NATS under
> the `NATS_RELAYED_SUBJECT_PREFIX` subject.
>
> Example: Incoming message `cms.cache.my-entity.some-id` is republished under
> `relayed.cache.my-entity.some-id`.

## Development

Enter the nix shell via `nix develop` to get a shell with all required
development tools installed.

Run `cargo build` to build the project directly.
Run `cargo run` to run the project.

Run `nix build` to build the package that is bundled via `flake.nix`.

## Server use

Add the flake from this repo as an input on the nixos server.

Import the nix module and configure it:

```nix
{ inputs, ...}: {
    imports = [
        inputs.nextjs-cache-relay.nixosModules.default
    ];

    services.nextjs-cache-relay = {
        enable = true;

        webhookDestination = "https://my-domain.com/api/cache/webhook";
        natsHost = "nats://my-nats:4222";
        natsUser = "user";
        natsPassword = "password";
        natsSubjectPrefix = "cms.cache";
        natsRelayedSubjectPrefix = "relayed.cache";
    };
}
```

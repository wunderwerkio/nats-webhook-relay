use anyhow::anyhow;
use async_nats::Message;
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct CacheRebuildMessage {
    #[serde(rename = "type")]
    msg_type: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct EntityCacheMessage {
    #[serde(rename = "type")]
    msg_type: String,
    #[serde(rename = "subType")]
    sub_type: String,
    params: EntityCacheMessageParams,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct EntityCacheMessageParams {
    id: String,
    uuid: String,
    bundle: Option<String>,
    operation: String,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum CacheMessage {
    #[serde(rename = "entity")]
    Entity {
        #[serde(rename = "subType")]
        sub_type: String,
        params: EntityCacheMessageParams,
        origin: Option<String>,
    },
    #[serde(rename = "cache_rebuild")]
    CacheRebuild { origin: Option<String> },
}

impl CacheMessage {
    pub fn with_origin(self, new_origin: String) -> Self {
        match self {
            CacheMessage::Entity {
                sub_type,
                params,
                origin: _,
            } => Self::Entity {
                sub_type,
                params,
                origin: Some(new_origin),
            },
            CacheMessage::CacheRebuild { origin: _ } => Self::CacheRebuild {
                origin: Some(new_origin),
            },
        }
    }
}

impl TryFrom<Message> for CacheMessage {
    type Error = anyhow::Error;

    fn try_from(value: Message) -> Result<Self, Self::Error> {
        let str_val = String::from_utf8(value.payload.into())?;

        match serde_json::from_str(&str_val) {
            Ok(data) => Ok(data),
            Err(err) => Err(anyhow!(err)),
        }
    }
}

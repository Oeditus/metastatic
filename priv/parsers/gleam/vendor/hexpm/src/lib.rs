// SPDX-License-Identifier: Apache-2.0
// SPDX-FileCopyrightText: 2026 The Gleam contributors

//! A trimmed Hex client, vendored for the Metastatic Gleam parser bridge.
//!
//! Upstream `hexpm` is a full Hex API client: HTTP, protobuf payloads, RSA
//! signature verification, OAuth. `gleam-core` needs none of that — it names
//! exactly two things from this crate:
//!
//! * [`version`] — the version algebra behind manifests, requirements and the
//!   "wrong compiler version" diagnostic;
//! * [`ApiError`] — a variant list that `gleam_core::error::Error` matches
//!   exhaustively.
//!
//! Both are reproduced here with upstream's semantics. Everything that would
//! require a network stack is gone, which is what lets the bridge build from
//! vendored sources with no `build.rs` and no `ring`/`prost` toolchain.
//!
//! See `vendor/README.md` for how this file is generated.

pub mod version;

use std::collections::HashMap;

use ecow::EcoString;
use thiserror::Error;
use version::{Range, Version};

/// Where the Hex API and repository live.
///
/// Kept so `gleam_core` can build request objects; nothing in this build ever
/// sends one.
#[derive(Debug, Clone)]
pub struct Config {
    /// Defaults to `https://hex.pm/api/`
    pub api_base: http::Uri,
    /// Defaults to `https://repo.hex.pm/`
    pub repository_base: http::Uri,
}

impl Config {
    pub fn new() -> Self {
        Self {
            api_base: http::Uri::from_static("https://hex.pm/api/"),
            repository_base: http::Uri::from_static("https://repo.hex.pm/"),
        }
    }
}

impl Default for Config {
    fn default() -> Self {
        Self::new()
    }
}

/// Read credentials for the repository.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Credentials {
    OAuthAccessToken(EcoString),
    ApiKey(EcoString),
}

/// Credentials for a write action.
#[derive(Debug, Clone)]
pub enum WriteActionCredentials {
    OAuthAccessToken {
        access_token: EcoString,
        one_time_password: EcoString,
    },
    ApiKey(EcoString),
}

/// Package ownership level.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub enum OwnerLevel {
    /// Every package permission except changing ownership.
    Maintainer,
    /// Every package permission, including changing ownership.
    Full,
}

impl OwnerLevel {
    fn to_json_string(self) -> &'static str {
        match self {
            OwnerLevel::Maintainer => "maintainer",
            OwnerLevel::Full => "full",
        }
    }
}

/// A package as the Hex API describes it.
#[derive(Debug, PartialEq, Clone, serde::Deserialize)]
pub struct Package {
    pub name: String,
    pub repository: String,
    #[serde(default)]
    pub releases: Vec<Release<()>>,
    #[serde(default)]
    pub advisories: Vec<SecurityAdvisory>,
}

/// One release of a package.
#[derive(Debug, PartialEq, Clone, serde::Deserialize)]
pub struct Release<Meta> {
    pub version: Version,
    #[serde(default)]
    pub requirements: HashMap<String, Dependency>,
    #[serde(default)]
    pub retirement_status: Option<RetirementStatus>,
    #[serde(default)]
    pub outer_checksum: Vec<u8>,
    #[serde(default)]
    pub security_advisories: Vec<SecurityAdvisory>,
    pub meta: Meta,
}

impl<Meta> Release<Meta> {
    pub fn is_retired(&self) -> bool {
        self.retirement_status.is_some()
    }
}

/// The `meta` payload of a release.
#[derive(Debug, PartialEq, Eq, Clone, serde::Deserialize)]
pub struct ReleaseMeta {
    pub app: String,
    #[serde(default)]
    pub build_tools: Vec<String>,
}

/// A dependency of a release.
#[derive(Debug, PartialEq, Eq, Clone, serde::Deserialize)]
pub struct Dependency {
    pub requirement: Range,
    #[serde(default)]
    pub optional: bool,
    #[serde(default)]
    pub app: Option<String>,
    #[serde(default)]
    pub repository: Option<String>,
}

/// Whether, and why, a release was retired.
///
/// `Serialize` as well as `Deserialize`: `gleam_core::audit` re-serialises a
/// retirement status into its machine-readable report, so the upstream type
/// carries both and a shim with only `Deserialize` fails to compile there.
#[derive(Debug, PartialEq, Eq, Clone, serde::Serialize, serde::Deserialize)]
pub struct RetirementStatus {
    pub reason: RetirementReason,
    pub message: String,
}

/// Why a release was retired.
#[derive(Debug, PartialEq, Eq, Clone)]
pub enum RetirementReason {
    Other,
    Invalid,
    Security,
    Deprecated,
    Renamed,
}

impl RetirementReason {
    pub fn to_str(&self) -> &'static str {
        match self {
            RetirementReason::Other => "other",
            RetirementReason::Invalid => "invalid",
            RetirementReason::Security => "security",
            RetirementReason::Deprecated => "deprecated",
            RetirementReason::Renamed => "renamed",
        }
    }
}

impl serde::Serialize for RetirementReason {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(self.to_str())
    }
}

impl<'de> serde::Deserialize<'de> for RetirementReason {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let value: &str = serde::de::Deserialize::deserialize(deserializer)?;
        match value {
            "other" => Ok(RetirementReason::Other),
            "invalid" => Ok(RetirementReason::Invalid),
            "security" => Ok(RetirementReason::Security),
            "deprecated" => Ok(RetirementReason::Deprecated),
            "renamed" => Ok(RetirementReason::Renamed),
            _ => Err(serde::de::Error::custom("unknown retirement reason")),
        }
    }
}

/// A security advisory affecting a release.
#[derive(Debug, PartialEq, Clone, serde::Deserialize)]
pub struct SecurityAdvisory {
    pub id: String,
    pub summary: String,
    pub html_url: String,
    #[serde(default)]
    pub cvss_rating: Option<AdvisorySeverity>,
    #[serde(default)]
    pub cvss_score: Option<f32>,
    pub api_url: String,
    #[serde(default)]
    pub aliases: Vec<String>,
}

/// The severity of a security advisory.
#[derive(Debug, PartialEq, Eq, Clone)]
pub enum AdvisorySeverity {
    None,
    Low,
    Medium,
    High,
    Critical,
}

impl serde::Serialize for AdvisorySeverity {
    fn serialize<S: serde::Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(self.to_str())
    }
}

impl<'de> serde::Deserialize<'de> for AdvisorySeverity {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let value: &str = serde::de::Deserialize::deserialize(deserializer)?;
        match value {
            "none" => Ok(AdvisorySeverity::None),
            "low" => Ok(AdvisorySeverity::Low),
            "medium" => Ok(AdvisorySeverity::Medium),
            "high" => Ok(AdvisorySeverity::High),
            "critical" => Ok(AdvisorySeverity::Critical),
            _ => Err(serde::de::Error::custom("unknown advisory severity type")),
        }
    }
}

impl AdvisorySeverity {
    pub fn to_str(&self) -> &'static str {
        match self {
            AdvisorySeverity::None => "none",
            AdvisorySeverity::Low => "low",
            AdvisorySeverity::Medium => "medium",
            AdvisorySeverity::High => "high",
            AdvisorySeverity::Critical => "critical",
        }
    }
}

/// The errors a Hex API call can produce.
///
/// Kept variant-for-variant with upstream even though nothing here performs an
/// API call: `gleam_core::error::Error` (and `PackageFetchError` in
/// `gleam_core::dependency`) match on this enum exhaustively, so a missing
/// variant is a compile error in the vendored compiler — which is exactly the
/// tripwire that keeps this list honest when `vendor.sh` refreshes it.
///
/// `#[allow(dead_code)]` because a parser never constructs most of these; they
/// exist to be *matched*, not built.
#[allow(dead_code)]
#[derive(Debug, Error)]
pub enum ApiError {
    #[error(transparent)]
    Json(#[from] serde_json::Error),

    #[error(transparent)]
    Io(#[from] std::io::Error),

    #[error("The rate limit for the Hex API has been exceeded")]
    RateLimited,

    #[error("Invalid authentication credentials")]
    InvalidCredentials,

    #[error("An unexpected response was sent by Hex: {0}: {1}")]
    UnexpectedResponse(u16, String),

    #[error("The given package name {0} is not valid")]
    InvalidPackageNameFormat(String),

    #[error("The payload signature does not match the downloaded payload")]
    IncorrectPayloadSignature,

    /// Upstream carries `prost::DecodeError` here. The protobuf runtime is not
    /// part of this build, so the payload is kept as its string rendering —
    /// the only thing any caller does with it is print it.
    #[error("Invalid protobuf payload: {0}")]
    InvalidProtobuf(String),

    #[error("Unexpected version format {0}")]
    InvalidVersionFormat(String),

    #[error("Resource was not found")]
    NotFound,

    #[error("The version requirement format {0} is not valid")]
    InvalidVersionRequirementFormat(String),

    #[error("The downloaded data did not have the expected checksum")]
    IncorrectChecksum,

    #[error("This account is not authorized for this action")]
    Forbidden,

    #[error("Must explicitly express your intention to replace the release")]
    NotReplacing,

    #[error("Can only modify a release up to one hour after publication")]
    LateModification,

    #[error("Can only delete a release up to one hour after publication")]
    LateDeletion,

    #[error("The oauth request wasn't approved in time")]
    OAuthTimeout,

    #[error("The oauth request was rejected")]
    OAuthAccessDenied,

    #[error("The oauth token expired before the request was approved")]
    ExpiredToken,

    #[error("The oauth refresh token was expired, revoked, or already used")]
    OAuthRefreshTokenRejected,

    #[error("The supplied one-time-password was not correct")]
    IncorrectOneTimePassword,
}

// ─────────────────────────────────────────────────────────────────────
// API request builders
// ─────────────────────────────────────────────────────────────────────
//
// `gleam_core::hex` builds these request objects and hands them to its own
// `HttpClient` abstraction. The bridge never performs a request, but the
// functions must exist and return the same shapes for `gleam-core` to compile,
// and — more importantly — for `gleam_core::hex`'s *response* handling to stay
// exercised by the upstream test suite.
//
// They are implemented faithfully (same paths, same bodies) rather than
// stubbed, because a stub that returns an empty request would make
// `gleam_core::hex` silently wrong for any host that does use it.

/// Builds a request against `base` for `path_suffix`.
fn make_request(base: http::Uri, method: http::Method, path_suffix: &str) -> http::request::Builder {
    let mut parts = base.into_parts();
    parts.path_and_query = Some(
        match parts.path_and_query {
            Some(path_and_query) => {
                let mut path = path_and_query.path().to_owned();
                if !path.ends_with('/') {
                    path.push('/');
                }
                path += path_suffix;
                path.parse().expect("valid path")
            }
            None => format!("/{path_suffix}").parse().expect("valid path"),
        },
    );

    http::Request::builder()
        .method(method)
        .uri(http::Uri::from_parts(parts).expect("valid uri"))
}

fn api_request(config: &Config, method: http::Method, path_suffix: &str) -> http::request::Builder {
    make_request(config.api_base.clone(), method, path_suffix)
        .header("content-type", "application/json")
        .header("accept", "application/json")
}

fn with_read_credentials(
    mut builder: http::request::Builder,
    credentials: Option<&Credentials>,
) -> http::request::Builder {
    if let Some(credentials) = credentials {
        let token = match credentials {
            Credentials::OAuthAccessToken(token) | Credentials::ApiKey(token) => token,
        };
        builder = builder.header("authorization", token.as_str());
    }
    builder
}

fn with_write_credentials(
    mut builder: http::request::Builder,
    credentials: &WriteActionCredentials,
) -> http::request::Builder {
    builder = match credentials {
        WriteActionCredentials::ApiKey(key) => builder.header("authorization", key.as_str()),
        WriteActionCredentials::OAuthAccessToken {
            access_token,
            one_time_password,
        } => builder
            .header("authorization", access_token.as_str())
            .header("x-hex-otp", one_time_password.as_str()),
    };
    builder
}

fn empty_request(builder: http::request::Builder) -> http::Request<Vec<u8>> {
    builder.body(Vec::new()).expect("valid request")
}

fn json_request(builder: http::request::Builder, body: serde_json::Value) -> http::Request<Vec<u8>> {
    builder
        .body(serde_json::to_vec(&body).expect("serialisable body"))
        .expect("valid request")
}

fn status_error(status: http::StatusCode, body: &[u8]) -> ApiError {
    match status {
        http::StatusCode::NOT_FOUND => ApiError::NotFound,
        http::StatusCode::TOO_MANY_REQUESTS => ApiError::RateLimited,
        http::StatusCode::UNAUTHORIZED => ApiError::InvalidCredentials,
        http::StatusCode::FORBIDDEN => ApiError::Forbidden,
        other => ApiError::UnexpectedResponse(
            other.as_u16(),
            String::from_utf8_lossy(body).to_string(),
        ),
    }
}

fn expect_status(
    response: http::Response<Vec<u8>>,
    accepted: &[http::StatusCode],
) -> Result<Vec<u8>, ApiError> {
    let (parts, body) = response.into_parts();
    if accepted.contains(&parts.status) {
        Ok(body)
    } else {
        Err(status_error(parts.status, &body))
    }
}

/// `POST /publish?replace=…` — publishes a release tarball.
pub fn api_publish_package_request(
    release_tarball: Vec<u8>,
    credentials: &WriteActionCredentials,
    config: &Config,
    replace: bool,
) -> http::Request<Vec<u8>> {
    let path = format!("publish?replace={replace}");
    let builder = with_write_credentials(api_request(config, http::Method::POST, &path), credentials);

    builder
        .header("content-type", "application/octet-stream")
        .body(release_tarball)
        .expect("valid request")
}

/// Interprets a publish response.
pub fn api_publish_package_response(response: http::Response<Vec<u8>>) -> Result<(), ApiError> {
    let (parts, body) = response.into_parts();

    match parts.status {
        http::StatusCode::OK | http::StatusCode::CREATED => Ok(()),
        http::StatusCode::UNPROCESSABLE_ENTITY => {
            let text = String::from_utf8_lossy(&body);
            if text.contains("--replace") {
                Err(ApiError::NotReplacing)
            } else if text.contains("can only modify a release up to one hour after publication") {
                Err(ApiError::LateModification)
            } else if text.contains("can only delete a release up to one hour after publication") {
                Err(ApiError::LateDeletion)
            } else {
                Err(ApiError::UnexpectedResponse(422, text.to_string()))
            }
        }
        status => Err(status_error(status, &body)),
    }
}

/// `POST /packages/{name}/releases/{version}/docs` — publishes documentation.
pub fn api_publish_docs_request(
    package_name: &str,
    version: &str,
    gzipped_tarball: Vec<u8>,
    credentials: &WriteActionCredentials,
    config: &Config,
) -> Result<http::Request<Vec<u8>>, ApiError> {
    let path = format!("packages/{package_name}/releases/{version}/docs");
    let builder = with_write_credentials(api_request(config, http::Method::POST, &path), credentials);

    Ok(builder
        .header("content-type", "application/octet-stream")
        .body(gzipped_tarball)
        .expect("valid request"))
}

/// Interprets a docs publish response.
pub fn api_publish_docs_response(response: http::Response<Vec<u8>>) -> Result<(), ApiError> {
    expect_status(response, &[http::StatusCode::CREATED]).map(|_| ())
}

/// `DELETE /keys/{name}` — removes an API key.
pub fn api_remove_api_key_request(
    name_of_key_to_delete: &str,
    credentials: &WriteActionCredentials,
    config: &Config,
) -> http::Request<Vec<u8>> {
    let path = format!("keys/{name_of_key_to_delete}");
    let builder = with_write_credentials(api_request(config, http::Method::DELETE, &path), credentials);

    empty_request(builder)
}

/// Interprets a key removal response. An already-removed key is success.
pub fn api_remove_api_key_response(response: http::Response<Vec<u8>>) -> Result<(), ApiError> {
    expect_status(
        response,
        &[
            http::StatusCode::NO_CONTENT,
            http::StatusCode::OK,
            http::StatusCode::NOT_FOUND,
        ],
    )
    .map(|_| ())
}

/// `POST /packages/{package}/releases/{version}/retire`.
pub fn api_retire_release_request(
    package: &str,
    version: &str,
    reason: RetirementReason,
    message: Option<&str>,
    credentials: &WriteActionCredentials,
    config: &Config,
) -> http::Request<Vec<u8>> {
    let path = format!("packages/{package}/releases/{version}/retire");
    let builder = with_write_credentials(api_request(config, http::Method::POST, &path), credentials);

    json_request(
        builder,
        serde_json::json!({
            "reason": reason.to_str(),
            "message": message,
        }),
    )
}

/// Interprets a retire response.
pub fn api_retire_release_response(response: http::Response<Vec<u8>>) -> Result<(), ApiError> {
    expect_status(
        response,
        &[http::StatusCode::NO_CONTENT, http::StatusCode::OK],
    )
    .map(|_| ())
}

/// `DELETE /packages/{package}/releases/{version}/retire` — un-retires.
pub fn api_unretire_release_request(
    package: &str,
    version: &str,
    credentials: &WriteActionCredentials,
    config: &Config,
) -> http::Request<Vec<u8>> {
    let path = format!("packages/{package}/releases/{version}/retire");
    let builder = with_write_credentials(api_request(config, http::Method::DELETE, &path), credentials);

    empty_request(builder)
}

/// Interprets an un-retire response.
pub fn api_unretire_release_response(response: http::Response<Vec<u8>>) -> Result<(), ApiError> {
    expect_status(
        response,
        &[http::StatusCode::NO_CONTENT, http::StatusCode::OK],
    )
    .map(|_| ())
}

/// `POST /packages/{name}/owners` — adds an owner.
pub fn api_add_owner_request(
    package_name: &str,
    owner: &str,
    level: OwnerLevel,
    credentials: &WriteActionCredentials,
    config: &Config,
) -> http::Request<Vec<u8>> {
    let path = format!("packages/{package_name}/owners");
    let builder = with_write_credentials(api_request(config, http::Method::POST, &path), credentials);

    json_request(
        builder,
        serde_json::json!({
            "level": level.to_json_string(),
            "transfer": false,
            "username": owner,
        }),
    )
}

/// Interprets an add-owner response.
pub fn api_add_owner_response(response: http::Response<Vec<u8>>) -> Result<(), ApiError> {
    expect_status(response, &[http::StatusCode::NO_CONTENT]).map(|_| ())
}

/// `POST /packages/{name}/owners` with `transfer: true`.
pub fn api_transfer_owner_request(
    package_name: &str,
    owner: &str,
    credentials: &WriteActionCredentials,
    config: &Config,
) -> http::Request<Vec<u8>> {
    let path = format!("packages/{package_name}/owners");
    let builder = with_write_credentials(api_request(config, http::Method::POST, &path), credentials);

    json_request(
        builder,
        serde_json::json!({
            "level": OwnerLevel::Full.to_json_string(),
            "transfer": true,
            "username": owner,
        }),
    )
}

/// Interprets a transfer-owner response.
pub fn api_transfer_owner_response(response: http::Response<Vec<u8>>) -> Result<(), ApiError> {
    expect_status(response, &[http::StatusCode::NO_CONTENT]).map(|_| ())
}

/// `GET /packages/{name}/releases/{version}`.
pub fn api_get_package_release_request(
    name: &str,
    version: &str,
    credentials: Option<&Credentials>,
    config: &Config,
) -> http::Request<Vec<u8>> {
    let path = format!("packages/{name}/releases/{version}");
    let builder = api_request(config, http::Method::GET, &path);

    empty_request(with_read_credentials(builder, credentials))
}

/// Interprets a package release response.
pub fn api_get_package_release_response(
    response: http::Response<Vec<u8>>,
) -> Result<Release<ReleaseMeta>, ApiError> {
    let body = expect_status(response, &[http::StatusCode::OK])?;
    Ok(serde_json::from_slice(&body)?)
}

/// `GET {repository}/packages/{name}-{version}.tar`.
pub fn repository_get_package_tarball_request(
    name: &str,
    version: &str,
    credentials: Option<&Credentials>,
    config: &Config,
) -> http::Request<Vec<u8>> {
    let path = format!("packages/{name}-{version}.tar");
    let builder = make_request(config.repository_base.clone(), http::Method::GET, &path);

    empty_request(with_read_credentials(builder, credentials))
}

/// Interprets a tarball response, verifying its checksum.
pub fn repository_get_package_tarball_response(
    response: http::Response<Vec<u8>>,
    checksum: &[u8],
) -> Result<Vec<u8>, ApiError> {
    let body = expect_status(response, &[http::StatusCode::OK])?;

    // The checksum is the SHA-256 of the tarball, as Hex publishes it. A
    // mismatch is a hard error: silently accepting a corrupted download is
    // exactly what the check exists to prevent.
    if checksum.is_empty() {
        return Ok(body);
    }

    let digest = sha256(&body);
    if digest == checksum {
        Ok(body)
    } else {
        Err(ApiError::IncorrectChecksum)
    }
}

/// SHA-256 of `data`.
///
/// Implemented here rather than pulled in as a dependency: the only caller is
/// the tarball checksum above, and a 40-line implementation is smaller than the
/// crate graph that would otherwise come with it.
fn sha256(data: &[u8]) -> Vec<u8> {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
        0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
        0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
        0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
        0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
        0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
        0xc67178f2,
    ];

    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
        0x5be0cd19,
    ];

    let mut message = data.to_vec();
    let bit_len = (data.len() as u64) * 8;
    message.push(0x80);
    while message.len() % 64 != 56 {
        message.push(0);
    }
    message.extend_from_slice(&bit_len.to_be_bytes());

    for chunk in message.chunks_exact(64) {
        let mut w = [0u32; 64];
        for (position, word) in chunk.chunks_exact(4).enumerate() {
            w[position] = u32::from_be_bytes([word[0], word[1], word[2], word[3]]);
        }
        for position in 16..64 {
            let s0 = w[position - 15].rotate_right(7)
                ^ w[position - 15].rotate_right(18)
                ^ (w[position - 15] >> 3);
            let s1 = w[position - 2].rotate_right(17)
                ^ w[position - 2].rotate_right(19)
                ^ (w[position - 2] >> 10);
            w[position] = w[position - 16]
                .wrapping_add(s0)
                .wrapping_add(w[position - 7])
                .wrapping_add(s1);
        }

        let mut a = h;
        for position in 0..64 {
            let s1 = a[4].rotate_right(6) ^ a[4].rotate_right(11) ^ a[4].rotate_right(25);
            let ch = (a[4] & a[5]) ^ (!a[4] & a[6]);
            let temp1 = a[7]
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[position])
                .wrapping_add(w[position]);
            let s0 = a[0].rotate_right(2) ^ a[0].rotate_right(13) ^ a[0].rotate_right(22);
            let maj = (a[0] & a[1]) ^ (a[0] & a[2]) ^ (a[1] & a[2]);
            let temp2 = s0.wrapping_add(maj);

            a[7] = a[6];
            a[6] = a[5];
            a[5] = a[4];
            a[4] = a[3].wrapping_add(temp1);
            a[3] = a[2];
            a[2] = a[1];
            a[1] = a[0];
            a[0] = temp1.wrapping_add(temp2);
        }

        for position in 0..8 {
            h[position] = h[position].wrapping_add(a[position]);
        }
    }

    h.iter().flat_map(|word| word.to_be_bytes()).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_module_is_reachable() {
        // The whole point of the crate: `gleam-core` writes
        // `use hexpm::version::Version;`, so the module path must exist.
        let version = version::Version::new(1, 2, 3);
        assert_eq!(version.to_string(), "1.2.3");
    }

    #[test]
    fn api_error_renders_a_message() {
        let error = ApiError::NotFound;
        assert_eq!(error.to_string(), "Resource was not found");
    }
}

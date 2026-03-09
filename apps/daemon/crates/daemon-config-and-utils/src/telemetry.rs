use sha2::{Digest, Sha256};
use url::Url;

pub fn hash_identifier(value: &str) -> String {
    let digest = Sha256::digest(value.as_bytes());
    format!("sha256:{digest:x}")
}

pub fn summarize_response_body(body: &str) -> String {
    let digest = Sha256::digest(body.as_bytes());
    format!("len={},sha256={digest:x}", body.len())
}

pub fn url_host(url: &str) -> Option<String> {
    Url::parse(url)
        .ok()
        .and_then(|parsed| parsed.host_str().map(str::to_string))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hash_identifier_is_stable() {
        let left = hash_identifier("user-123");
        let right = hash_identifier("user-123");
        assert_eq!(left, right);
        assert_ne!(left, hash_identifier("user-456"));
    }

    #[test]
    fn summarize_response_body_includes_length_and_digest() {
        let summary = summarize_response_body("hello");
        assert!(summary.contains("len=5"));
        assert!(summary.contains("sha256="));
    }

    #[test]
    fn url_host_extracts_hostname() {
        assert_eq!(
            url_host("https://example.supabase.co/rest/v1/devices").as_deref(),
            Some("example.supabase.co")
        );
    }
}

#![forbid(unsafe_code)]

#[cfg(not(target_os = "linux"))]
compile_error!("the ADR-0002 boundary demo requires Linux openat2");

#[cfg(target_os = "linux")]
mod linux;

#[cfg(target_os = "linux")]
pub use linux::{open_descendant, BoundaryError};

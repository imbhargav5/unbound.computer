//! IPC handler registration and implementation.

pub mod handlers;
mod register;

pub use register::register_handlers;

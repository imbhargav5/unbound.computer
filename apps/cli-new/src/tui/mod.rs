//! Ratatui-based Terminal UI for Unbound.
//!
//! This module provides an interactive three-panel layout similar to the macOS app:
//! - Left sidebar: repositories and sessions
//! - Center: chat panel with messages
//! - Right: version control (files, diff, terminal)

mod app;
mod claude_events;
mod components;
mod daemon_client;
mod event;
pub mod theme;
mod ui;

pub use app::App;
pub use theme::ThemeMode;

use anyhow::Result;
use crossterm::{
    cursor::Show,
    event::{DisableMouseCapture, EnableMouseCapture},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, Terminal};
use std::{io, panic};

/// Restore terminal to normal state.
/// This is called both on normal exit and on panic.
/// Ignores errors to be safe when terminal is already restored or partially setup.
fn restore_terminal() {
    // Try each restoration step independently - don't let one failure prevent others
    let _ = disable_raw_mode();
    let _ = execute!(
        io::stdout(),
        LeaveAlternateScreen,
        DisableMouseCapture,
        Show
    );
}

/// Install a panic hook that restores the terminal before displaying the panic message.
/// This prevents panic output from corrupting the terminal display.
fn install_panic_hook() {
    let original_hook = panic::take_hook();
    panic::set_hook(Box::new(move |panic_info| {
        restore_terminal();
        original_hook(panic_info);
    }));
}

/// Run the TUI application with the specified theme mode.
pub async fn run(theme_mode: ThemeMode) -> Result<()> {
    // Install panic hook BEFORE terminal setup to ensure cleanup on panic
    install_panic_hook();

    // Run the TUI and capture result (don't propagate errors yet)
    let result = run_with_terminal(theme_mode).await;

    // ALWAYS restore terminal, even if setup or run failed partway through.
    // This is safe because crossterm handles already-restored state gracefully.
    restore_terminal();

    result
}

/// Inner function that sets up terminal and runs the app.
/// Separated so that `run()` can guarantee cleanup via restore_terminal().
async fn run_with_terminal(theme_mode: ThemeMode) -> Result<()> {
    // Setup terminal
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    // Create app and run
    let mut app = App::new(theme_mode).await;
    run_app(&mut terminal, &mut app).await
}

/// Main application loop.
async fn run_app(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    app: &mut App,
) -> Result<()> {
    // Initial data refresh
    if let Err(e) = app.refresh_data().await {
        app.set_status_message(format!("Failed to connect to daemon: {}", e));
    }

    loop {
        // Advance spinner animation if Claude is running
        if app.claude_running {
            app.advance_spinner();
        }

        // Process any pending daemon events from the streaming subscription
        while let Some(ref mut rx) = app.event_receiver {
            match rx.try_recv() {
                Ok(event) => {
                    app.handle_daemon_event(event);
                }
                Err(tokio::sync::mpsc::error::TryRecvError::Empty) => break,
                Err(tokio::sync::mpsc::error::TryRecvError::Disconnected) => {
                    // Subscription closed unexpectedly
                    app.event_receiver = None;
                    break;
                }
            }
        }

        // Render
        terminal.draw(|f| ui::render(f, app))?;

        // Handle events
        if event::handle_events(app).await? {
            break;
        }
    }

    // Clean up subscription on exit
    app.stop_subscription().await;

    Ok(())
}

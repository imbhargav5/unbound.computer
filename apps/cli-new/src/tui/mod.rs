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
    event::{DisableMouseCapture, EnableMouseCapture},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, Terminal};
use std::io;

/// Run the TUI application with the specified theme mode.
pub async fn run(theme_mode: ThemeMode) -> Result<()> {
    // Setup terminal
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    // Create app and run
    let mut app = App::new(theme_mode).await;
    let result = run_app(&mut terminal, &mut app).await;

    // Restore terminal
    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )?;
    terminal.show_cursor()?;

    result
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

    let mut last_status_check = std::time::Instant::now();
    let status_check_interval = std::time::Duration::from_millis(500);

    loop {
        // Advance spinner animation if Claude is running
        if app.claude_running {
            app.advance_spinner();
        }

        // Poll subscription for new events (non-blocking)
        if app.poll_subscription() {
            // New message received via subscription - refresh from daemon
            let _ = app.fetch_messages().await;
        }

        // Poll background session subscriptions (updates claude_running flags)
        app.drain_background_subscriptions();

        // Check Claude status periodically
        if app.claude_running && last_status_check.elapsed() >= status_check_interval {
            if let Ok(is_running) = app.check_claude_status().await {
                if !is_running {
                    app.claude_running = false;
                }
            }
            last_status_check = std::time::Instant::now();
        }

        // Render
        terminal.draw(|f| ui::render(f, app))?;

        // Handle events
        if event::handle_events(app).await? {
            break;
        }
    }

    Ok(())
}

//! Theme system for the TUI.
//!
//! Provides both a custom Unbound theme and a terminal-adaptive theme
//! that respects the user's terminal color scheme.

use ratatui::style::Color;
use std::env;

/// Check if the terminal supports true color (24-bit RGB).
fn supports_true_color() -> bool {
    if let Ok(colorterm) = env::var("COLORTERM") {
        let ct = colorterm.to_lowercase();
        if ct == "truecolor" || ct == "24bit" {
            return true;
        }
    }

    // Also check TERM for some terminals that advertise it there
    if let Ok(term) = env::var("TERM") {
        let t = term.to_lowercase();
        if t.contains("truecolor") || t.contains("24bit") || t.contains("direct") {
            return true;
        }
    }

    false
}

/// Theme mode selection.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum ThemeMode {
    /// Custom Unbound brand theme (dark mode)
    #[default]
    Unbound,
    /// Terminal-adaptive theme using ANSI colors
    Terminal,
}

/// Color palette for the TUI.
#[derive(Debug, Clone, Copy)]
pub struct Theme {
    // Backgrounds
    pub bg: Color,
    pub bg_panel: Color,
    pub bg_selection: Color,
    pub bg_user_message: Color,

    // Borders
    pub border: Color,
    pub border_active: Color,

    // Text
    pub text: Color,
    pub text_secondary: Color,
    pub text_muted: Color,

    // Accent (brand color)
    pub accent: Color,

    // Semantic colors
    pub success: Color,
    pub warning: Color,
    pub error: Color,
    pub info: Color,

    // Message colors
    pub user_message: Color,
    pub assistant_message: Color,
    pub system_message: Color,

    // Spinner/loading
    pub spinner: Color,
}

impl Theme {
    /// Create the Unbound brand theme (dark mode).
    /// Automatically detects terminal capabilities and uses RGB colors when
    /// true color is supported, falling back to 256-color palette otherwise.
    pub fn unbound() -> Self {
        if supports_true_color() {
            Self::unbound_rgb()
        } else {
            Self::unbound_256()
        }
    }

    /// Unbound theme using true color (24-bit RGB).
    /// For terminals that support COLORTERM=truecolor.
    fn unbound_rgb() -> Self {
        Self {
            // Backgrounds - from black palette
            bg: Color::Rgb(0x0A, 0x0E, 0x15),           // black-100
            bg_panel: Color::Rgb(0x21, 0x26, 0x31),     // black-90
            bg_selection: Color::Rgb(0x37, 0x3F, 0x4E), // black-80
            bg_user_message: Color::Rgb(0x1A, 0x24, 0x35), // dark blue-gray for user messages

            // Borders
            border: Color::Rgb(0x4E, 0x57, 0x6A), // black-70
            border_active: Color::Rgb(0xEE, 0xD2, 0x63), // yellow-80 (brand)

            // Text - from white palette
            text: Color::Rgb(0xFF, 0xFF, 0xFF), // white-100
            text_secondary: Color::Rgb(0xE0, 0xE4, 0xEB), // white-80
            text_muted: Color::Rgb(0xBF, 0xC6, 0xD4), // white-60

            // Accent (brand yellow)
            accent: Color::Rgb(0xEE, 0xD2, 0x63), // yellow-80

            // Semantic colors
            success: Color::Rgb(0x8E, 0xEF, 0xE8), // green-100
            warning: Color::Rgb(0xEE, 0xD2, 0x63), // yellow-80
            error: Color::Rgb(0xE8, 0x8E, 0x8E),   // red
            info: Color::Rgb(0x8E, 0xB2, 0xEB),    // blue

            // Message colors
            user_message: Color::Rgb(0x8E, 0xB2, 0xEB), // blue
            assistant_message: Color::Rgb(0x8E, 0xEF, 0xE8), // green-100
            system_message: Color::Rgb(0xEE, 0xD2, 0x63), // yellow-80

            // Spinner
            spinner: Color::Rgb(0xDC, 0xB6, 0xF7), // purple-100
        }
    }

    /// Unbound theme using 256-color palette.
    /// For terminals like macOS Terminal.app that don't support true color.
    fn unbound_256() -> Self {
        // 256-color palette indexes:
        // 232-255: Grayscale (232=almost black, 255=almost white)
        // 16-231: 6x6x6 color cube

        Self {
            // Backgrounds - grayscale dark tones
            bg: Color::Indexed(233),           // Very dark gray (black-100)
            bg_panel: Color::Indexed(235),     // Dark gray (black-90)
            bg_selection: Color::Indexed(238), // Medium dark (black-80)
            bg_user_message: Color::Indexed(236), // Dark gray for user messages

            // Borders
            border: Color::Indexed(241),        // Gray (black-70)
            border_active: Color::Indexed(220), // Yellow (brand)

            // Text - grayscale light tones
            text: Color::Indexed(255),           // Almost white
            text_secondary: Color::Indexed(252), // Light gray
            text_muted: Color::Indexed(245),     // Medium gray

            // Accent (brand yellow)
            accent: Color::Indexed(220), // Bright yellow

            // Semantic colors
            success: Color::Indexed(123), // Cyan/teal (green-100)
            warning: Color::Indexed(220), // Yellow
            error: Color::Indexed(210),   // Light red/coral
            info: Color::Indexed(111),    // Light blue

            // Message colors
            user_message: Color::Indexed(111),      // Light blue
            assistant_message: Color::Indexed(123), // Cyan/teal
            system_message: Color::Indexed(220),    // Yellow

            // Spinner
            spinner: Color::Indexed(183), // Light purple
        }
    }

    /// Create a terminal-adaptive theme using ANSI colors.
    /// This respects the user's terminal color scheme.
    pub fn terminal() -> Self {
        Self {
            // Backgrounds - use terminal defaults
            bg: Color::Reset,
            bg_panel: Color::Reset,
            bg_selection: Color::DarkGray,
            bg_user_message: Color::DarkGray,

            // Borders
            border: Color::DarkGray,
            border_active: Color::Yellow,

            // Text
            text: Color::Reset,
            text_secondary: Color::Gray,
            text_muted: Color::DarkGray,

            // Accent
            accent: Color::Yellow,

            // Semantic colors
            success: Color::Green,
            warning: Color::Yellow,
            error: Color::Red,
            info: Color::Blue,

            // Message colors
            user_message: Color::Cyan,
            assistant_message: Color::Green,
            system_message: Color::Yellow,

            // Spinner
            spinner: Color::Magenta,
        }
    }

    /// Get theme based on mode.
    pub fn from_mode(mode: ThemeMode) -> Self {
        match mode {
            ThemeMode::Unbound => Self::unbound(),
            ThemeMode::Terminal => Self::terminal(),
        }
    }
}

impl Default for Theme {
    fn default() -> Self {
        Self::unbound()
    }
}

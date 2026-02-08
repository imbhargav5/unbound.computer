// Package config provides configuration management for Nagato.
package config

import (
	"os"
	"path/filepath"
	"strconv"
	"time"

	"github.com/google/uuid"
)

const (
	// Default values
	DefaultDaemonTimeout = 15 * time.Second
	DefaultSocketName    = "nagato.sock"
	DefaultBaseDir       = ".unbound"
	DefaultEventName     = "remote.command.v1"

	// Environment variable names
	EnvAblyKey        = "ABLY_API_KEY"
	EnvNagatoSocket   = "NAGATO_SOCKET"
	EnvDaemonTimeout  = "NAGATO_DAEMON_TIMEOUT"
	EnvUnboundBaseDir = "UNBOUND_BASE_DIR"
)

// Config holds all configuration for the Nagato consumer.
type Config struct {
	// AblyKey is the Ably API key for authentication.
	AblyKey string

	// DeviceID is the unique identifier for this device.
	// Used to construct the channel name: remote:{device_id}:commands
	DeviceID string

	// SocketPath is the path to the Unix domain socket for daemon communication.
	SocketPath string

	// DaemonTimeout is how long to wait for the daemon to respond before fail-open.
	DaemonTimeout time.Duration

	// ConsumerName is a unique identifier for this Nagato instance.
	// Format: nagato-{uuid}
	ConsumerName string

	// ChannelName is the Ably channel to subscribe to.
	// Format: remote:{device_id}:commands
	ChannelName string

	// EventName is the Ably event name to consume from the channel.
	EventName string
}

// New creates a new Config with values from environment variables and defaults.
func New(deviceID string) (*Config, error) {
	cfg := &Config{
		DeviceID:      deviceID,
		ConsumerName:  "nagato-" + uuid.New().String(),
		DaemonTimeout: DefaultDaemonTimeout,
		EventName:     DefaultEventName,
	}

	// Ably API key (required)
	cfg.AblyKey = os.Getenv(EnvAblyKey)

	// Channel name derived from device ID
	cfg.ChannelName = "remote:" + deviceID + ":commands"

	// Socket path
	if socketPath := os.Getenv(EnvNagatoSocket); socketPath != "" {
		cfg.SocketPath = socketPath
	} else {
		baseDir := os.Getenv(EnvUnboundBaseDir)
		if baseDir == "" {
			homeDir, err := os.UserHomeDir()
			if err != nil {
				return nil, err
			}
			baseDir = filepath.Join(homeDir, DefaultBaseDir)
		}
		cfg.SocketPath = filepath.Join(baseDir, DefaultSocketName)
	}

	// Daemon timeout
	if timeoutStr := os.Getenv(EnvDaemonTimeout); timeoutStr != "" {
		timeoutSecs, err := strconv.Atoi(timeoutStr)
		if err != nil {
			return nil, err
		}
		cfg.DaemonTimeout = time.Duration(timeoutSecs) * time.Second
	}

	return cfg, nil
}

// Validate checks that all required configuration is present.
func (c *Config) Validate() error {
	if c.AblyKey == "" {
		return &ConfigError{Field: "AblyKey", Message: "ABLY_API_KEY environment variable is required"}
	}
	if c.DeviceID == "" {
		return &ConfigError{Field: "DeviceID", Message: "device ID is required"}
	}
	if c.SocketPath == "" {
		return &ConfigError{Field: "SocketPath", Message: "socket path is required"}
	}
	if c.EventName == "" {
		return &ConfigError{Field: "EventName", Message: "event name is required"}
	}
	return nil
}

// ConfigError represents a configuration validation error.
type ConfigError struct {
	Field   string
	Message string
}

func (e *ConfigError) Error() string {
	return "config error: " + e.Field + ": " + e.Message
}

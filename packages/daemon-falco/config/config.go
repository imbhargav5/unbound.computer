// Package config provides configuration management for Falco.
package config

import (
	"os"
	"path/filepath"
	"strconv"
	"time"
)

const (
	// Default values
	DefaultPublishTimeout = 5 * time.Second
	DefaultSocketName     = "falco.sock"
	DefaultBaseDir        = ".unbound"

	// Environment variable names
	EnvAblyKey         = "ABLY_API_KEY"
	EnvFalcoSocket     = "FALCO_SOCKET"
	EnvPublishTimeout  = "FALCO_PUBLISH_TIMEOUT"
	EnvUnboundBaseDir  = "UNBOUND_BASE_DIR"
)

// Config holds all configuration for the Falco publisher.
type Config struct {
	// AblyKey is the Ably API key for authentication.
	AblyKey string

	// DeviceID is the unique identifier for this device.
	// Used to construct the channel name: device-events:{device_id}
	DeviceID string

	// SocketPath is the path to the Unix domain socket for daemon communication.
	SocketPath string

	// PublishTimeout is how long to wait for Ably publish to complete.
	PublishTimeout time.Duration

	// ChannelName is the Ably channel to publish to.
	// Format: device-events:{device_id}
	ChannelName string
}

// New creates a new Config with values from environment variables and defaults.
func New(deviceID string) (*Config, error) {
	cfg := &Config{
		DeviceID:       deviceID,
		PublishTimeout: DefaultPublishTimeout,
	}

	// Ably API key (required)
	cfg.AblyKey = os.Getenv(EnvAblyKey)

	// Channel name derived from device ID
	cfg.ChannelName = "device-events:" + deviceID

	// Socket path
	if socketPath := os.Getenv(EnvFalcoSocket); socketPath != "" {
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

	// Publish timeout
	if timeoutStr := os.Getenv(EnvPublishTimeout); timeoutStr != "" {
		timeoutSecs, err := strconv.Atoi(timeoutStr)
		if err != nil {
			return nil, err
		}
		cfg.PublishTimeout = time.Duration(timeoutSecs) * time.Second
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

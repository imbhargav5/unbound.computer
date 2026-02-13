package config

import (
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"time"
)

const (
	DefaultSocketName        = "ably.sock"
	DefaultBaseDir           = ".unbound"
	DefaultMaxFrameBytes     = 2 * 1024 * 1024
	DefaultHeartbeatInterval = 5 * time.Second
	DefaultPublishTimeout    = 5 * time.Second
	DefaultShutdownTimeout   = 2 * time.Second
	DefaultPresenceEventName = "daemon.presence.v1"
	DefaultPresenceSource    = "daemon-ably"
	EnvUnboundBaseDir        = "UNBOUND_BASE_DIR"
	EnvAblySocket            = "UNBOUND_ABLY_SOCKET"
	EnvAblyBrokerSocket      = "UNBOUND_ABLY_BROKER_SOCKET"
	EnvAblyBrokerTokenFalco  = "UNBOUND_ABLY_BROKER_TOKEN_FALCO"
	EnvAblyBrokerTokenNagato = "UNBOUND_ABLY_BROKER_TOKEN_NAGATO"
	EnvMaxFrameBytes         = "DAEMON_ABLY_MAX_FRAME_BYTES"
	EnvHeartbeatIntervalSec  = "DAEMON_ABLY_HEARTBEAT_INTERVAL"
	EnvPublishTimeoutSec     = "DAEMON_ABLY_PUBLISH_TIMEOUT"
	EnvShutdownTimeoutSec    = "DAEMON_ABLY_SHUTDOWN_TIMEOUT"
)

type Config struct {
	DeviceID string
	UserID   string

	SocketPath        string
	BrokerSocketPath  string
	BrokerFalcoToken  string
	BrokerNagatoToken string
	MaxFrameBytes     int

	HeartbeatInterval time.Duration
	PublishTimeout    time.Duration
	ShutdownTimeout   time.Duration

	PresenceChannel string
	PresenceEvent   string
	PresenceSource  string
}

func New(deviceID string, userID string) (*Config, error) {
	cfg := &Config{
		DeviceID:          deviceID,
		UserID:            userID,
		MaxFrameBytes:     DefaultMaxFrameBytes,
		HeartbeatInterval: DefaultHeartbeatInterval,
		PublishTimeout:    DefaultPublishTimeout,
		ShutdownTimeout:   DefaultShutdownTimeout,
		PresenceEvent:     DefaultPresenceEventName,
		PresenceSource:    DefaultPresenceSource,
	}

	if socketPath := os.Getenv(EnvAblySocket); socketPath != "" {
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

	cfg.BrokerSocketPath = os.Getenv(EnvAblyBrokerSocket)
	cfg.BrokerFalcoToken = os.Getenv(EnvAblyBrokerTokenFalco)
	cfg.BrokerNagatoToken = os.Getenv(EnvAblyBrokerTokenNagato)
	cfg.PresenceChannel = fmt.Sprintf("presence:%s", userID)

	if heartbeatSeconds := os.Getenv(EnvHeartbeatIntervalSec); heartbeatSeconds != "" {
		seconds, err := strconv.Atoi(heartbeatSeconds)
		if err != nil {
			return nil, fmt.Errorf("invalid %s: %w", EnvHeartbeatIntervalSec, err)
		}
		cfg.HeartbeatInterval = time.Duration(seconds) * time.Second
	}

	if publishTimeoutSeconds := os.Getenv(EnvPublishTimeoutSec); publishTimeoutSeconds != "" {
		seconds, err := strconv.Atoi(publishTimeoutSeconds)
		if err != nil {
			return nil, fmt.Errorf("invalid %s: %w", EnvPublishTimeoutSec, err)
		}
		cfg.PublishTimeout = time.Duration(seconds) * time.Second
	}

	if shutdownTimeoutSeconds := os.Getenv(EnvShutdownTimeoutSec); shutdownTimeoutSeconds != "" {
		seconds, err := strconv.Atoi(shutdownTimeoutSeconds)
		if err != nil {
			return nil, fmt.Errorf("invalid %s: %w", EnvShutdownTimeoutSec, err)
		}
		cfg.ShutdownTimeout = time.Duration(seconds) * time.Second
	}

	if maxFrameBytes := os.Getenv(EnvMaxFrameBytes); maxFrameBytes != "" {
		size, err := strconv.Atoi(maxFrameBytes)
		if err != nil {
			return nil, fmt.Errorf("invalid %s: %w", EnvMaxFrameBytes, err)
		}
		cfg.MaxFrameBytes = size
	}

	return cfg, nil
}

func (c *Config) Validate() error {
	if c.DeviceID == "" {
		return fmt.Errorf("device id is required")
	}
	if c.UserID == "" {
		return fmt.Errorf("user id is required")
	}
	if c.SocketPath == "" {
		return fmt.Errorf("%s environment variable is required", EnvAblySocket)
	}
	if c.BrokerSocketPath == "" {
		return fmt.Errorf("%s environment variable is required", EnvAblyBrokerSocket)
	}
	if c.BrokerFalcoToken == "" {
		return fmt.Errorf("%s environment variable is required", EnvAblyBrokerTokenFalco)
	}
	if c.BrokerNagatoToken == "" {
		return fmt.Errorf("%s environment variable is required", EnvAblyBrokerTokenNagato)
	}
	if c.PresenceChannel == "" {
		return fmt.Errorf("presence channel is required")
	}
	if c.PresenceEvent == "" {
		return fmt.Errorf("presence event is required")
	}
	if c.HeartbeatInterval <= 0 {
		return fmt.Errorf("heartbeat interval must be positive")
	}
	if c.PublishTimeout <= 0 {
		return fmt.Errorf("publish timeout must be positive")
	}
	if c.ShutdownTimeout <= 0 {
		return fmt.Errorf("shutdown timeout must be positive")
	}
	if c.MaxFrameBytes <= 0 {
		return fmt.Errorf("max frame bytes must be positive")
	}
	return nil
}

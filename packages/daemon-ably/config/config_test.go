package config

import "testing"

func TestNewUsesDefaultMaxFrameBytes(t *testing.T) {
	cfg, err := New("device-1", "user-1")
	if err != nil {
		t.Fatalf("new config: %v", err)
	}

	if cfg.MaxFrameBytes != DefaultMaxFrameBytes {
		t.Fatalf("expected default max frame bytes %d, got %d", DefaultMaxFrameBytes, cfg.MaxFrameBytes)
	}
}

func TestNewLoadsMaxFrameBytesFromEnv(t *testing.T) {
	t.Setenv(EnvMaxFrameBytes, "8192")

	cfg, err := New("device-1", "user-1")
	if err != nil {
		t.Fatalf("new config: %v", err)
	}

	if cfg.MaxFrameBytes != 8192 {
		t.Fatalf("expected max frame bytes from env, got %d", cfg.MaxFrameBytes)
	}
}

func TestValidateRejectsNonPositiveMaxFrameBytes(t *testing.T) {
	cfg := &Config{
		DeviceID:          "device-1",
		UserID:            "user-1",
		SocketPath:        "/tmp/ably.sock",
		BrokerSocketPath:  "/tmp/ably-auth.sock",
		BrokerFalcoToken:  "falco",
		BrokerNagatoToken: "nagato",
		PresenceChannel:   "presence:user-1",
		PresenceEvent:     "daemon.presence.v1",
		HeartbeatInterval: DefaultHeartbeatInterval,
		PublishTimeout:    DefaultPublishTimeout,
		ShutdownTimeout:   DefaultShutdownTimeout,
		MaxFrameBytes:     0,
	}

	if err := cfg.Validate(); err == nil {
		t.Fatalf("expected validate error for non-positive max frame bytes")
	}
}

package runtime

import (
	"context"
	"errors"
	"strings"
	"sync"
	"testing"
	"time"

	"go.uber.org/zap"

	ablyconfig "github.com/unbound-computer/daemon-ably/config"
)

func TestRestoreSubscriptionsReplaysAllOnReconnect(t *testing.T) {
	cfg := testConfig()
	manager := &Manager{
		cfg:           cfg,
		logger:        zap.NewNop(),
		subs:          make(map[string]*subscription),
		heartbeatDone: make(chan struct{}),
	}

	manager.subs["sub-1"] = &subscription{id: "sub-1", channel: "remote:1:commands", event: "remote.command.v1"}
	manager.subs["sub-2"] = &subscription{id: "sub-2", channel: "remote:2:commands", event: "remote.command.v1"}

	var (
		mu      sync.Mutex
		called  = make(map[string]int)
		failSub = "sub-1"
	)
	manager.attachSubscriptionOverride = func(_ context.Context, sub *subscription) error {
		mu.Lock()
		called[sub.id]++
		mu.Unlock()
		if sub.id == failSub {
			return errors.New("inject reconnect failure")
		}
		return nil
	}

	manager.restoreSubscriptions()

	mu.Lock()
	defer mu.Unlock()
	if called["sub-1"] != 1 || called["sub-2"] != 1 {
		t.Fatalf("expected both subscriptions restored once, got %+v", called)
	}
}

func TestHeartbeatLifecyclePublishesOnlineAndOfflinePresence(t *testing.T) {
	cfg := testConfig()
	cfg.HeartbeatInterval = 10 * time.Millisecond
	cfg.PublishTimeout = 50 * time.Millisecond
	cfg.ShutdownTimeout = 50 * time.Millisecond

	manager := &Manager{
		cfg:           cfg,
		logger:        zap.NewNop(),
		subs:          make(map[string]*subscription),
		heartbeatDone: make(chan struct{}),
	}

	var (
		mu       sync.Mutex
		payloads []PresencePayload
	)
	manager.publishPresenceOverride = func(_ context.Context, payload PresencePayload) error {
		mu.Lock()
		payloads = append(payloads, payload)
		mu.Unlock()
		return nil
	}

	if err := manager.publishPresence(context.Background(), statusOnline); err != nil {
		t.Fatalf("publish initial online presence: %v", err)
	}

	go manager.heartbeatLoop()
	waitForCondition(t, 2*time.Second, func() bool {
		mu.Lock()
		defer mu.Unlock()
		return len(payloads) >= 2
	})

	if err := manager.Close(); err != nil {
		t.Fatalf("close manager: %v", err)
	}

	mu.Lock()
	defer mu.Unlock()

	var hasOnline bool
	var hasOffline bool
	for _, payload := range payloads {
		if payload.Status == statusOnline {
			hasOnline = true
		}
		if payload.Status == statusOffline {
			hasOffline = true
		}
		if payload.SchemaVersion != 1 {
			t.Fatalf("unexpected schema version: %d", payload.SchemaVersion)
		}
		expectedUserID := strings.ToLower(cfg.UserID)
		if payload.UserID != expectedUserID {
			t.Fatalf("unexpected user id: got %q, expected %q", payload.UserID, expectedUserID)
		}
		if payload.DeviceID != cfg.DeviceID {
			t.Fatalf("unexpected device id: %q", payload.DeviceID)
		}
		if payload.Source != cfg.PresenceSource {
			t.Fatalf("unexpected source: %q", payload.Source)
		}
		if payload.TTLMS != cfg.PresenceDOTTLMS {
			t.Fatalf("unexpected ttl: %d", payload.TTLMS)
		}
	}
	if !hasOnline {
		t.Fatalf("expected at least one online heartbeat payload")
	}
	if !hasOffline {
		t.Fatalf("expected offline heartbeat payload on close")
	}
}

func testConfig() *ablyconfig.Config {
	return &ablyconfig.Config{
		DeviceID:          "11111111-1111-1111-1111-111111111111",
		UserID:            "USER-1",
		PresenceChannel:   "presence:user-1",
		PresenceEvent:     "daemon.presence.v1",
		PresenceSource:    "daemon-do",
		PresenceDOTTLMS:   12000,
		HeartbeatInterval: 50 * time.Millisecond,
		PublishTimeout:    50 * time.Millisecond,
		ShutdownTimeout:   50 * time.Millisecond,
	}
}

func TestPublishPresenceNormalizesUserID(t *testing.T) {
	cfg := testConfig()
	manager := &Manager{
		cfg:    cfg,
		logger: zap.NewNop(),
	}

	var decoded PresencePayload
	manager.publishPresenceOverride = func(_ context.Context, payload PresencePayload) error {
		decoded = payload
		return nil
	}

	if err := manager.publishPresence(context.Background(), statusOnline); err != nil {
		t.Fatalf("publish presence: %v", err)
	}

	if decoded.UserID != strings.ToLower(cfg.UserID) {
		t.Fatalf("expected normalized user id %q, got %q", strings.ToLower(cfg.UserID), decoded.UserID)
	}
}

func waitForCondition(t *testing.T, timeout time.Duration, condition func() bool) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if condition() {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatalf("condition was not met within %s", timeout)
}

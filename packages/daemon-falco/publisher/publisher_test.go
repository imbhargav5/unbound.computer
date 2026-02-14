package publisher

import (
	"context"
	"errors"
	"testing"
	"time"

	"go.uber.org/zap"

	ablyclient "github.com/unbound-computer/daemon-ably-client/client"
	"github.com/unbound-computer/daemon-falco/sideeffect"
)

func TestPublishUsesChannelEventPayloadOverrides(t *testing.T) {
	mock := &mockIPCClient{}
	pub := newWithClient(mock, Options{
		ChannelName:    "default:channel",
		PublishTimeout: time.Second,
		Logger:         zap.NewNop(),
	})

	effect := &sideeffect.SideEffect{
		Type:      sideeffect.MessageAppended,
		Channel:   "remote:test-device:commands",
		Event:     "remote.command.response.v1",
		Payload:   []byte(`{"response":"ok"}`),
		SessionID: "session-1",
	}

	if err := pub.Publish(context.Background(), effect); err != nil {
		t.Fatalf("publish failed: %v", err)
	}

	if len(mock.publishes) != 1 {
		t.Fatalf("expected 1 publish, got %d", len(mock.publishes))
	}
	call := mock.publishes[0]
	if call.channel != "remote:test-device:commands" {
		t.Fatalf("unexpected channel: %s", call.channel)
	}
	if call.event != "remote.command.response.v1" {
		t.Fatalf("unexpected event: %s", call.event)
	}
	if string(call.payload) != `{"response":"ok"}` {
		t.Fatalf("unexpected payload: %s", string(call.payload))
	}
}

func TestPublishRetriesUntilSuccess(t *testing.T) {
	mock := &mockIPCClient{
		publishErrors: []error{
			ablyclient.ErrNotConnected,
			errors.New("transient"),
			nil,
		},
	}
	pub := newWithClient(mock, Options{
		ChannelName:    "default:channel",
		PublishTimeout: time.Second,
		Logger:         zap.NewNop(),
	})

	effect := &sideeffect.SideEffect{
		Type: sideeffect.MessageAppended,
	}

	if err := pub.Publish(context.Background(), effect); err != nil {
		t.Fatalf("publish failed unexpectedly: %v", err)
	}
	if len(mock.publishes) != 3 {
		t.Fatalf("expected 3 publish attempts, got %d", len(mock.publishes))
	}
}

func TestPublishFailsAfterRetryExhaustion(t *testing.T) {
	mock := &mockIPCClient{
		publishErrors: []error{
			errors.New("attempt1"),
			errors.New("attempt2"),
			errors.New("attempt3"),
		},
	}
	pub := newWithClient(mock, Options{
		ChannelName:    "default:channel",
		PublishTimeout: time.Second,
		Logger:         zap.NewNop(),
	})

	effect := &sideeffect.SideEffect{
		Type: sideeffect.MessageAppended,
	}

	err := pub.Publish(context.Background(), effect)
	if err == nil {
		t.Fatalf("expected publish failure, got nil")
	}
	if !errors.Is(err, ErrPublishFailed) {
		t.Fatalf("expected ErrPublishFailed, got %v", err)
	}
	if len(mock.publishes) != MaxRetries {
		t.Fatalf("expected %d publish attempts, got %d", MaxRetries, len(mock.publishes))
	}
}

func TestPublishObjectSetUsesObjectSetPath(t *testing.T) {
	mock := &mockIPCClient{}
	pub := newWithClient(mock, Options{
		ChannelName:    "default:channel",
		PublishTimeout: time.Second,
		Logger:         zap.NewNop(),
	})

	if err := pub.PublishObjectSet(
		context.Background(),
		"session:abc:status",
		"coding_session_status",
		[]byte(`{"status":"running"}`),
	); err != nil {
		t.Fatalf("object set failed: %v", err)
	}

	if len(mock.objectSets) != 1 {
		t.Fatalf("expected 1 object set call, got %d", len(mock.objectSets))
	}
	call := mock.objectSets[0]
	if call.channel != "session:abc:status" {
		t.Fatalf("unexpected channel: %s", call.channel)
	}
	if call.key != "coding_session_status" {
		t.Fatalf("unexpected key: %s", call.key)
	}
	if string(call.value) != `{"status":"running"}` {
		t.Fatalf("unexpected value: %s", string(call.value))
	}
}

type publishCall struct {
	channel string
	event   string
	payload []byte
}

type objectSetCall struct {
	channel string
	key     string
	value   []byte
}

type mockIPCClient struct {
	publishes       []publishCall
	objectSets      []objectSetCall
	publishErrors   []error
	objectSetErrors []error
	connectErr      error
	closed          bool
}

func (m *mockIPCClient) Connect(context.Context) error {
	return m.connectErr
}

func (m *mockIPCClient) Publish(
	_ context.Context,
	channel string,
	event string,
	payload []byte,
	_ time.Duration,
) error {
	m.publishes = append(m.publishes, publishCall{
		channel: channel,
		event:   event,
		payload: append([]byte(nil), payload...),
	})

	if len(m.publishErrors) == 0 {
		return nil
	}
	err := m.publishErrors[0]
	if len(m.publishErrors) > 1 {
		m.publishErrors = m.publishErrors[1:]
	}
	return err
}

func (m *mockIPCClient) ObjectSet(
	_ context.Context,
	channel string,
	key string,
	value []byte,
	_ time.Duration,
) error {
	m.objectSets = append(m.objectSets, objectSetCall{
		channel: channel,
		key:     key,
		value:   append([]byte(nil), value...),
	})

	if len(m.objectSetErrors) == 0 {
		return nil
	}
	err := m.objectSetErrors[0]
	if len(m.objectSetErrors) > 1 {
		m.objectSetErrors = m.objectSetErrors[1:]
	}
	return err
}

func (m *mockIPCClient) Close() error {
	m.closed = true
	return nil
}

func (m *mockIPCClient) IsConnected() bool {
	return !m.closed
}

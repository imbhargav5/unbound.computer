package consumer

import (
	"context"
	"errors"
	"testing"
	"time"

	"go.uber.org/zap"

	ablyclient "github.com/unbound-computer/daemon-ably-client/client"
)

func TestConnectSubscribesWithExpectedChannelAndEvent(t *testing.T) {
	mock := newMockTransport()
	cons := newWithClient(mock, Options{
		ChannelName:    "remote:test-device:commands",
		EventName:      "remote.command.v1",
		SubscriptionID: "nagato-test",
		BufferSize:     1,
		Logger:         zap.NewNop(),
	})
	defer cons.Close()

	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()

	if err := cons.Connect(ctx); err != nil {
		t.Fatalf("connect failed: %v", err)
	}

	if mock.subscribeCalls != 1 {
		t.Fatalf("expected subscribe call, got %d", mock.subscribeCalls)
	}
	if mock.lastSubscription.SubscriptionID != "nagato-test" {
		t.Fatalf("unexpected subscription id: %s", mock.lastSubscription.SubscriptionID)
	}
	if mock.lastSubscription.Channel != "remote:test-device:commands" {
		t.Fatalf("unexpected channel: %s", mock.lastSubscription.Channel)
	}
	if mock.lastSubscription.Event != "remote.command.v1" {
		t.Fatalf("unexpected event: %s", mock.lastSubscription.Event)
	}
}

func TestPublishUsesPublishAckOperation(t *testing.T) {
	mock := newMockTransport()
	cons := newWithClient(mock, Options{
		ChannelName:    "remote:test-device:commands",
		EventName:      "remote.command.v1",
		SubscriptionID: "nagato-test",
		BufferSize:     1,
		Logger:         zap.NewNop(),
	})
	defer cons.Close()

	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if err := cons.Connect(ctx); err != nil {
		t.Fatalf("connect failed: %v", err)
	}

	payload := []byte(`{"status":"accepted"}`)
	if err := cons.Publish(ctx, "remote.command.ack.v1", payload); err != nil {
		t.Fatalf("publish failed: %v", err)
	}

	if mock.publishAckCalls != 1 {
		t.Fatalf("expected publish.ack call, got %d", mock.publishAckCalls)
	}
	if mock.lastPublishChannel != "remote:test-device:commands" {
		t.Fatalf("unexpected publish channel: %s", mock.lastPublishChannel)
	}
	if mock.lastPublishEvent != "remote.command.ack.v1" {
		t.Fatalf("unexpected publish event: %s", mock.lastPublishEvent)
	}
	if string(mock.lastPublishPayload) != string(payload) {
		t.Fatalf("unexpected publish payload: %s", string(mock.lastPublishPayload))
	}
}

func TestForwardsInboundTransportMessages(t *testing.T) {
	mock := newMockTransport()
	cons := newWithClient(mock, Options{
		ChannelName:    "remote:test-device:commands",
		EventName:      "remote.command.v1",
		SubscriptionID: "nagato-test",
		BufferSize:     1,
		Logger:         zap.NewNop(),
	})
	defer cons.Close()

	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	if err := cons.Connect(ctx); err != nil {
		t.Fatalf("connect failed: %v", err)
	}

	mock.messages <- &ablyclient.Message{
		SubscriptionID: "nagato-test",
		MessageID:      "msg-1",
		Channel:        "remote:test-device:commands",
		Event:          "remote.command.v1",
		Payload:        []byte(`{"command":"run"}`),
		ReceivedAtMS:   time.Now().UnixMilli(),
	}

	select {
	case message := <-cons.Receive():
		if message.ID != "msg-1" {
			t.Fatalf("unexpected message id: %s", message.ID)
		}
		if string(message.Payload) != `{"command":"run"}` {
			t.Fatalf("unexpected message payload: %s", string(message.Payload))
		}
	case <-ctx.Done():
		t.Fatalf("timed out waiting for forwarded message")
	}
}

type mockTransport struct {
	connectErr       error
	subscribeErr     error
	publishAckErr    error
	connected        bool
	closed           bool
	subscribeCalls   int
	publishAckCalls  int
	lastSubscription ablyclient.Subscription
	lastPublishChannel string
	lastPublishEvent string
	lastPublishPayload []byte
	messages         chan *ablyclient.Message
	errors           chan error
}

func newMockTransport() *mockTransport {
	return &mockTransport{
		connected: true,
		messages:  make(chan *ablyclient.Message, 8),
		errors:    make(chan error, 8),
	}
}

func (m *mockTransport) Connect(context.Context) error {
	return m.connectErr
}

func (m *mockTransport) Subscribe(_ context.Context, sub ablyclient.Subscription) error {
	m.subscribeCalls++
	m.lastSubscription = sub
	return m.subscribeErr
}

func (m *mockTransport) PublishAck(
	_ context.Context,
	channel string,
	event string,
	payload []byte,
	_ time.Duration,
) error {
	m.publishAckCalls++
	m.lastPublishChannel = channel
	m.lastPublishEvent = event
	m.lastPublishPayload = append([]byte(nil), payload...)
	return m.publishAckErr
}

func (m *mockTransport) Messages() <-chan *ablyclient.Message {
	return m.messages
}

func (m *mockTransport) Errors() <-chan error {
	return m.errors
}

func (m *mockTransport) Close() error {
	m.closed = true
	return nil
}

func (m *mockTransport) IsConnected() bool {
	if m.closed {
		return false
	}
	return m.connected
}

func TestPublishFailsWhenDisconnected(t *testing.T) {
	mock := newMockTransport()
	mock.connected = false
	cons := newWithClient(mock, Options{
		ChannelName:    "remote:test-device:commands",
		EventName:      "remote.command.v1",
		SubscriptionID: "nagato-test",
		BufferSize:     1,
		Logger:         zap.NewNop(),
	})
	defer cons.Close()

	err := cons.Publish(context.Background(), "remote.command.ack.v1", []byte(`{}`))
	if !errors.Is(err, ErrNotConnected) {
		t.Fatalf("expected ErrNotConnected, got %v", err)
	}
}

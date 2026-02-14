package runtime

import (
	"bufio"
	"context"
	"encoding/base64"
	"encoding/json"
	"net"
	"strings"
	"sync"
	"testing"
	"time"

	"go.uber.org/zap"
)

type fakeServerManager struct {
	mu sync.Mutex

	publishCalls    []publishCall
	publishAckCalls []publishCall
	objectSetCalls  []objectSetCall

	subscriptions map[string]func(*InboundMessage)
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

func newFakeServerManager() *fakeServerManager {
	return &fakeServerManager{
		subscriptions: make(map[string]func(*InboundMessage)),
	}
}

func (f *fakeServerManager) Publish(
	_ context.Context,
	channel string,
	event string,
	payload []byte,
	_ time.Duration,
) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.publishCalls = append(f.publishCalls, publishCall{
		channel: channel,
		event:   event,
		payload: append([]byte(nil), payload...),
	})
	return nil
}

func (f *fakeServerManager) PublishAck(
	_ context.Context,
	channel string,
	event string,
	payload []byte,
	_ time.Duration,
) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.publishAckCalls = append(f.publishAckCalls, publishCall{
		channel: channel,
		event:   event,
		payload: append([]byte(nil), payload...),
	})
	return nil
}

func (f *fakeServerManager) ObjectSet(
	_ context.Context,
	channel string,
	key string,
	value []byte,
	_ time.Duration,
) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.objectSetCalls = append(f.objectSetCalls, objectSetCall{
		channel: channel,
		key:     key,
		value:   append([]byte(nil), value...),
	})
	return nil
}

func (f *fakeServerManager) Subscribe(
	_ context.Context,
	subscriptionID string,
	_ string,
	_ string,
	onMessage func(*InboundMessage),
) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.subscriptions[subscriptionID] = onMessage
	return nil
}

func (f *fakeServerManager) Unsubscribe(subscriptionID string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	delete(f.subscriptions, subscriptionID)
}

func (f *fakeServerManager) emitFirst(msg *InboundMessage) bool {
	f.mu.Lock()
	var callback func(*InboundMessage)
	for _, cb := range f.subscriptions {
		callback = cb
		break
	}
	f.mu.Unlock()

	if callback == nil {
		return false
	}
	go callback(msg)
	return true
}

func TestServerMalformedFrameKeepsConnectionUsable(t *testing.T) {
	manager := newFakeServerManager()
	server := NewServer("/tmp/unused.sock", 2*1024*1024, manager, zap.NewNop())
	serverConn, clientConn := net.Pipe()
	defer clientConn.Close()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	done := make(chan struct{})
	go func() {
		server.handleConnection(ctx, serverConn)
		close(done)
	}()

	_, _ = clientConn.Write([]byte(`{"op":` + "\n"))

	payload := base64.StdEncoding.EncodeToString([]byte(`{"hello":"world"}`))
	_, _ = clientConn.Write([]byte(`{"op":"publish.v1","request_id":"req-1","channel":"chan","event":"evt","payload_b64":"` + payload + `"}` + "\n"))

	var ack publishAck
	readJSONLine(t, clientConn, &ack)
	if !ack.OK {
		t.Fatalf("expected ack OK after malformed frame recovery, got error %q", ack.Error)
	}

	manager.mu.Lock()
	defer manager.mu.Unlock()
	if len(manager.publishCalls) != 1 {
		t.Fatalf("expected one publish call, got %d", len(manager.publishCalls))
	}
}

func TestServerPublishRejectsInvalidBase64Payload(t *testing.T) {
	manager := newFakeServerManager()
	server := NewServer("/tmp/unused.sock", 2*1024*1024, manager, zap.NewNop())
	serverConn, clientConn := net.Pipe()
	defer clientConn.Close()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go server.handleConnection(ctx, serverConn)

	_, _ = clientConn.Write([]byte(`{"op":"publish.v1","request_id":"req-2","channel":"chan","event":"evt","payload_b64":"not-base64***"}` + "\n"))

	var ack publishAck
	readJSONLine(t, clientConn, &ack)
	if ack.OK {
		t.Fatalf("expected publish ack to fail for invalid base64")
	}
	if ack.Error != "payload_b64 must be valid base64" {
		t.Fatalf("unexpected error message: %q", ack.Error)
	}

	manager.mu.Lock()
	defer manager.mu.Unlock()
	if len(manager.publishCalls) != 0 {
		t.Fatalf("expected no publish calls, got %d", len(manager.publishCalls))
	}
}

func TestServerSubscribeAckAndMessageDelivery(t *testing.T) {
	manager := newFakeServerManager()
	server := NewServer("/tmp/unused.sock", 2*1024*1024, manager, zap.NewNop())
	serverConn, clientConn := net.Pipe()
	defer clientConn.Close()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go server.handleConnection(ctx, serverConn)

	_, _ = clientConn.Write([]byte(`{"op":"subscribe.v1","request_id":"req-sub","subscription_id":"sub-1","channel":"remote:abc:commands","event":"remote.command.v1"}` + "\n"))

	var ack subscribeAck
	readJSONLine(t, clientConn, &ack)
	if !ack.OK {
		t.Fatalf("expected subscribe ack OK, got error %q", ack.Error)
	}

	if !manager.emitFirst(&InboundMessage{
		MessageID:    "msg-1",
		Channel:      "remote:abc:commands",
		Event:        "remote.command.v1",
		Payload:      []byte(`{"command":"run"}`),
		ReceivedAtMS: 12345,
	}) {
		t.Fatalf("expected subscription callback to be registered")
	}

	var message messageEnvelope
	readJSONLine(t, clientConn, &message)

	if message.Op != opMessage {
		t.Fatalf("unexpected message op: %q", message.Op)
	}
	if message.SubscriptionID != "sub-1" {
		t.Fatalf("unexpected subscription id: %q", message.SubscriptionID)
	}
	decoded, err := base64.StdEncoding.DecodeString(message.PayloadB64)
	if err != nil {
		t.Fatalf("failed decoding payload_b64: %v", err)
	}
	if string(decoded) != `{"command":"run"}` {
		t.Fatalf("unexpected decoded payload: %q", string(decoded))
	}
}

func TestServerPublishAckUsesNagatoClientPath(t *testing.T) {
	manager := newFakeServerManager()
	server := NewServer("/tmp/unused.sock", 2*1024*1024, manager, zap.NewNop())
	serverConn, clientConn := net.Pipe()
	defer clientConn.Close()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go server.handleConnection(ctx, serverConn)

	payload := base64.StdEncoding.EncodeToString([]byte(`{"ack":true}`))
	_, _ = clientConn.Write([]byte(`{"op":"publish.ack.v1","request_id":"req-ack","channel":"remote:abc:commands","event":"remote.command.ack.v1","payload_b64":"` + payload + `"}` + "\n"))

	var ack publishAck
	readJSONLine(t, clientConn, &ack)
	if !ack.OK {
		t.Fatalf("expected publish.ack ack OK, got error %q", ack.Error)
	}

	manager.mu.Lock()
	defer manager.mu.Unlock()
	if len(manager.publishAckCalls) != 1 {
		t.Fatalf("expected one publish.ack call, got %d", len(manager.publishAckCalls))
	}
}

func TestServerObjectSetUsesObjectSetPath(t *testing.T) {
	manager := newFakeServerManager()
	server := NewServer("/tmp/unused.sock", 2*1024*1024, manager, zap.NewNop())
	serverConn, clientConn := net.Pipe()
	defer clientConn.Close()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	go server.handleConnection(ctx, serverConn)

	value := base64.StdEncoding.EncodeToString([]byte(`{"status":"running"}`))
	_, _ = clientConn.Write([]byte(`{"op":"object.set.v1","request_id":"req-object","channel":"session:abc:status","key":"coding_session_status","value_b64":"` + value + `"}` + "\n"))

	var ack publishAck
	readJSONLine(t, clientConn, &ack)
	if !ack.OK {
		t.Fatalf("expected object.set ack OK, got error %q", ack.Error)
	}

	manager.mu.Lock()
	defer manager.mu.Unlock()
	if len(manager.objectSetCalls) != 1 {
		t.Fatalf("expected one object.set call, got %d", len(manager.objectSetCalls))
	}
	if manager.objectSetCalls[0].key != "coding_session_status" {
		t.Fatalf("unexpected object key: %q", manager.objectSetCalls[0].key)
	}
}

func TestServerOversizeFrameClosesConnectionDeterministically(t *testing.T) {
	manager := newFakeServerManager()
	server := NewServer("/tmp/unused.sock", 128, manager, zap.NewNop())
	serverConn, clientConn := net.Pipe()
	defer clientConn.Close()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go server.handleConnection(ctx, serverConn)

	oversizeFrame := `{"op":"publish.v1","request_id":"too-big","channel":"chan","event":"evt","payload_b64":"` +
		strings.Repeat("A", 512) + `"}` + "\n"
	_, _ = clientConn.Write([]byte(oversizeFrame))

	time.Sleep(50 * time.Millisecond)
	_, err := clientConn.Write([]byte(`{"op":"publish.v1","request_id":"next","channel":"chan","event":"evt","payload_b64":"` + base64.StdEncoding.EncodeToString([]byte("x")) + `"}` + "\n"))
	if err == nil {
		t.Fatalf("expected connection to be closed after oversize frame")
	}
}

func readJSONLine(t *testing.T, conn net.Conn, out any) {
	t.Helper()
	if err := conn.SetReadDeadline(time.Now().Add(2 * time.Second)); err != nil {
		t.Fatalf("set read deadline: %v", err)
	}
	line, err := bufio.NewReader(conn).ReadBytes('\n')
	if err != nil {
		t.Fatalf("read line: %v", err)
	}
	if err := json.Unmarshal(line, out); err != nil {
		t.Fatalf("unmarshal line %q: %v", string(line), err)
	}
}

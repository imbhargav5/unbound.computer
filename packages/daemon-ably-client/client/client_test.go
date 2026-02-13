package client

import (
	"bufio"
	"context"
	"encoding/base64"
	"encoding/json"
	"net"
	"sync/atomic"
	"testing"
	"time"
)

type publishRequestFrame struct {
	Op        string `json:"op"`
	RequestID string `json:"request_id"`
	Channel   string `json:"channel"`
	Event     string `json:"event"`
}

type subscribeRequestFrame struct {
	Op             string `json:"op"`
	RequestID      string `json:"request_id"`
	SubscriptionID string `json:"subscription_id"`
	Channel        string `json:"channel"`
	Event          string `json:"event"`
}

func TestPublishRequestResponseCorrelation(t *testing.T) {
	serverConns := make(chan net.Conn, 1)
	client, err := newWithDial("test-socket", func(context.Context) (net.Conn, error) {
		clientConn, serverConn := net.Pipe()
		serverConns <- serverConn
		return clientConn, nil
	})
	if err != nil {
		t.Fatalf("newWithDial: %v", err)
	}
	defer client.Close()

	done := make(chan struct{})
	go func() {
		defer close(done)
		conn := <-serverConns
		defer conn.Close()

		scanner := bufio.NewScanner(conn)
		if !scanner.Scan() {
			return
		}
		var publish publishRequestFrame
		_ = json.Unmarshal(scanner.Bytes(), &publish)

		// Send mismatched ACK first; client should keep waiting.
		_ = writeJSONLine(conn, map[string]any{
			"op":         opPublishAck,
			"request_id": "mismatched",
			"ok":         true,
		})

		time.Sleep(50 * time.Millisecond)
		_ = writeJSONLine(conn, map[string]any{
			"op":         opPublishAck,
			"request_id": publish.RequestID,
			"ok":         true,
		})
	}()

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	if err := client.Connect(ctx); err != nil {
		t.Fatalf("connect: %v", err)
	}

	started := time.Now()
	if err := client.Publish(ctx, "remote:test:commands", "remote.command.v1", []byte(`{"ok":true}`), time.Second); err != nil {
		t.Fatalf("publish: %v", err)
	}
	if time.Since(started) < 50*time.Millisecond {
		t.Fatalf("publish returned before matching ack was received")
	}

	<-done
}

func TestSubscribeMessageDelivery(t *testing.T) {
	serverConns := make(chan net.Conn, 1)
	client, err := newWithDial("test-socket", func(context.Context) (net.Conn, error) {
		clientConn, serverConn := net.Pipe()
		serverConns <- serverConn
		return clientConn, nil
	})
	if err != nil {
		t.Fatalf("newWithDial: %v", err)
	}
	defer client.Close()

	go func() {
		conn := <-serverConns
		defer conn.Close()

		scanner := bufio.NewScanner(conn)
		if !scanner.Scan() {
			return
		}
		var subscribe subscribeRequestFrame
		_ = json.Unmarshal(scanner.Bytes(), &subscribe)

		_ = writeJSONLine(conn, map[string]any{
			"op":         opSubscribeAck,
			"request_id": subscribe.RequestID,
			"ok":         true,
		})
		_ = writeJSONLine(conn, map[string]any{
			"op":              opMessage,
			"subscription_id": subscribe.SubscriptionID,
			"message_id":      "message-1",
			"channel":         subscribe.Channel,
			"event":           subscribe.Event,
			"payload_b64":     base64.StdEncoding.EncodeToString([]byte(`{"command":"run"}`)),
			"received_at_ms":  time.Now().UnixMilli(),
		})
	}()

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	if err := client.Connect(ctx); err != nil {
		t.Fatalf("connect: %v", err)
	}
	if err := client.Subscribe(ctx, Subscription{
		SubscriptionID: "nagato-primary",
		Channel:        "remote:test-device:commands",
		Event:          "remote.command.v1",
	}); err != nil {
		t.Fatalf("subscribe: %v", err)
	}

	select {
	case message := <-client.Messages():
		if message.SubscriptionID != "nagato-primary" {
			t.Fatalf("unexpected subscription id: %s", message.SubscriptionID)
		}
		if string(message.Payload) != `{"command":"run"}` {
			t.Fatalf("unexpected payload: %s", string(message.Payload))
		}
	case <-ctx.Done():
		t.Fatalf("timed out waiting for subscription message")
	}
}

func TestReconnectRestoresSubscription(t *testing.T) {
	var dialCount int32
	var restored int32

	client, err := newWithDial("test-socket", func(context.Context) (net.Conn, error) {
		clientConn, serverConn := net.Pipe()
		connection := atomic.AddInt32(&dialCount, 1)
		go serveReconnectConnection(serverConn, connection, &restored)
		return clientConn, nil
	})
	if err != nil {
		t.Fatalf("newWithDial: %v", err)
	}
	defer client.Close()

	ctx, cancel := context.WithTimeout(context.Background(), 6*time.Second)
	defer cancel()
	if err := client.Connect(ctx); err != nil {
		t.Fatalf("connect: %v", err)
	}

	if err := client.Subscribe(ctx, Subscription{
		SubscriptionID: "nagato-reconnect",
		Channel:        "remote:test-device:commands",
		Event:          "remote.command.v1",
	}); err != nil {
		t.Fatalf("subscribe: %v", err)
	}

	select {
	case message := <-client.Messages():
		if message.MessageID != "reconnected-message" {
			t.Fatalf("unexpected message id: %s", message.MessageID)
		}
	case <-ctx.Done():
		t.Fatalf("timed out waiting for restored subscription message")
	}

	if atomic.LoadInt32(&restored) != 1 {
		t.Fatalf("subscription was not restored after reconnect")
	}
}

func serveReconnectConnection(conn net.Conn, connection int32, restored *int32) {
	defer conn.Close()

	scanner := bufio.NewScanner(conn)
	for scanner.Scan() {
		line := scanner.Bytes()
		var op operationEnvelope
		_ = json.Unmarshal(line, &op)
		if op.Op != opSubscribe {
			continue
		}

		var subscribe subscribeRequestFrame
		_ = json.Unmarshal(line, &subscribe)
		_ = writeJSONLine(conn, map[string]any{
			"op":         opSubscribeAck,
			"request_id": subscribe.RequestID,
			"ok":         true,
		})

		if connection == 1 {
			// Force reconnect after initial subscription registration.
			time.Sleep(50 * time.Millisecond)
			_ = conn.Close()
			return
		}

		if connection >= 2 {
			atomic.StoreInt32(restored, 1)
			_ = writeJSONLine(conn, map[string]any{
				"op":              opMessage,
				"subscription_id": subscribe.SubscriptionID,
				"message_id":      "reconnected-message",
				"channel":         subscribe.Channel,
				"event":           subscribe.Event,
				"payload_b64":     base64.StdEncoding.EncodeToString([]byte(`{"reconnected":true}`)),
				"received_at_ms":  time.Now().UnixMilli(),
			})
			return
		}
	}
}

func writeJSONLine(conn net.Conn, payload any) error {
	encoded, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	encoded = append(encoded, '\n')
	_, err = conn.Write(encoded)
	return err
}

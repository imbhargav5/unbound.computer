package runtime

import (
	"context"
	"encoding/json"
	"io"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestRequestBrokerTokenSendsDeviceID(t *testing.T) {
	socketPath := filepath.Join("/tmp", "daemon-ably-broker-test.sock")
	_ = os.Remove(socketPath)
	defer os.Remove(socketPath)

	listener, err := net.Listen("unix", socketPath)
	if err != nil {
		t.Fatalf("listen unix socket: %v", err)
	}
	defer listener.Close()

	received := make(chan brokerTokenRequest, 1)
	serverErr := make(chan error, 1)

	go func() {
		conn, err := listener.Accept()
		if err != nil {
			serverErr <- err
			return
		}
		defer conn.Close()

		raw, err := io.ReadAll(conn)
		if err != nil {
			serverErr <- err
			return
		}

		var req brokerTokenRequest
		if err := json.Unmarshal(raw, &req); err != nil {
			serverErr <- err
			return
		}
		received <- req

		tokenDetails, err := json.Marshal(brokerTokenDetails{
			Token:      "token-123",
			ClientID:   "user-123",
			Expires:    123,
			Issued:     122,
			Capability: "{}",
		})
		if err != nil {
			serverErr <- err
			return
		}

		resp, err := json.Marshal(brokerTokenResponse{
			OK:           true,
			TokenDetails: tokenDetails,
		})
		if err != nil {
			serverErr <- err
			return
		}

		if _, err := conn.Write(resp); err != nil {
			serverErr <- err
			return
		}
		serverErr <- nil
	}()

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	details, err := requestBrokerToken(ctx, socketPath, "broker-token", "device-123", "daemon_falco")
	if err != nil {
		t.Fatalf("requestBrokerToken returned error: %v", err)
	}
	if details == nil || details.Token != "token-123" {
		t.Fatalf("unexpected token details: %+v", details)
	}

	select {
	case req := <-received:
		if req.BrokerToken != "broker-token" {
			t.Fatalf("unexpected broker token: %q", req.BrokerToken)
		}
		if req.Audience != "daemon_falco" {
			t.Fatalf("unexpected audience: %q", req.Audience)
		}
		if req.DeviceID != "device-123" {
			t.Fatalf("unexpected device_id: %q", req.DeviceID)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for broker request payload")
	}

	select {
	case err := <-serverErr:
		if err != nil {
			t.Fatalf("server error: %v", err)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("timed out waiting for broker server completion")
	}
}

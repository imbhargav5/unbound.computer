package runtime

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"

	"github.com/ably/ably-go/ably"
)

type brokerTokenRequest struct {
	BrokerToken string `json:"broker_token"`
	Audience    string `json:"audience"`
	DeviceID    string `json:"device_id"`
}

type brokerTokenResponse struct {
	OK           bool            `json:"ok"`
	TokenDetails json.RawMessage `json:"token_details"`
	Error        string          `json:"error"`
}

type brokerTokenDetails struct {
	Token      string `json:"token"`
	Expires    int64  `json:"expires"`
	ClientID   string `json:"clientId"`
	Issued     int64  `json:"issued"`
	Capability string `json:"capability"`
}

func requestBrokerToken(
	ctx context.Context,
	socketPath string,
	brokerToken string,
	deviceID string,
	audience string,
) (*ably.TokenDetails, error) {
	requestPayload, err := json.Marshal(brokerTokenRequest{
		BrokerToken: brokerToken,
		Audience:    audience,
		DeviceID:    deviceID,
	})
	if err != nil {
		return nil, fmt.Errorf("failed to serialize broker request: %w", err)
	}

	dialer := net.Dialer{}
	conn, err := dialer.DialContext(ctx, "unix", socketPath)
	if err != nil {
		return nil, fmt.Errorf("failed to connect to Ably broker socket: %w", err)
	}
	defer conn.Close()

	if deadline, ok := ctx.Deadline(); ok {
		_ = conn.SetDeadline(deadline)
	}

	if _, err := conn.Write(requestPayload); err != nil {
		return nil, fmt.Errorf("failed to write broker request: %w", err)
	}
	if unixConn, ok := conn.(*net.UnixConn); ok {
		_ = unixConn.CloseWrite()
	}

	responsePayload, err := io.ReadAll(conn)
	if err != nil {
		return nil, fmt.Errorf("failed to read broker response: %w", err)
	}

	var response brokerTokenResponse
	if err := json.Unmarshal(responsePayload, &response); err != nil {
		return nil, fmt.Errorf("invalid broker response: %w", err)
	}
	if !response.OK {
		if response.Error == "" {
			return nil, errors.New("broker rejected token request")
		}
		return nil, fmt.Errorf("broker rejected token request: %s", response.Error)
	}

	var tokenDetails brokerTokenDetails
	if err := json.Unmarshal(response.TokenDetails, &tokenDetails); err != nil {
		return nil, fmt.Errorf("invalid broker token details payload: %w", err)
	}
	if tokenDetails.Token == "" {
		return nil, errors.New("broker response missing token")
	}

	return &ably.TokenDetails{
		Token:      tokenDetails.Token,
		Expires:    tokenDetails.Expires,
		ClientID:   tokenDetails.ClientID,
		Issued:     tokenDetails.Issued,
		Capability: tokenDetails.Capability,
	}, nil
}

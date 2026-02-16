package runtime

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"go.uber.org/zap"
)

type PresenceDOClient struct {
	endpoint   string
	authToken  string
	httpClient *http.Client
	logger     *zap.Logger
}

func NewPresenceDOClient(endpoint string, authToken string, timeout time.Duration, logger *zap.Logger) *PresenceDOClient {
	if logger == nil {
		logger = zap.NewNop()
	}
	client := &http.Client{}
	if timeout > 0 {
		client.Timeout = timeout
	}
	return &PresenceDOClient{
		endpoint:   strings.TrimSpace(endpoint),
		authToken:  strings.TrimSpace(authToken),
		httpClient: client,
		logger:     logger,
	}
}

func (c *PresenceDOClient) Publish(ctx context.Context, payload PresencePayload) error {
	if c == nil || c.endpoint == "" {
		return fmt.Errorf("presence DO endpoint is not configured")
	}

	body, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("marshal presence payload: %w", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.endpoint, bytes.NewReader(body))
	if err != nil {
		return fmt.Errorf("create DO request: %w", err)
	}

	req.Header.Set("Content-Type", "application/json")
	if c.authToken != "" {
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", c.authToken))
	}

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return fmt.Errorf("presence DO request failed: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		bodyBytes, _ := io.ReadAll(io.LimitReader(resp.Body, 4096))
		return fmt.Errorf("presence DO request failed: status=%d body=%s", resp.StatusCode, strings.TrimSpace(string(bodyBytes)))
	}

	return nil
}

package runtime

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/url"
	"sync"
	"time"

	"github.com/ably/ably-go/ably"
	"github.com/google/uuid"
	"go.uber.org/zap"

	ablyconfig "github.com/unbound-computer/daemon-ably/config"
)

const (
	audienceFalco  = "daemon_falco"
	audienceNagato = "daemon_nagato"
	statusOnline   = "online"
	statusOffline  = "offline"
)

type InboundMessage struct {
	MessageID    string
	Channel      string
	Event        string
	Payload      []byte
	ReceivedAtMS int64
}

type subscription struct {
	id        string
	channel   string
	event     string
	onMessage func(*InboundMessage)
	unsub     func()
}

type PresencePayload struct {
	SchemaVersion int    `json:"schema_version"`
	UserID        string `json:"user_id"`
	DeviceID      string `json:"device_id"`
	Status        string `json:"status"`
	Source        string `json:"source"`
	SentAtMS      int64  `json:"sent_at_ms"`
}

type Manager struct {
	cfg    *ablyconfig.Config
	logger *zap.Logger

	falcoClient  *ably.Realtime
	falcoREST    *ably.REST
	nagatoClient *ably.Realtime
	server       *Server

	mu            sync.Mutex
	subs          map[string]*subscription
	closed        bool
	heartbeatDone chan struct{}

	// Test hooks.
	publishWithClientOverride func(
		ctx context.Context,
		client *ably.Realtime,
		channel string,
		event string,
		payload []byte,
		timeout time.Duration,
	) error
	attachSubscriptionOverride func(ctx context.Context, sub *subscription) error
	objectSetOverride          func(ctx context.Context, channel string, key string, value []byte, timeout time.Duration) error
}

func NewManager(cfg *ablyconfig.Config, logger *zap.Logger) (*Manager, error) {
	if logger == nil {
		logger = zap.NewNop()
	}

	falcoClient, err := newRealtimeClient(cfg, audienceFalco, cfg.BrokerFalcoToken, logger.Named("ably-falco"))
	if err != nil {
		return nil, err
	}
	falcoREST, err := newRESTClient(cfg, audienceFalco, cfg.BrokerFalcoToken, logger.Named("ably-falco-rest"))
	if err != nil {
		falcoClient.Close()
		return nil, err
	}

	nagatoClient, err := newRealtimeClient(cfg, audienceNagato, cfg.BrokerNagatoToken, logger.Named("ably-nagato"))
	if err != nil {
		falcoClient.Close()
		return nil, err
	}

	manager := &Manager{
		cfg:           cfg,
		logger:        logger,
		falcoClient:   falcoClient,
		falcoREST:     falcoREST,
		nagatoClient:  nagatoClient,
		subs:          make(map[string]*subscription),
		heartbeatDone: make(chan struct{}),
	}
	manager.server = NewServer(cfg.SocketPath, cfg.MaxFrameBytes, manager, logger.Named("ipc"))

	manager.nagatoClient.Connection.OnAll(func(change ably.ConnectionStateChange) {
		switch change.Current {
		case ably.ConnectionStateConnected:
			manager.logger.Info("nagato Ably client connected", zap.String("connection_id", manager.nagatoClient.Connection.ID()))
			go manager.restoreSubscriptions()
		case ably.ConnectionStateDisconnected:
			manager.logger.Warn("nagato Ably client disconnected")
		case ably.ConnectionStateSuspended:
			manager.logger.Warn("nagato Ably client suspended")
		case ably.ConnectionStateFailed:
			manager.logger.Error("nagato Ably client failed", zap.Error(change.Reason))
		}
	})

	manager.falcoClient.Connection.OnAll(func(change ably.ConnectionStateChange) {
		switch change.Current {
		case ably.ConnectionStateConnected:
			manager.logger.Info("falco Ably client connected", zap.String("connection_id", manager.falcoClient.Connection.ID()))
		case ably.ConnectionStateDisconnected:
			manager.logger.Warn("falco Ably client disconnected")
		case ably.ConnectionStateSuspended:
			manager.logger.Warn("falco Ably client suspended")
		case ably.ConnectionStateFailed:
			manager.logger.Error("falco Ably client failed", zap.Error(change.Reason))
		}
	})

	return manager, nil
}

func (m *Manager) Start(ctx context.Context) error {
	if err := connectRealtime(ctx, m.falcoClient, m.logger.Named("falco-connect")); err != nil {
		return fmt.Errorf("failed connecting falco Ably client: %w", err)
	}
	if err := connectRealtime(ctx, m.nagatoClient, m.logger.Named("nagato-connect")); err != nil {
		return fmt.Errorf("failed connecting nagato Ably client: %w", err)
	}

	if err := m.server.Start(ctx); err != nil {
		return err
	}

	if err := m.publishPresence(ctx, statusOnline); err != nil {
		m.logger.Warn("failed to publish initial online heartbeat", zap.Error(err))
	}

	go m.heartbeatLoop()
	return nil
}

func (m *Manager) Close() error {
	m.mu.Lock()
	if m.closed {
		m.mu.Unlock()
		return nil
	}
	m.closed = true

	subs := make([]*subscription, 0, len(m.subs))
	for _, sub := range m.subs {
		subs = append(subs, sub)
	}
	m.subs = make(map[string]*subscription)
	m.mu.Unlock()

	ctx, cancel := context.WithTimeout(context.Background(), m.cfg.ShutdownTimeout)
	_ = m.publishPresence(ctx, statusOffline)
	cancel()

	for _, sub := range subs {
		if sub.unsub != nil {
			sub.unsub()
		}
	}

	if m.server != nil {
		_ = m.server.Close()
	}

	if m.nagatoClient != nil {
		m.nagatoClient.Close()
	}
	if m.falcoClient != nil {
		m.falcoClient.Close()
	}

	select {
	case <-m.heartbeatDone:
	case <-time.After(500 * time.Millisecond):
	}

	return nil
}

func (m *Manager) Publish(ctx context.Context, channel string, event string, payload []byte, timeout time.Duration) error {
	if m.publishWithClientOverride != nil {
		return m.publishWithClientOverride(ctx, m.falcoClient, channel, event, payload, timeout)
	}
	return m.publishWithClient(ctx, m.falcoClient, channel, event, payload, timeout)
}

func (m *Manager) PublishAck(ctx context.Context, channel string, event string, payload []byte, timeout time.Duration) error {
	if m.publishWithClientOverride != nil {
		return m.publishWithClientOverride(ctx, m.nagatoClient, channel, event, payload, timeout)
	}
	return m.publishWithClient(ctx, m.nagatoClient, channel, event, payload, timeout)
}

func (m *Manager) ObjectSet(
	ctx context.Context,
	channel string,
	key string,
	value []byte,
	timeout time.Duration,
) error {
	if m.objectSetOverride != nil {
		return m.objectSetOverride(ctx, channel, key, value, timeout)
	}
	if channel == "" {
		return fmt.Errorf("channel is required")
	}
	if key == "" {
		return fmt.Errorf("key is required")
	}
	if timeout <= 0 {
		timeout = m.cfg.PublishTimeout
	}

	var decodedValue any
	if len(value) == 0 {
		decodedValue = nil
	} else if err := json.Unmarshal(value, &decodedValue); err != nil {
		return fmt.Errorf("object value must be valid JSON: %w", err)
	}

	reqCtx := ctx
	if reqCtx == nil {
		reqCtx = context.Background()
	}
	if _, ok := reqCtx.Deadline(); !ok {
		var cancel context.CancelFunc
		reqCtx, cancel = context.WithTimeout(reqCtx, timeout)
		defer cancel()
	}

	path := fmt.Sprintf("/channels/%s/object", url.PathEscape(channel))
	body := map[string]any{
		"name":  key,
		"op":    "set",
		"value": decodedValue,
	}

	response, err := m.falcoREST.Request(
		"POST",
		path,
		ably.RequestWithBody(body),
	).Pages(reqCtx)
	if err != nil {
		return fmt.Errorf("object set request failed: %w", err)
	}
	if !response.Success() {
		message := response.ErrorMessage()
		if message == "" {
			message = "object set request failed"
		}
		return fmt.Errorf(
			"object set request failed: status=%d code=%d message=%s",
			response.StatusCode(),
			response.ErrorCode(),
			message,
		)
	}
	return nil
}

func (m *Manager) Subscribe(
	ctx context.Context,
	subscriptionID string,
	channel string,
	event string,
	onMessage func(*InboundMessage),
) error {
	if subscriptionID == "" {
		return fmt.Errorf("subscription id is required")
	}
	if channel == "" {
		return fmt.Errorf("subscription channel is required")
	}
	if onMessage == nil {
		return fmt.Errorf("subscription callback is required")
	}

	m.mu.Lock()
	if m.closed {
		m.mu.Unlock()
		return errors.New("manager closed")
	}

	existing := m.subs[subscriptionID]
	if existing != nil && existing.unsub != nil {
		existing.unsub()
	}

	sub := &subscription{
		id:        subscriptionID,
		channel:   channel,
		event:     event,
		onMessage: onMessage,
	}
	m.subs[subscriptionID] = sub
	m.mu.Unlock()

	ctxWithTimeout, cancel := context.WithTimeout(ctx, m.cfg.PublishTimeout)
	defer cancel()

	if err := m.attachSubscription(ctxWithTimeout, sub); err != nil {
		m.mu.Lock()
		delete(m.subs, subscriptionID)
		m.mu.Unlock()
		return err
	}

	return nil
}

func (m *Manager) Unsubscribe(subscriptionID string) {
	if subscriptionID == "" {
		return
	}

	m.mu.Lock()
	sub := m.subs[subscriptionID]
	delete(m.subs, subscriptionID)
	m.mu.Unlock()

	if sub != nil && sub.unsub != nil {
		sub.unsub()
	}
}

func (m *Manager) publishWithClient(
	ctx context.Context,
	client *ably.Realtime,
	channel string,
	event string,
	payload []byte,
	timeout time.Duration,
) error {
	if channel == "" {
		return fmt.Errorf("channel is required")
	}
	if event == "" {
		return fmt.Errorf("event is required")
	}
	if timeout <= 0 {
		timeout = m.cfg.PublishTimeout
	}

	pubCtx := ctx
	if pubCtx == nil {
		pubCtx = context.Background()
	}
	if _, ok := pubCtx.Deadline(); !ok {
		var cancel context.CancelFunc
		pubCtx, cancel = context.WithTimeout(pubCtx, timeout)
		defer cancel()
	}

	ch := client.Channels.Get(channel)
	return ch.Publish(pubCtx, event, payload)
}

func (m *Manager) attachSubscription(ctx context.Context, sub *subscription) error {
	if m.attachSubscriptionOverride != nil {
		return m.attachSubscriptionOverride(ctx, sub)
	}

	channel := m.nagatoClient.Channels.Get(sub.channel)
	if err := channel.Attach(ctx); err != nil {
		return fmt.Errorf("failed attaching channel %s: %w", sub.channel, err)
	}

	handler := func(message *ably.Message) {
		payload, err := payloadFromAblyMessage(message.Data)
		if err != nil {
			m.logger.Warn(
				"failed decoding subscribed message payload",
				zap.String("subscription_id", sub.id),
				zap.String("channel", sub.channel),
				zap.String("event", message.Name),
				zap.Error(err),
			)
			return
		}

		messageID := message.ID
		if messageID == "" {
			messageID = uuid.NewString()
		}

		receivedAtMS := message.Timestamp
		if receivedAtMS <= 0 {
			receivedAtMS = time.Now().UnixMilli()
		}

		sub.onMessage(&InboundMessage{
			MessageID:    messageID,
			Channel:      sub.channel,
			Event:        message.Name,
			Payload:      payload,
			ReceivedAtMS: receivedAtMS,
		})
	}

	var (
		unsub func()
		err   error
	)
	if sub.event == "" {
		unsub, err = channel.SubscribeAll(ctx, handler)
	} else {
		unsub, err = channel.Subscribe(ctx, sub.event, handler)
	}
	if err != nil {
		return fmt.Errorf("failed subscribing on channel %s: %w", sub.channel, err)
	}

	m.mu.Lock()
	defer m.mu.Unlock()
	current := m.subs[sub.id]
	if current == nil {
		unsub()
		return nil
	}
	if current.unsub != nil {
		current.unsub()
	}
	current.unsub = unsub
	return nil
}

func (m *Manager) restoreSubscriptions() {
	m.mu.Lock()
	if m.closed {
		m.mu.Unlock()
		return
	}

	subs := make([]*subscription, 0, len(m.subs))
	for _, sub := range m.subs {
		subs = append(subs, sub)
	}
	m.mu.Unlock()

	for _, sub := range subs {
		ctx, cancel := context.WithTimeout(context.Background(), m.cfg.PublishTimeout)
		err := m.attachSubscription(ctx, sub)
		cancel()
		if err != nil {
			m.logger.Warn(
				"failed restoring subscription after reconnect",
				zap.String("subscription_id", sub.id),
				zap.String("channel", sub.channel),
				zap.String("event", sub.event),
				zap.Error(err),
			)
		}
	}
}

func (m *Manager) heartbeatLoop() {
	defer close(m.heartbeatDone)

	ticker := time.NewTicker(m.cfg.HeartbeatInterval)
	defer ticker.Stop()

	for {
		m.mu.Lock()
		closed := m.closed
		m.mu.Unlock()
		if closed {
			return
		}

		select {
		case <-ticker.C:
			ctx, cancel := context.WithTimeout(context.Background(), m.cfg.PublishTimeout)
			if err := m.publishPresence(ctx, statusOnline); err != nil {
				m.logger.Warn("failed publishing periodic heartbeat", zap.Error(err))
			}
			cancel()
		default:
			time.Sleep(100 * time.Millisecond)
		}
	}
}

func (m *Manager) publishPresence(ctx context.Context, status string) error {
	payload := PresencePayload{
		SchemaVersion: 1,
		UserID:        m.cfg.UserID,
		DeviceID:      m.cfg.DeviceID,
		Status:        status,
		Source:        m.cfg.PresenceSource,
		SentAtMS:      time.Now().UnixMilli(),
	}
	encoded, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	return m.Publish(ctx, m.cfg.PresenceChannel, m.cfg.PresenceEvent, encoded, m.cfg.PublishTimeout)
}

func connectRealtime(ctx context.Context, client *ably.Realtime, logger *zap.Logger) error {
	connected := make(chan struct{}, 1)
	var connErr error

	client.Connection.OnAll(func(change ably.ConnectionStateChange) {
		switch change.Current {
		case ably.ConnectionStateConnected:
			select {
			case connected <- struct{}{}:
			default:
			}
		case ably.ConnectionStateFailed:
			connErr = change.Reason
			select {
			case connected <- struct{}{}:
			default:
			}
		}
	})

	client.Connect()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-connected:
		if connErr != nil {
			return connErr
		}
		logger.Info("connected to Ably")
		return nil
	}
}

func newRealtimeClient(
	cfg *ablyconfig.Config,
	audience string,
	brokerToken string,
	logger *zap.Logger,
) (*ably.Realtime, error) {
	client, err := ably.NewRealtime(
		ably.WithClientID(cfg.DeviceID),
		ably.WithAuthCallback(func(ctx context.Context, _ ably.TokenParams) (ably.Tokener, error) {
			logger.Debug("requesting token from local broker", zap.String("audience", audience))
			return requestBrokerToken(ctx, cfg.BrokerSocketPath, brokerToken, cfg.DeviceID, audience)
		}),
		ably.WithAutoConnect(false),
	)
	if err != nil {
		return nil, err
	}
	return client, nil
}

func newRESTClient(
	cfg *ablyconfig.Config,
	audience string,
	brokerToken string,
	logger *zap.Logger,
) (*ably.REST, error) {
	client, err := ably.NewREST(
		ably.WithClientID(cfg.DeviceID),
		ably.WithAuthCallback(func(ctx context.Context, _ ably.TokenParams) (ably.Tokener, error) {
			logger.Debug("requesting token from local broker", zap.String("audience", audience))
			return requestBrokerToken(ctx, cfg.BrokerSocketPath, brokerToken, cfg.DeviceID, audience)
		}),
	)
	if err != nil {
		return nil, err
	}
	return client, nil
}

func payloadFromAblyMessage(data any) ([]byte, error) {
	switch typed := data.(type) {
	case nil:
		return nil, nil
	case []byte:
		return typed, nil
	case string:
		return []byte(typed), nil
	default:
		encoded, err := json.Marshal(typed)
		if err != nil {
			return nil, fmt.Errorf("marshal payload: %w", err)
		}
		return encoded, nil
	}
}

func encodePayload(payload []byte) string {
	if len(payload) == 0 {
		return ""
	}
	return base64.StdEncoding.EncodeToString(payload)
}

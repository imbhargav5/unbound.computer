package runtime

import (
	"bufio"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"sync"
	"time"

	"github.com/google/uuid"
	"go.uber.org/zap"

	ablyconfig "github.com/unbound-computer/daemon-ably/config"
)

const (
	opPublishRequest    = "publish.v1"
	opPublishAckRequest = "publish.ack.v1"
	opObjectSetRequest  = "object.set.v1"
	opPublishAck        = "publish.ack.v1"
	opSubscribeRequest  = "subscribe.v1"
	opSubscribeAck      = "subscribe.ack.v1"
	opMessage           = "message.v1"
)

type operationEnvelope struct {
	Op string `json:"op"`
}

type requestAck struct {
	RequestID string `json:"request_id"`
	OK        bool   `json:"ok"`
	Error     string `json:"error,omitempty"`
}

type publishRequest struct {
	Op         string `json:"op"`
	RequestID  string `json:"request_id"`
	Channel    string `json:"channel"`
	Event      string `json:"event"`
	PayloadB64 string `json:"payload_b64"`
	TimeoutMS  int64  `json:"timeout_ms,omitempty"`
}

type objectSetRequest struct {
	Op        string `json:"op"`
	RequestID string `json:"request_id"`
	Channel   string `json:"channel"`
	Key       string `json:"key"`
	ValueB64  string `json:"value_b64"`
	TimeoutMS int64  `json:"timeout_ms,omitempty"`
}

type publishAck struct {
	Op string `json:"op"`
	requestAck
}

type subscribeRequest struct {
	Op             string `json:"op"`
	RequestID      string `json:"request_id"`
	SubscriptionID string `json:"subscription_id"`
	Channel        string `json:"channel"`
	Event          string `json:"event,omitempty"`
}

type subscribeAck struct {
	Op string `json:"op"`
	requestAck
}

type messageEnvelope struct {
	Op             string `json:"op"`
	SubscriptionID string `json:"subscription_id"`
	MessageID      string `json:"message_id"`
	Channel        string `json:"channel"`
	Event          string `json:"event"`
	PayloadB64     string `json:"payload_b64"`
	ReceivedAtMS   int64  `json:"received_at_ms"`
}

type serverManager interface {
	Publish(ctx context.Context, channel string, event string, payload []byte, timeout time.Duration) error
	PublishAck(ctx context.Context, channel string, event string, payload []byte, timeout time.Duration) error
	ObjectSet(ctx context.Context, channel string, key string, value []byte, timeout time.Duration) error
	Subscribe(
		ctx context.Context,
		subscriptionID string,
		channel string,
		event string,
		onMessage func(*InboundMessage),
	) error
	Unsubscribe(subscriptionID string)
}

type Server struct {
	socketPath    string
	maxFrameBytes int
	manager       serverManager
	logger        *zap.Logger

	mu       sync.Mutex
	listener net.Listener
	closed   bool
	wg       sync.WaitGroup
}

func NewServer(socketPath string, maxFrameBytes int, manager serverManager, logger *zap.Logger) *Server {
	if logger == nil {
		logger = zap.NewNop()
	}
	if maxFrameBytes <= 0 {
		maxFrameBytes = ablyconfig.DefaultMaxFrameBytes
	}
	return &Server{
		socketPath:    socketPath,
		maxFrameBytes: maxFrameBytes,
		manager:       manager,
		logger:        logger,
	}
}

func (s *Server) Start(ctx context.Context) error {
	if err := os.Remove(s.socketPath); err != nil && !os.IsNotExist(err) {
		return fmt.Errorf("failed removing stale socket: %w", err)
	}

	listener, err := net.Listen("unix", s.socketPath)
	if err != nil {
		return fmt.Errorf("failed listening on %s: %w", s.socketPath, err)
	}
	if err := os.Chmod(s.socketPath, 0o600); err != nil {
		s.logger.Warn("failed to set socket permissions", zap.String("socket", s.socketPath), zap.Error(err))
	}

	s.mu.Lock()
	s.listener = listener
	s.mu.Unlock()

	s.logger.Info("daemon-ably IPC server listening", zap.String("socket", s.socketPath))
	go s.acceptLoop(ctx)
	return nil
}

func (s *Server) Close() error {
	s.mu.Lock()
	if s.closed {
		s.mu.Unlock()
		return nil
	}
	s.closed = true
	listener := s.listener
	s.mu.Unlock()

	if listener != nil {
		_ = listener.Close()
	}
	s.wg.Wait()
	_ = os.Remove(s.socketPath)
	return nil
}

func (s *Server) acceptLoop(ctx context.Context) {
	for {
		s.mu.Lock()
		listener := s.listener
		closed := s.closed
		s.mu.Unlock()
		if closed {
			return
		}

		conn, err := listener.Accept()
		if err != nil {
			if errors.Is(err, net.ErrClosed) {
				return
			}
			s.logger.Warn("failed accepting IPC connection", zap.Error(err))
			continue
		}

		s.wg.Add(1)
		go func() {
			defer s.wg.Done()
			s.handleConnection(ctx, conn)
		}()
	}
}

func (s *Server) handleConnection(ctx context.Context, conn net.Conn) {
	defer conn.Close()
	state := &serverConn{
		id:            uuid.NewString(),
		conn:          conn,
		logger:        s.logger.Named("conn"),
		subscriptions: make(map[string]struct{}),
	}

	s.logger.Info("IPC client connected", zap.String("connection_id", state.id))
	defer func() {
		state.mu.Lock()
		subscriptions := make([]string, 0, len(state.subscriptions))
		for key := range state.subscriptions {
			subscriptions = append(subscriptions, key)
		}
		state.closed = true
		state.mu.Unlock()

		for _, key := range subscriptions {
			s.manager.Unsubscribe(key)
		}

		s.logger.Info("IPC client disconnected", zap.String("connection_id", state.id))
	}()

	scanner := bufio.NewScanner(conn)
	initialBufferCap := 64 * 1024
	if s.maxFrameBytes < initialBufferCap {
		initialBufferCap = s.maxFrameBytes
	}
	scanner.Buffer(make([]byte, 0, initialBufferCap), s.maxFrameBytes)

	for scanner.Scan() {
		select {
		case <-ctx.Done():
			return
		default:
		}

		line := scanner.Bytes()
		if err := s.processLine(state, line); err != nil {
			s.logger.Warn(
				"failed processing IPC frame",
				zap.String("connection_id", state.id),
				zap.Error(err),
			)
		}
	}

	if err := scanner.Err(); err != nil {
		if errors.Is(err, bufio.ErrTooLong) {
			s.logger.Warn(
				"IPC connection frame exceeded max size",
				zap.String("connection_id", state.id),
				zap.Int("max_frame_bytes", s.maxFrameBytes),
			)
			return
		}
		s.logger.Warn("IPC connection read error", zap.String("connection_id", state.id), zap.Error(err))
	}
}

func (s *Server) processLine(state *serverConn, line []byte) error {
	var envelope operationEnvelope
	if err := json.Unmarshal(line, &envelope); err != nil {
		return fmt.Errorf("invalid operation envelope: %w", err)
	}

	switch envelope.Op {
	case opPublishRequest:
		var request publishRequest
		if err := json.Unmarshal(line, &request); err != nil {
			return fmt.Errorf("invalid publish request: %w", err)
		}
		return s.handlePublishRequest(state, request, false)
	case opPublishAckRequest:
		var request publishRequest
		if err := json.Unmarshal(line, &request); err != nil {
			return fmt.Errorf("invalid publish ack request: %w", err)
		}
		return s.handlePublishRequest(state, request, true)
	case opObjectSetRequest:
		var request objectSetRequest
		if err := json.Unmarshal(line, &request); err != nil {
			return fmt.Errorf("invalid object set request: %w", err)
		}
		return s.handleObjectSetRequest(state, request)
	case opSubscribeRequest:
		var request subscribeRequest
		if err := json.Unmarshal(line, &request); err != nil {
			return fmt.Errorf("invalid subscribe request: %w", err)
		}
		return s.handleSubscribeRequest(state, request)
	default:
		return fmt.Errorf("unknown operation: %s", envelope.Op)
	}
}

func (s *Server) handlePublishRequest(state *serverConn, request publishRequest, useNagatoClient bool) error {
	ack := publishAck{
		Op: opPublishAck,
		requestAck: requestAck{
			RequestID: request.RequestID,
			OK:        true,
		},
	}

	if request.RequestID == "" {
		ack.OK = false
		ack.Error = "request_id is required"
		return state.writeJSON(ack)
	}
	if request.Channel == "" {
		ack.OK = false
		ack.Error = "channel is required"
		return state.writeJSON(ack)
	}
	if request.Event == "" {
		ack.OK = false
		ack.Error = "event is required"
		return state.writeJSON(ack)
	}

	payload, err := base64.StdEncoding.DecodeString(request.PayloadB64)
	if err != nil {
		ack.OK = false
		ack.Error = "payload_b64 must be valid base64"
		return state.writeJSON(ack)
	}

	timeout := time.Duration(request.TimeoutMS) * time.Millisecond
	ctx := context.Background()
	if request.TimeoutMS > 0 {
		timeoutCtx, cancel := context.WithTimeout(ctx, timeout)
		defer cancel()
		ctx = timeoutCtx
	}

	if useNagatoClient {
		err = s.manager.PublishAck(ctx, request.Channel, request.Event, payload, timeout)
	} else {
		err = s.manager.Publish(ctx, request.Channel, request.Event, payload, timeout)
	}
	if err != nil {
		ack.OK = false
		ack.Error = err.Error()
	}

	return state.writeJSON(ack)
}

func (s *Server) handleObjectSetRequest(state *serverConn, request objectSetRequest) error {
	ack := publishAck{
		Op: opPublishAck,
		requestAck: requestAck{
			RequestID: request.RequestID,
			OK:        true,
		},
	}

	if request.RequestID == "" {
		ack.OK = false
		ack.Error = "request_id is required"
		return state.writeJSON(ack)
	}
	if request.Channel == "" {
		ack.OK = false
		ack.Error = "channel is required"
		return state.writeJSON(ack)
	}
	if request.Key == "" {
		ack.OK = false
		ack.Error = "key is required"
		return state.writeJSON(ack)
	}

	value, err := base64.StdEncoding.DecodeString(request.ValueB64)
	if err != nil {
		ack.OK = false
		ack.Error = "value_b64 must be valid base64"
		return state.writeJSON(ack)
	}

	timeout := time.Duration(request.TimeoutMS) * time.Millisecond
	ctx := context.Background()
	if request.TimeoutMS > 0 {
		timeoutCtx, cancel := context.WithTimeout(ctx, timeout)
		defer cancel()
		ctx = timeoutCtx
	}

	if err := s.manager.ObjectSet(ctx, request.Channel, request.Key, value, timeout); err != nil {
		ack.OK = false
		ack.Error = err.Error()
	}

	return state.writeJSON(ack)
}

func (s *Server) handleSubscribeRequest(state *serverConn, request subscribeRequest) error {
	ack := subscribeAck{
		Op: opSubscribeAck,
		requestAck: requestAck{
			RequestID: request.RequestID,
			OK:        true,
		},
	}

	if request.RequestID == "" {
		ack.OK = false
		ack.Error = "request_id is required"
		return state.writeJSON(ack)
	}
	if request.SubscriptionID == "" {
		ack.OK = false
		ack.Error = "subscription_id is required"
		return state.writeJSON(ack)
	}
	if request.Channel == "" {
		ack.OK = false
		ack.Error = "channel is required"
		return state.writeJSON(ack)
	}

	subscriptionKey := fmt.Sprintf("%s:%s", state.id, request.SubscriptionID)
	err := s.manager.Subscribe(
		context.Background(),
		subscriptionKey,
		request.Channel,
		request.Event,
		func(msg *InboundMessage) {
			out := messageEnvelope{
				Op:             opMessage,
				SubscriptionID: request.SubscriptionID,
				MessageID:      msg.MessageID,
				Channel:        msg.Channel,
				Event:          msg.Event,
				PayloadB64:     encodePayload(msg.Payload),
				ReceivedAtMS:   msg.ReceivedAtMS,
			}
			if err := state.writeJSON(out); err != nil {
				s.logger.Warn(
					"failed writing subscription message to IPC connection",
					zap.String("connection_id", state.id),
					zap.String("subscription_id", request.SubscriptionID),
					zap.Error(err),
				)
			}
		},
	)
	if err != nil {
		ack.OK = false
		ack.Error = err.Error()
	} else {
		state.mu.Lock()
		state.subscriptions[subscriptionKey] = struct{}{}
		state.mu.Unlock()
	}

	return state.writeJSON(ack)
}

type serverConn struct {
	id     string
	conn   net.Conn
	logger *zap.Logger

	mu            sync.Mutex
	closed        bool
	subscriptions map[string]struct{}
}

func (s *serverConn) writeJSON(payload any) error {
	encoded, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	encoded = append(encoded, '\n')

	s.mu.Lock()
	defer s.mu.Unlock()
	if s.closed {
		return errors.New("connection closed")
	}
	_, err = s.conn.Write(encoded)
	return err
}

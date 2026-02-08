// Package server provides the Unix domain socket server for Falco.
//
// Falco listens on a socket and receives side-effects from the daemon.
// For each side-effect, it publishes to Ably and sends back an acknowledgment.
package server

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"os"
	"sync"

	"github.com/google/uuid"
	"go.uber.org/zap"

	"github.com/unbound-computer/daemon-falco/protocol"
	"github.com/unbound-computer/daemon-falco/publisher"
	"github.com/unbound-computer/daemon-falco/sideeffect"
)

const (
	ReadBufSize = 4096
)

var (
	ErrClosed = errors.New("server closed")
)

// Server listens for side-effects from the daemon and publishes them to Ably.
type Server struct {
	socketPath string
	publisher  *publisher.Publisher
	logger     *zap.Logger

	listener net.Listener

	mu       sync.Mutex
	closed   bool
	closedCh chan struct{}
	wg       sync.WaitGroup
}

// New creates a new server.
func New(socketPath string, pub *publisher.Publisher, logger *zap.Logger) *Server {
	if logger == nil {
		logger = zap.NewNop()
	}
	return &Server{
		socketPath: socketPath,
		publisher:  pub,
		logger:     logger,
		closedCh:   make(chan struct{}),
	}
}

// Start starts the server and listens for connections.
func (s *Server) Start(ctx context.Context) error {
	s.mu.Lock()
	if s.closed {
		s.mu.Unlock()
		return ErrClosed
	}
	s.mu.Unlock()

	// Remove existing socket file if it exists
	if err := os.Remove(s.socketPath); err != nil && !os.IsNotExist(err) {
		return err
	}

	s.logger.Info("starting server",
		zap.String("socket", s.socketPath),
	)

	listener, err := net.Listen("unix", s.socketPath)
	if err != nil {
		return err
	}

	s.mu.Lock()
	s.listener = listener
	s.mu.Unlock()

	s.logger.Info("server listening",
		zap.String("socket", s.socketPath),
	)

	// Accept connections
	go s.acceptLoop(ctx)

	return nil
}

// acceptLoop accepts incoming connections.
func (s *Server) acceptLoop(ctx context.Context) {
	for {
		conn, err := s.listener.Accept()
		if err != nil {
			select {
			case <-s.closedCh:
				return
			default:
				s.logger.Error("accept error", zap.Error(err))
				continue
			}
		}

		s.logger.Info("daemon connected")

		s.wg.Add(1)
		go func() {
			defer s.wg.Done()
			s.handleConnection(ctx, conn)
		}()
	}
}

// handleConnection handles a single daemon connection.
func (s *Server) handleConnection(ctx context.Context, conn net.Conn) {
	defer conn.Close()

	buf := make([]byte, 0, ReadBufSize)
	readBuf := make([]byte, ReadBufSize)

	for {
		select {
		case <-ctx.Done():
			return
		case <-s.closedCh:
			return
		default:
		}

		// Read data from connection
		n, err := conn.Read(readBuf)
		if err != nil {
			if errors.Is(err, net.ErrClosed) {
				s.logger.Info("daemon disconnected")
			} else {
				s.logger.Error("read error", zap.Error(err))
			}
			return
		}

		buf = append(buf, readBuf[:n]...)

		// Process all complete frames in buffer
		for {
			frameData, consumed, err := protocol.ReadFrame(buf)
			if errors.Is(err, protocol.ErrIncompleteFrame) {
				break // Need more data
			}
			if err != nil {
				s.logger.Error("frame read error", zap.Error(err))
				buf = buf[1:] // Skip one byte and try again
				continue
			}

			// Process the frame
			s.processFrame(ctx, conn, frameData)

			// Remove processed bytes from buffer
			buf = buf[consumed:]
		}
	}
}

// processFrame processes a single frame from the daemon.
func (s *Server) processFrame(ctx context.Context, conn net.Conn, data []byte) {
	frame, err := protocol.ParseSideEffect(data)
	if err != nil {
		s.logger.Error("failed to parse side-effect frame", zap.Error(err))
		return
	}

	s.logger.Debug("received side-effect",
		zap.String("effect_id", frame.EffectID.String()),
		zap.Int("payload_len", len(frame.JSONPayload)),
	)

	// Parse the JSON payload to get the event type
	var effect sideeffect.SideEffect
	if err := json.Unmarshal(frame.JSONPayload, &effect); err != nil {
		s.logger.Error("failed to parse side-effect JSON",
			zap.String("effect_id", frame.EffectID.String()),
			zap.Error(err),
		)
		s.sendAck(conn, frame.EffectID, protocol.Failed, err.Error())
		return
	}

	eventName := string(effect.Type)
	if effect.Event != "" {
		eventName = effect.Event
	}
	if eventName == "" {
		err := errors.New("missing event name in side-effect payload")
		s.logger.Error("failed to publish side-effect",
			zap.String("effect_id", frame.EffectID.String()),
			zap.Error(err),
		)
		s.sendAck(conn, frame.EffectID, protocol.Failed, err.Error())
		return
	}

	publishPayload := frame.JSONPayload
	if len(effect.Payload) > 0 {
		publishPayload = effect.Payload
	}

	// Publish to Ably (default or override channel)
	if effect.Channel != "" {
		err = s.publisher.PublishJSONToChannel(ctx, effect.Channel, eventName, publishPayload)
	} else {
		err = s.publisher.PublishJSON(ctx, eventName, publishPayload)
	}
	if err != nil {
		s.logger.Error("failed to publish side-effect",
			zap.String("effect_id", frame.EffectID.String()),
			zap.String("channel", effect.Channel),
			zap.String("event", eventName),
			zap.Error(err),
		)
		s.sendAck(conn, frame.EffectID, protocol.Failed, err.Error())
		return
	}

	s.logger.Info("published side-effect",
		zap.String("effect_id", frame.EffectID.String()),
		zap.String("channel", effect.Channel),
		zap.String("event", eventName),
		zap.String("session_id", effect.SessionID),
	)

	// Send success acknowledgment
	s.sendAck(conn, frame.EffectID, protocol.Success, "")
}

// sendAck sends a PublishAckFrame to the daemon.
func (s *Server) sendAck(conn net.Conn, effectID uuid.UUID, status protocol.PublishStatus, errorMsg string) {
	ack := &protocol.PublishAckFrame{
		EffectID:     effectID,
		Status:       status,
		ErrorMessage: errorMsg,
	}

	encoded := ack.Encode()
	if _, err := conn.Write(encoded); err != nil {
		s.logger.Error("failed to send ack",
			zap.String("effect_id", effectID.String()),
			zap.Error(err),
		)
	}
}

// Close shuts down the server.
func (s *Server) Close() error {
	s.mu.Lock()
	if s.closed {
		s.mu.Unlock()
		return nil
	}
	s.closed = true
	close(s.closedCh)
	s.mu.Unlock()

	s.logger.Info("closing server")

	if s.listener != nil {
		s.listener.Close()
	}

	// Wait for all connections to close
	s.wg.Wait()

	// Remove socket file
	os.Remove(s.socketPath)

	return nil
}

// Wait blocks until all connections are closed.
func (s *Server) Wait() {
	s.wg.Wait()
}

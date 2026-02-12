// Command falco is a stateless, crash-safe publisher that receives Armin side-effects
// from the daemon and publishes them to Ably for real-time sync.
//
// Usage:
//
//	falco --device-id <device_id>
//
// Environment variables:
//
//	UNBOUND_ABLY_BROKER_SOCKET - Local Ably token broker socket path (required)
//	UNBOUND_ABLY_BROKER_TOKEN  - Local Ably token broker auth token (required)
//	FALCO_SOCKET          - Unix socket path (default: ~/.unbound/falco.sock)
//	FALCO_PUBLISH_TIMEOUT - Ably publish timeout in seconds (default: 5)
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"

	"github.com/unbound-computer/daemon-falco/config"
	"github.com/unbound-computer/daemon-falco/publisher"
	"github.com/unbound-computer/daemon-falco/server"
)

var (
	version = "dev"
)

func main() {
	if err := run(); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}

func run() error {
	// Parse flags
	deviceID := flag.String("device-id", "", "Device ID (required)")
	debug := flag.Bool("debug", false, "Enable debug logging")
	showVersion := flag.Bool("version", false, "Show version")
	flag.Parse()

	if *showVersion {
		fmt.Printf("falco version %s\n", version)
		return nil
	}

	if *deviceID == "" {
		return fmt.Errorf("--device-id is required")
	}

	// Setup logging
	logger, err := newLogger(*debug)
	if err != nil {
		return fmt.Errorf("failed to create logger: %w", err)
	}
	defer logger.Sync()

	logger.Info("starting falco",
		zap.String("version", version),
		zap.String("device_id", *deviceID),
	)

	// Load configuration
	cfg, err := config.New(*deviceID)
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}

	if err := cfg.Validate(); err != nil {
		return fmt.Errorf("invalid config: %w", err)
	}

	// Setup context with signal handling
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		sig := <-sigCh
		logger.Info("received signal, shutting down",
			zap.String("signal", sig.String()),
		)
		cancel()
	}()

	// Create Ably publisher
	pub, err := publisher.New(publisher.Options{
		BrokerSocketPath: cfg.AblyBrokerSocketPath,
		BrokerToken:      cfg.AblyBrokerToken,
		DeviceID:         cfg.DeviceID,
		ChannelName:      cfg.ChannelName,
		PublishTimeout:   cfg.PublishTimeout,
		Logger:           logger.Named("publisher"),
	})
	if err != nil {
		return fmt.Errorf("failed to create publisher: %w", err)
	}
	defer pub.Close()

	// Create and start server first so daemon can connect immediately.
	// Ably connectivity can come up shortly after.
	srv := server.New(cfg.SocketPath, pub, logger.Named("server"))
	if err := srv.Start(ctx); err != nil {
		return fmt.Errorf("failed to start server: %w", err)
	}
	defer srv.Close()

	// Connect to Ably asynchronously so Falco socket readiness is not gated on
	// external network conditions.
	go func() {
		logger.Info("connecting Ably publisher in background")
		if err := pub.Connect(ctx); err != nil {
			select {
			case <-ctx.Done():
				return
			default:
			}
			logger.Error("failed to connect to Ably publisher", zap.Error(err))
			return
		}
		logger.Info("Ably publisher connected")
	}()

	logger.Info("falco ready",
		zap.String("socket", cfg.SocketPath),
		zap.String("channel", cfg.ChannelName),
	)

	// Wait for shutdown signal
	<-ctx.Done()

	logger.Info("shutdown complete")
	return nil
}

func newLogger(debug bool) (*zap.Logger, error) {
	level := zapcore.InfoLevel
	if debug {
		level = zapcore.DebugLevel
	}

	cfg := zap.Config{
		Level:       zap.NewAtomicLevelAt(level),
		Development: debug,
		Encoding:    "console",
		EncoderConfig: zapcore.EncoderConfig{
			TimeKey:        "time",
			LevelKey:       "level",
			NameKey:        "logger",
			CallerKey:      "caller",
			MessageKey:     "msg",
			StacktraceKey:  "stacktrace",
			LineEnding:     zapcore.DefaultLineEnding,
			EncodeLevel:    zapcore.CapitalColorLevelEncoder,
			EncodeTime:     zapcore.ISO8601TimeEncoder,
			EncodeDuration: zapcore.StringDurationEncoder,
			EncodeCaller:   zapcore.ShortCallerEncoder,
		},
		OutputPaths:      []string{"stdout"},
		ErrorOutputPaths: []string{"stderr"},
	}

	return cfg.Build()
}

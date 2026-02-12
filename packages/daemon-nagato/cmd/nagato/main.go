// Command nagato is a stateless, crash-safe consumer that receives remote commands
// from Ably and forwards them to the local daemon for processing.
//
// Usage:
//
//	nagato --device-id <device_id>
//
// Environment variables:
//
//	UNBOUND_ABLY_BROKER_SOCKET - Local Ably token broker socket path (required)
//	UNBOUND_ABLY_BROKER_TOKEN  - Local Ably token broker auth token (required)
//	NAGATO_SOCKET         - Unix socket path (default: ~/.unbound/nagato.sock)
//	NAGATO_DAEMON_TIMEOUT - Daemon response timeout in seconds (default: 15)
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

	"github.com/unbound-computer/daemon-nagato/config"
	"github.com/unbound-computer/daemon-nagato/courier"
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
		fmt.Printf("nagato version %s\n", version)
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

	logger.Info("starting nagato",
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

	// Create courier
	c, err := courier.New(cfg, logger.Named("courier"))
	if err != nil {
		return fmt.Errorf("failed to create courier: %w", err)
	}

	// Setup signal handling
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

	// Run courier
	if err := c.Run(ctx); err != nil {
		if err == courier.ErrShutdown {
			logger.Info("courier shutdown complete")
			return nil
		}
		return fmt.Errorf("courier error: %w", err)
	}

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

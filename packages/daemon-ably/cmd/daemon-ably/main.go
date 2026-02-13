package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"

	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"

	ablyconfig "github.com/unbound-computer/daemon-ably/config"
	ablyruntime "github.com/unbound-computer/daemon-ably/runtime"
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
	deviceID := flag.String("device-id", "", "Device ID (required)")
	userID := flag.String("user-id", "", "User ID (required)")
	debug := flag.Bool("debug", false, "Enable debug logging")
	showVersion := flag.Bool("version", false, "Show version")
	flag.Parse()

	if *showVersion {
		fmt.Printf("daemon-ably version %s\n", version)
		return nil
	}
	if *deviceID == "" {
		return fmt.Errorf("--device-id is required")
	}
	if *userID == "" {
		return fmt.Errorf("--user-id is required")
	}

	logger, err := newLogger(*debug)
	if err != nil {
		return fmt.Errorf("failed to create logger: %w", err)
	}
	defer logger.Sync()

	cfg, err := ablyconfig.New(*deviceID, *userID)
	if err != nil {
		return fmt.Errorf("failed to load config: %w", err)
	}
	if err := cfg.Validate(); err != nil {
		return fmt.Errorf("invalid config: %w", err)
	}

	if err := os.MkdirAll(filepath.Dir(cfg.SocketPath), 0o700); err != nil {
		return fmt.Errorf("failed ensuring socket directory: %w", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	go func() {
		sig := <-sigCh
		logger.Info("received signal, shutting down daemon-ably", zap.String("signal", sig.String()))
		cancel()
	}()

	manager, err := ablyruntime.NewManager(cfg, logger.Named("manager"))
	if err != nil {
		return fmt.Errorf("failed creating daemon-ably manager: %w", err)
	}
	defer manager.Close()

	if err := manager.Start(ctx); err != nil {
		return fmt.Errorf("failed starting daemon-ably: %w", err)
	}

	logger.Info(
		"daemon-ably ready",
		zap.String("version", version),
		zap.String("device_id", cfg.DeviceID),
		zap.String("user_id", cfg.UserID),
		zap.String("socket", cfg.SocketPath),
		zap.String("presence_channel", cfg.PresenceChannel),
		zap.String("presence_event", cfg.PresenceEvent),
	)

	<-ctx.Done()
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

import { beforeEach, describe, expect, it } from "vitest";
import { MemoryStorage } from "./memory.js";
import { SecretsManager } from "./secrets.js";
import type { TrustedDevice } from "./types.js";

describe("SecretsManager", () => {
  let storage: MemoryStorage;
  let secrets: SecretsManager;

  beforeEach(() => {
    storage = new MemoryStorage();
    secrets = new SecretsManager(storage);
  });

  describe("trusted devices management", () => {
    const createTrustedDevice = (
      overrides?: Partial<TrustedDevice>
    ): TrustedDevice => ({
      deviceId: "device-123",
      name: "Test Device",
      publicKey: "dGVzdC1wdWJsaWMta2V5", // base64
      role: "trusted_executor",
      trustedAt: new Date().toISOString(),
      ...overrides,
    });

    describe("getTrustedDevices", () => {
      it("should return empty array when no devices stored", async () => {
        const devices = await secrets.getTrustedDevices();
        expect(devices).toEqual([]);
      });

      it("should return stored devices", async () => {
        const device = createTrustedDevice();
        await secrets.addTrustedDevice(device);

        const devices = await secrets.getTrustedDevices();
        expect(devices).toHaveLength(1);
        expect(devices[0]).toEqual(device);
      });

      it("should handle invalid JSON gracefully", async () => {
        await storage.set("trusted_devices", "not-valid-json");
        const devices = await secrets.getTrustedDevices();
        expect(devices).toEqual([]);
      });
    });

    describe("addTrustedDevice", () => {
      it("should add a new trusted device", async () => {
        const device = createTrustedDevice();
        await secrets.addTrustedDevice(device);

        const devices = await secrets.getTrustedDevices();
        expect(devices).toContainEqual(device);
      });

      it("should update existing device with same ID", async () => {
        const device1 = createTrustedDevice({ name: "Original Name" });
        await secrets.addTrustedDevice(device1);

        const device2 = createTrustedDevice({ name: "Updated Name" });
        await secrets.addTrustedDevice(device2);

        const devices = await secrets.getTrustedDevices();
        expect(devices).toHaveLength(1);
        expect(devices[0].name).toBe("Updated Name");
      });

      it("should allow multiple different devices", async () => {
        const device1 = createTrustedDevice({ deviceId: "device-1" });
        const device2 = createTrustedDevice({ deviceId: "device-2" });
        const device3 = createTrustedDevice({ deviceId: "device-3" });

        await secrets.addTrustedDevice(device1);
        await secrets.addTrustedDevice(device2);
        await secrets.addTrustedDevice(device3);

        const devices = await secrets.getTrustedDevices();
        expect(devices).toHaveLength(3);
      });
    });

    describe("removeTrustedDevice", () => {
      it("should remove an existing device", async () => {
        const device = createTrustedDevice();
        await secrets.addTrustedDevice(device);

        const removed = await secrets.removeTrustedDevice(device.deviceId);

        expect(removed).toBe(true);
        const devices = await secrets.getTrustedDevices();
        expect(devices).toHaveLength(0);
      });

      it("should return false if device not found", async () => {
        const removed = await secrets.removeTrustedDevice("non-existent");
        expect(removed).toBe(false);
      });

      it("should not affect other devices", async () => {
        const device1 = createTrustedDevice({ deviceId: "device-1" });
        const device2 = createTrustedDevice({ deviceId: "device-2" });

        await secrets.addTrustedDevice(device1);
        await secrets.addTrustedDevice(device2);

        await secrets.removeTrustedDevice("device-1");

        const devices = await secrets.getTrustedDevices();
        expect(devices).toHaveLength(1);
        expect(devices[0].deviceId).toBe("device-2");
      });
    });

    describe("isTrustedDevice", () => {
      it("should return true for existing trusted device", async () => {
        const device = createTrustedDevice();
        await secrets.addTrustedDevice(device);

        const isTrusted = await secrets.isTrustedDevice(device.deviceId);
        expect(isTrusted).toBe(true);
      });

      it("should return false for non-existent device", async () => {
        const isTrusted = await secrets.isTrustedDevice("non-existent");
        expect(isTrusted).toBe(false);
      });

      it("should return false for expired device", async () => {
        const pastDate = new Date(Date.now() - 86_400_000).toISOString(); // 1 day ago
        const device = createTrustedDevice({ expiresAt: pastDate });
        await secrets.addTrustedDevice(device);

        const isTrusted = await secrets.isTrustedDevice(device.deviceId);
        expect(isTrusted).toBe(false);
      });

      it("should return true for device with future expiration", async () => {
        const futureDate = new Date(Date.now() + 86_400_000).toISOString(); // 1 day ahead
        const device = createTrustedDevice({ expiresAt: futureDate });
        await secrets.addTrustedDevice(device);

        const isTrusted = await secrets.isTrustedDevice(device.deviceId);
        expect(isTrusted).toBe(true);
      });

      it("should return true for device without expiration", async () => {
        const device = createTrustedDevice({ expiresAt: undefined });
        await secrets.addTrustedDevice(device);

        const isTrusted = await secrets.isTrustedDevice(device.deviceId);
        expect(isTrusted).toBe(true);
      });
    });

    describe("getTrustedDevice", () => {
      it("should return device by ID", async () => {
        const device = createTrustedDevice();
        await secrets.addTrustedDevice(device);

        const found = await secrets.getTrustedDevice(device.deviceId);
        expect(found).toEqual(device);
      });

      it("should return null if not found", async () => {
        const found = await secrets.getTrustedDevice("non-existent");
        expect(found).toBeNull();
      });
    });

    describe("hasTrustedDevices", () => {
      it("should return false when no devices", async () => {
        const has = await secrets.hasTrustedDevices();
        expect(has).toBe(false);
      });

      it("should return true when devices exist", async () => {
        await secrets.addTrustedDevice(createTrustedDevice());

        const has = await secrets.hasTrustedDevices();
        expect(has).toBe(true);
      });
    });

    describe("getTrustRoot", () => {
      it("should return null when no trust root", async () => {
        await secrets.addTrustedDevice(
          createTrustedDevice({ role: "trusted_executor" })
        );

        const trustRoot = await secrets.getTrustRoot();
        expect(trustRoot).toBeNull();
      });

      it("should return the trust root device", async () => {
        const executor = createTrustedDevice({
          deviceId: "executor-1",
          role: "trusted_executor",
        });
        const trustRoot = createTrustedDevice({
          deviceId: "trust-root-1",
          role: "trust_root",
          name: "iPhone",
        });

        await secrets.addTrustedDevice(executor);
        await secrets.addTrustedDevice(trustRoot);

        const found = await secrets.getTrustRoot();
        expect(found).not.toBeNull();
        expect(found?.role).toBe("trust_root");
        expect(found?.name).toBe("iPhone");
      });

      it("should return first trust root if multiple exist", async () => {
        // This shouldn't happen in practice, but test the behavior
        const root1 = createTrustedDevice({
          deviceId: "root-1",
          role: "trust_root",
          name: "First Root",
        });
        const root2 = createTrustedDevice({
          deviceId: "root-2",
          role: "trust_root",
          name: "Second Root",
        });

        await secrets.addTrustedDevice(root1);
        await secrets.addTrustedDevice(root2);

        const found = await secrets.getTrustRoot();
        expect(found?.name).toBe("First Root");
      });
    });
  });

  describe("device identity", () => {
    describe("setDeviceId / getDeviceId", () => {
      it("should store and retrieve device ID", async () => {
        const deviceId = "test-device-uuid";
        await secrets.setDeviceId(deviceId);

        const retrieved = await secrets.getDeviceId();
        expect(retrieved).toBe(deviceId);
      });

      it("should return null when not set", async () => {
        const retrieved = await secrets.getDeviceId();
        expect(retrieved).toBeNull();
      });
    });

    describe("setDevicePrivateKey / getDevicePrivateKey", () => {
      it("should store and retrieve device private key as base64", async () => {
        const privateKey = new Uint8Array(32).fill(42);
        await secrets.setDevicePrivateKey(privateKey);

        const retrieved = await secrets.getDevicePrivateKey();
        expect(retrieved).toEqual(privateKey);
      });

      it("should return null when not set", async () => {
        const retrieved = await secrets.getDevicePrivateKey();
        expect(retrieved).toBeNull();
      });
    });
  });

  describe("API key management", () => {
    describe("setApiKey / getApiKey", () => {
      it("should store and retrieve API key", async () => {
        const apiKey = "unkey_abc123";
        await secrets.setApiKey(apiKey);

        const retrieved = await secrets.getApiKey();
        expect(retrieved).toBe(apiKey);
      });
    });

    describe("hasApiKey", () => {
      it("should return false when not set", async () => {
        const has = await secrets.hasApiKey();
        expect(has).toBe(false);
      });

      it("should return true when set", async () => {
        await secrets.setApiKey("test-key");
        const has = await secrets.hasApiKey();
        expect(has).toBe(true);
      });
    });

    describe("deleteApiKey", () => {
      it("should delete the API key", async () => {
        await secrets.setApiKey("test-key");
        const deleted = await secrets.deleteApiKey();

        expect(deleted).toBe(true);
        const has = await secrets.hasApiKey();
        expect(has).toBe(false);
      });
    });
  });

  describe("isDeviceLinked", () => {
    it("should return false when neither API key nor device ID set", async () => {
      const linked = await secrets.isDeviceLinked();
      expect(linked).toBe(false);
    });

    it("should return false when only API key set", async () => {
      await secrets.setApiKey("test-key");
      const linked = await secrets.isDeviceLinked();
      expect(linked).toBe(false);
    });

    it("should return false when only device ID set", async () => {
      await secrets.setDeviceId("test-device");
      const linked = await secrets.isDeviceLinked();
      expect(linked).toBe(false);
    });

    it("should return true when both API key and device ID set", async () => {
      await secrets.setApiKey("test-key");
      await secrets.setDeviceId("test-device");
      const linked = await secrets.isDeviceLinked();
      expect(linked).toBe(true);
    });
  });

  describe("clearAll", () => {
    it("should clear all stored secrets", async () => {
      await secrets.setApiKey("test-key");
      await secrets.setDeviceId("test-device");
      await secrets.setMasterKey(new Uint8Array(32).fill(1));
      await secrets.setDevicePrivateKey(new Uint8Array(32).fill(2));
      await secrets.addTrustedDevice({
        deviceId: "trusted-1",
        name: "Test",
        publicKey: "abc",
        role: "trust_root",
        trustedAt: new Date().toISOString(),
      });

      await secrets.clearAll();

      expect(await secrets.getApiKey()).toBeNull();
      expect(await secrets.getDeviceId()).toBeNull();
      expect(await secrets.getMasterKey()).toBeNull();
      expect(await secrets.getDevicePrivateKey()).toBeNull();
      expect(await secrets.getTrustedDevices()).toEqual([]);
    });
  });
});

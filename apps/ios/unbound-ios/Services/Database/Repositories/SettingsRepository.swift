//
//  SettingsRepository.swift
//  unbound-ios
//
//  Database repository for user settings (key-value store).
//

import Foundation
import GRDB

/// Value types for settings
enum SettingValueType: String {
    case string
    case int
    case bool
    case double
    case json
}

final class SettingsRepository {
    private let databaseService: DatabaseService

    init(databaseService: DatabaseService) {
        self.databaseService = databaseService
    }

    // MARK: - String Settings

    func getString(_ key: String) async throws -> String? {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try UserSettingRecord
                .filter(Column("key") == key)
                .fetchOne(db)?
                .value
        }
    }

    func setString(_ key: String, value: String) async throws {
        let record = UserSettingRecord(
            key: key,
            value: value,
            valueType: SettingValueType.string.rawValue,
            updatedAt: Date()
        )
        try await upsert(record)
    }

    // MARK: - Integer Settings

    func getInt(_ key: String) async throws -> Int? {
        guard let stringValue = try await getString(key) else { return nil }
        return Int(stringValue)
    }

    func setInt(_ key: String, value: Int) async throws {
        let record = UserSettingRecord(
            key: key,
            value: String(value),
            valueType: SettingValueType.int.rawValue,
            updatedAt: Date()
        )
        try await upsert(record)
    }

    // MARK: - Boolean Settings

    func getBool(_ key: String) async throws -> Bool? {
        guard let stringValue = try await getString(key) else { return nil }
        return stringValue == "true" || stringValue == "1"
    }

    func setBool(_ key: String, value: Bool) async throws {
        let record = UserSettingRecord(
            key: key,
            value: value ? "true" : "false",
            valueType: SettingValueType.bool.rawValue,
            updatedAt: Date()
        )
        try await upsert(record)
    }

    // MARK: - Double Settings

    func getDouble(_ key: String) async throws -> Double? {
        guard let stringValue = try await getString(key) else { return nil }
        return Double(stringValue)
    }

    func setDouble(_ key: String, value: Double) async throws {
        let record = UserSettingRecord(
            key: key,
            value: String(value),
            valueType: SettingValueType.double.rawValue,
            updatedAt: Date()
        )
        try await upsert(record)
    }

    // MARK: - JSON Settings (Codable)

    func getObject<T: Decodable>(_ key: String, as type: T.Type) async throws -> T? {
        guard let stringValue = try await getString(key),
              let data = stringValue.data(using: .utf8) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    func setObject<T: Encodable>(_ key: String, value: T) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        guard let stringValue = String(data: data, encoding: .utf8) else {
            throw DatabaseError.invalidData("Failed to encode object to JSON string")
        }
        let record = UserSettingRecord(
            key: key,
            value: stringValue,
            valueType: SettingValueType.json.rawValue,
            updatedAt: Date()
        )
        try await upsert(record)
    }

    // MARK: - Delete

    func delete(_ key: String) async throws {
        let db = try databaseService.getDatabase()
        try await db.write { db in
            try UserSettingRecord
                .filter(Column("key") == key)
                .deleteAll(db)
        }
    }

    /// Delete all settings
    func deleteAll() async throws {
        let db = try databaseService.getDatabase()
        try await db.write { db in
            try UserSettingRecord.deleteAll(db)
        }
    }

    // MARK: - Utility

    /// Check if a setting exists
    func exists(_ key: String) async throws -> Bool {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try UserSettingRecord
                .filter(Column("key") == key)
                .fetchCount(db) > 0
        }
    }

    /// Get all settings keys
    func getAllKeys() async throws -> [String] {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try UserSettingRecord
                .fetchAll(db)
                .map { $0.key }
        }
    }

    // MARK: - Private

    private func upsert(_ record: UserSettingRecord) async throws {
        let db = try databaseService.getDatabase()
        var mutableRecord = record
        try await db.write { db in
            try mutableRecord.save(db)
        }
    }
}

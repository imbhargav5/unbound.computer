//
//  AttachmentRepository.swift
//  unbound-ios
//
//  Database repository for file attachments with disk storage.
//  Files are stored in Library/Application Support/uploads/
//

import Foundation
import GRDB
import CryptoKit

final class AttachmentRepository {
    private let databaseService: DatabaseService
    private let fileManager = FileManager.default

    init(databaseService: DatabaseService) {
        self.databaseService = databaseService
    }

    // MARK: - Attachment Operations

    /// Store a new attachment (saves file to disk and metadata to database)
    func store(
        data: Data,
        filename: String,
        mimeType: String,
        sessionId: UUID,
        messageId: UUID? = nil
    ) async throws -> AttachmentRecord {
        let id = UUID()
        let fileType = AttachmentFileType.from(mimeType: mimeType)
        let storedFilename = generateStoredFilename(originalFilename: filename, id: id)
        let checksum = sha256Checksum(of: data)

        // Save file to disk
        let filePath = getStoragePath(fileType: fileType, storedFilename: storedFilename)
        try data.write(to: filePath)

        // Create database record
        let record = AttachmentRecord(
            id: id.uuidString,
            messageId: messageId?.uuidString,
            sessionId: sessionId.uuidString,
            filename: filename,
            storedFilename: storedFilename,
            fileType: fileType.rawValue,
            mimeType: mimeType,
            fileSize: data.count,
            checksum: checksum,
            metadataJson: nil,
            createdAt: Date()
        )

        let db = try databaseService.getDatabase()
        try await db.write { db in
            var mutableRecord = record
            try mutableRecord.insert(db)
        }

        return record
    }

    /// Store an image attachment with dimensions
    func storeImage(
        data: Data,
        filename: String,
        mimeType: String,
        sessionId: UUID,
        messageId: UUID? = nil,
        width: Int? = nil,
        height: Int? = nil
    ) async throws -> ImageUploadRecord {
        let id = UUID()
        let storedFilename = generateStoredFilename(originalFilename: filename, id: id)
        let checksum = sha256Checksum(of: data)

        // Save file to disk
        let filePath = getStoragePath(fileType: .image, storedFilename: storedFilename)
        try data.write(to: filePath)

        // Create database record
        let record = ImageUploadRecord(
            id: id.uuidString,
            messageId: messageId?.uuidString,
            sessionId: sessionId.uuidString,
            filename: filename,
            storedFilename: storedFilename,
            mimeType: mimeType,
            fileSize: data.count,
            width: width,
            height: height,
            checksum: checksum,
            createdAt: Date()
        )

        let db = try databaseService.getDatabase()
        try await db.write { db in
            var mutableRecord = record
            try mutableRecord.insert(db)
        }

        return record
    }

    /// Fetch attachment data from disk
    func fetchData(for attachment: AttachmentRecord) throws -> Data {
        let fileType = AttachmentFileType(rawValue: attachment.fileType) ?? .other
        let filePath = getStoragePath(fileType: fileType, storedFilename: attachment.storedFilename)
        return try Data(contentsOf: filePath)
    }

    /// Fetch image data from disk
    func fetchData(for imageUpload: ImageUploadRecord) throws -> Data {
        let filePath = getStoragePath(fileType: .image, storedFilename: imageUpload.storedFilename)
        return try Data(contentsOf: filePath)
    }

    // MARK: - Query Operations

    /// Fetch all attachments for a session
    func fetchAttachments(sessionId: UUID) async throws -> [AttachmentRecord] {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try AttachmentRecord
                .filter(Column("session_id") == sessionId.uuidString)
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }

    /// Fetch all attachments for a message
    func fetchAttachments(messageId: UUID) async throws -> [AttachmentRecord] {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try AttachmentRecord
                .filter(Column("message_id") == messageId.uuidString)
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }

    /// Fetch all image uploads for a session
    func fetchImageUploads(sessionId: UUID) async throws -> [ImageUploadRecord] {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try ImageUploadRecord
                .filter(Column("session_id") == sessionId.uuidString)
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }

    /// Fetch all image uploads for a message
    func fetchImageUploads(messageId: UUID) async throws -> [ImageUploadRecord] {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try ImageUploadRecord
                .filter(Column("message_id") == messageId.uuidString)
                .order(Column("created_at").desc)
                .fetchAll(db)
        }
    }

    /// Fetch a single attachment by ID
    func fetchAttachment(id: UUID) async throws -> AttachmentRecord? {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try AttachmentRecord
                .filter(Column("id") == id.uuidString)
                .fetchOne(db)
        }
    }

    /// Fetch a single image upload by ID
    func fetchImageUpload(id: UUID) async throws -> ImageUploadRecord? {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            try ImageUploadRecord
                .filter(Column("id") == id.uuidString)
                .fetchOne(db)
        }
    }

    // MARK: - Delete Operations

    /// Delete an attachment (removes file and database record)
    func deleteAttachment(id: UUID) async throws {
        // Get the record first to know the file path
        guard let record = try await fetchAttachment(id: id) else { return }

        // Delete file from disk
        let fileType = AttachmentFileType(rawValue: record.fileType) ?? .other
        let filePath = getStoragePath(fileType: fileType, storedFilename: record.storedFilename)
        try? fileManager.removeItem(at: filePath)

        // Delete database record
        let db = try databaseService.getDatabase()
        try await db.write { db in
            try AttachmentRecord
                .filter(Column("id") == id.uuidString)
                .deleteAll(db)
        }
    }

    /// Delete an image upload (removes file and database record)
    func deleteImageUpload(id: UUID) async throws {
        guard let record = try await fetchImageUpload(id: id) else { return }

        // Delete file from disk
        let filePath = getStoragePath(fileType: .image, storedFilename: record.storedFilename)
        try? fileManager.removeItem(at: filePath)

        // Delete database record
        let db = try databaseService.getDatabase()
        try await db.write { db in
            try ImageUploadRecord
                .filter(Column("id") == id.uuidString)
                .deleteAll(db)
        }
    }

    /// Delete all attachments for a session (called when session is deleted)
    func deleteAllAttachments(sessionId: UUID) async throws {
        // Get all attachments for the session
        let attachments = try await fetchAttachments(sessionId: sessionId)
        let imageUploads = try await fetchImageUploads(sessionId: sessionId)

        // Delete files from disk
        for attachment in attachments {
            let fileType = AttachmentFileType(rawValue: attachment.fileType) ?? .other
            let filePath = getStoragePath(fileType: fileType, storedFilename: attachment.storedFilename)
            try? fileManager.removeItem(at: filePath)
        }

        for imageUpload in imageUploads {
            let filePath = getStoragePath(fileType: .image, storedFilename: imageUpload.storedFilename)
            try? fileManager.removeItem(at: filePath)
        }

        // Delete database records
        let db = try databaseService.getDatabase()
        try await db.write { db in
            try AttachmentRecord
                .filter(Column("session_id") == sessionId.uuidString)
                .deleteAll(db)
            try ImageUploadRecord
                .filter(Column("session_id") == sessionId.uuidString)
                .deleteAll(db)
        }
    }

    // MARK: - Utility

    /// Generate a stored filename from original filename and UUID
    private func generateStoredFilename(originalFilename: String, id: UUID) -> String {
        let ext = (originalFilename as NSString).pathExtension.lowercased()
        return "\(id.uuidString).\(ext.isEmpty ? "bin" : ext)"
    }

    /// Get the full storage path for a file
    private func getStoragePath(fileType: AttachmentFileType, storedFilename: String) -> URL {
        databaseService.uploadsDirectory
            .appendingPathComponent(fileType.subdirectory)
            .appendingPathComponent(storedFilename)
    }

    /// Get the full storage path for an attachment record
    func getStoragePath(for attachment: AttachmentRecord) -> URL {
        let fileType = AttachmentFileType(rawValue: attachment.fileType) ?? .other
        return getStoragePath(fileType: fileType, storedFilename: attachment.storedFilename)
    }

    /// Get the full storage path for an image upload record
    func getStoragePath(for imageUpload: ImageUploadRecord) -> URL {
        getStoragePath(fileType: .image, storedFilename: imageUpload.storedFilename)
    }

    /// Calculate SHA256 checksum of data
    private func sha256Checksum(of data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Get total storage used by attachments
    func getTotalStorageUsed() async throws -> Int {
        let db = try databaseService.getDatabase()
        return try await db.read { db in
            let attachmentSize = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(file_size), 0) FROM attachments"
            ) ?? 0
            let imageSize = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(file_size), 0) FROM image_uploads"
            ) ?? 0
            return attachmentSize + imageSize
        }
    }
}

"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.AudioFileModel = void 0;
const connection_1 = __importDefault(require("../database/connection"));
const uuid_1 = require("uuid");
const crypto_1 = require("crypto");
class AudioFileModel {
    static createStmt = connection_1.default.prepare(`
    INSERT INTO audio_files (
      id, user_id, content_hash, text_content, voice, model, format, speed, 
      status, created_at, expires_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, ?)
  `);
    static findByUserAndHashStmt = connection_1.default.prepare(`
    SELECT * FROM audio_files 
    WHERE user_id = ? AND content_hash = ? AND status != 'expired'
    ORDER BY created_at DESC LIMIT 1
  `);
    static findByIdStmt = connection_1.default.prepare(`
    SELECT * FROM audio_files WHERE id = ?
  `);
    static updateStatusStmt = connection_1.default.prepare(`
    UPDATE audio_files SET status = ? WHERE id = ?
  `);
    static updateFileInfoStmt = connection_1.default.prepare(`
    UPDATE audio_files SET file_name = ?, file_size = ?, status = 'ready' WHERE id = ?
  `);
    static findExpiredFilesStmt = connection_1.default.prepare(`
    SELECT * FROM audio_files WHERE expires_at < datetime('now') AND status != 'expired'
  `);
    static markExpiredStmt = connection_1.default.prepare(`
    UPDATE audio_files SET status = 'expired' WHERE expires_at < datetime('now')
  `);
    static findByUserIdStmt = connection_1.default.prepare(`
    SELECT * FROM audio_files WHERE user_id = ? AND status != 'expired'
    ORDER BY created_at DESC
  `);
    static findByUserIdSinceStmt = connection_1.default.prepare(`
    SELECT * FROM audio_files 
    WHERE user_id = ? AND created_at > ? AND status != 'expired'
    ORDER BY created_at DESC
  `);
    static countByUserAndDateStmt = connection_1.default.prepare(`
    SELECT COUNT(*) as count FROM audio_files 
    WHERE user_id = ? AND date(created_at) = date('now')
  `);
    static getUserStorageUsageStmt = connection_1.default.prepare(`
    SELECT COALESCE(SUM(file_size), 0) as total_size FROM audio_files 
    WHERE user_id = ? AND status = 'ready'
  `);
    static findStuckGenerationsStmt = connection_1.default.prepare(`
    SELECT * FROM audio_files 
    WHERE status = 'generating' AND created_at < datetime('now', '-1 hour')
  `);
    static generateContentHash(request) {
        const content = `${request.text}|${request.voice}|${request.model}|${request.format}|${request.speed || 1.0}`;
        return (0, crypto_1.createHash)('sha256').update(content).digest('hex');
    }
    static async create(userId, request) {
        const id = (0, uuid_1.v4)();
        const contentHash = this.generateContentHash(request);
        const retentionDays = parseInt(process.env.FILE_RETENTION_DAYS || '7');
        const expiresAt = new Date(Date.now() + retentionDays * 24 * 60 * 60 * 1000).toISOString();
        this.createStmt.run(id, userId, contentHash, request.text, request.voice, request.model, request.format, request.speed || 1.0, 'generating', expiresAt);
        return this.findByIdStmt.get(id);
    }
    static async findByUserAndHash(userId, contentHash) {
        const file = this.findByUserAndHashStmt.get(userId, contentHash);
        return file || null;
    }
    static async findById(fileId) {
        const file = this.findByIdStmt.get(fileId);
        return file || null;
    }
    static async updateStatus(fileId, status) {
        this.updateStatusStmt.run(status, fileId);
    }
    static async updateFileInfo(fileId, fileName, fileSize) {
        this.updateFileInfoStmt.run(fileName, fileSize, fileId);
    }
    static async findExpiredFiles() {
        return this.findExpiredFilesStmt.all();
    }
    static async markExpiredFiles() {
        const result = this.markExpiredStmt.run();
        return result.changes;
    }
    static async findByUserId(userId) {
        return this.findByUserIdStmt.all(userId);
    }
    static async findByUserIdSince(userId, timestamp) {
        return this.findByUserIdSinceStmt.all(userId, timestamp);
    }
    static async findStuckGenerations() {
        return this.findStuckGenerationsStmt.all();
    }
    static async getUserStats(userId) {
        const files = await this.findByUserId(userId);
        const storageResult = this.getUserStorageUsageStmt.get(userId);
        const todayCount = this.countByUserAndDateStmt.get(userId);
        return {
            filesCount: files.length,
            storageUsedMb: Math.round((storageResult.total_size || 0) / (1024 * 1024) * 100) / 100,
            generatedToday: todayCount.count,
        };
    }
}
exports.AudioFileModel = AudioFileModel;
//# sourceMappingURL=audio-file.model.js.map
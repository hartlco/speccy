import db from '../database/connection';
import { AudioFile, TTSRequest } from '../types';
import { v4 as uuidv4 } from 'uuid';
import { createHash } from 'crypto';

export class AudioFileModel {
  private static createStmt = db.prepare(`
    INSERT INTO audio_files (
      id, user_id, content_hash, text_content, voice, model, format, speed, 
      status, created_at, expires_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, ?)
  `);

  private static findByUserAndHashStmt = db.prepare(`
    SELECT * FROM audio_files 
    WHERE user_id = ? AND content_hash = ? AND status != 'expired'
    ORDER BY created_at DESC LIMIT 1
  `);

  private static findByIdStmt = db.prepare(`
    SELECT * FROM audio_files WHERE id = ?
  `);

  private static updateStatusStmt = db.prepare(`
    UPDATE audio_files SET status = ? WHERE id = ?
  `);

  private static updateFileInfoStmt = db.prepare(`
    UPDATE audio_files SET file_name = ?, file_size = ?, status = 'ready' WHERE id = ?
  `);

  private static findExpiredFilesStmt = db.prepare(`
    SELECT * FROM audio_files WHERE expires_at < datetime('now') AND status != 'expired'
  `);

  private static markExpiredStmt = db.prepare(`
    UPDATE audio_files SET status = 'expired' WHERE expires_at < datetime('now')
  `);

  private static findByUserIdStmt = db.prepare(`
    SELECT * FROM audio_files WHERE user_id = ? AND status != 'expired'
    ORDER BY created_at DESC
  `);

  private static findByUserIdSinceStmt = db.prepare(`
    SELECT * FROM audio_files 
    WHERE user_id = ? AND created_at > ? AND status != 'expired'
    ORDER BY created_at DESC
  `);

  private static countByUserAndDateStmt = db.prepare(`
    SELECT COUNT(*) as count FROM audio_files 
    WHERE user_id = ? AND date(created_at) = date('now')
  `);

  private static getUserStorageUsageStmt = db.prepare(`
    SELECT COALESCE(SUM(file_size), 0) as total_size FROM audio_files 
    WHERE user_id = ? AND status = 'ready'
  `);

  private static findStuckGenerationsStmt = db.prepare(`
    SELECT * FROM audio_files 
    WHERE status = 'generating' AND created_at < datetime('now', '-1 hour')
  `);

  static generateContentHash(request: TTSRequest): string {
    const content = `${request.text}|${request.voice}|${request.model}|${request.format}|${request.speed || 1.0}`;
    return createHash('sha256').update(content).digest('hex');
  }

  static async create(userId: string, request: TTSRequest): Promise<AudioFile> {
    const id = uuidv4();
    const contentHash = this.generateContentHash(request);
    const retentionDays = parseInt(process.env.FILE_RETENTION_DAYS || '7');
    const expiresAt = new Date(Date.now() + retentionDays * 24 * 60 * 60 * 1000).toISOString();

    this.createStmt.run(
      id,
      userId,
      contentHash,
      request.text,
      request.voice,
      request.model,
      request.format,
      request.speed || 1.0,
      'generating',
      expiresAt
    );

    return this.findByIdStmt.get(id) as AudioFile;
  }

  static async findByUserAndHash(userId: string, contentHash: string): Promise<AudioFile | null> {
    const file = this.findByUserAndHashStmt.get(userId, contentHash) as AudioFile | undefined;
    return file || null;
  }

  static async findById(fileId: string): Promise<AudioFile | null> {
    const file = this.findByIdStmt.get(fileId) as AudioFile | undefined;
    return file || null;
  }

  static async updateStatus(fileId: string, status: AudioFile['status']): Promise<void> {
    this.updateStatusStmt.run(status, fileId);
  }

  static async updateFileInfo(fileId: string, fileName: string, fileSize: number): Promise<void> {
    this.updateFileInfoStmt.run(fileName, fileSize, fileId);
  }

  static async findExpiredFiles(): Promise<AudioFile[]> {
    return this.findExpiredFilesStmt.all() as AudioFile[];
  }

  static async markExpiredFiles(): Promise<number> {
    const result = this.markExpiredStmt.run();
    return result.changes;
  }

  static async findByUserId(userId: string): Promise<AudioFile[]> {
    return this.findByUserIdStmt.all(userId) as AudioFile[];
  }

  static async findByUserIdSince(userId: string, timestamp: string): Promise<AudioFile[]> {
    return this.findByUserIdSinceStmt.all(userId, timestamp) as AudioFile[];
  }

  static async findStuckGenerations(): Promise<AudioFile[]> {
    return this.findStuckGenerationsStmt.all() as AudioFile[];
  }

  static async getUserStats(userId: string): Promise<{
    filesCount: number;
    storageUsedMb: number;
    generatedToday: number;
  }> {
    const files = await this.findByUserId(userId);
    const storageResult = this.getUserStorageUsageStmt.get(userId) as { total_size: number };
    const todayCount = this.countByUserAndDateStmt.get(userId) as { count: number };

    return {
      filesCount: files.length,
      storageUsedMb: Math.round((storageResult.total_size || 0) / (1024 * 1024) * 100) / 100,
      generatedToday: todayCount.count,
    };
  }
}
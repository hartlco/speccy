import { AudioFile, TTSRequest } from '../types';
export declare class AudioFileModel {
    private static createStmt;
    private static findByUserAndHashStmt;
    private static findByIdStmt;
    private static updateStatusStmt;
    private static updateFileInfoStmt;
    private static findExpiredFilesStmt;
    private static markExpiredStmt;
    private static findByUserIdStmt;
    private static findByUserIdSinceStmt;
    private static countByUserAndDateStmt;
    private static getUserStorageUsageStmt;
    private static findStuckGenerationsStmt;
    static generateContentHash(request: TTSRequest): string;
    static create(userId: string, request: TTSRequest): Promise<AudioFile>;
    static findByUserAndHash(userId: string, contentHash: string): Promise<AudioFile | null>;
    static findById(fileId: string): Promise<AudioFile | null>;
    static updateStatus(fileId: string, status: AudioFile['status']): Promise<void>;
    static updateFileInfo(fileId: string, fileName: string, fileSize: number): Promise<void>;
    static findExpiredFiles(): Promise<AudioFile[]>;
    static markExpiredFiles(): Promise<number>;
    static findByUserId(userId: string): Promise<AudioFile[]>;
    static findByUserIdSince(userId: string, timestamp: string): Promise<AudioFile[]>;
    static findStuckGenerations(): Promise<AudioFile[]>;
    static getUserStats(userId: string): Promise<{
        filesCount: number;
        storageUsedMb: number;
        generatedToday: number;
    }>;
}
//# sourceMappingURL=audio-file.model.d.ts.map
import { TTSRequest, AudioFile } from '../types';
export declare class TTSService {
    private static ensureStorageDir;
    /**
     * Generate TTS with token provided in request (ASYNC - returns immediately)
     */
    static generateTTSWithToken(userId: string, openaiToken: string, request: TTSRequest): Promise<AudioFile>;
    /**
     * Perform TTS generation with provided OpenAI token
     */
    private static performTTSGenerationWithToken;
    /**
     * Split text into chunks for OpenAI TTS processing
     */
    private static chunkText;
    /**
     * Get file status by content hash
     */
    static getFileStatus(userId: string, contentHash: string): Promise<AudioFile | null>;
    /**
     * Get file by ID (for downloading)
     */
    static getFileById(userId: string, fileId: string): Promise<AudioFile | null>;
    /**
     * Get file path for serving
     */
    static getFilePath(fileName: string): string;
}
//# sourceMappingURL=tts.service.d.ts.map
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.TTSService = void 0;
const openai_1 = require("openai");
const audio_file_model_1 = require("../models/audio-file.model");
const user_model_1 = require("../models/user.model");
const fs_1 = require("fs");
const path_1 = require("path");
const promises_1 = require("fs/promises");
const promises_2 = require("fs/promises");
class TTSService {
    static async ensureStorageDir() {
        const storageDir = process.env.STORAGE_PATH || './data/files';
        await (0, promises_1.mkdir)(storageDir, { recursive: true });
        return storageDir;
    }
    /**
     * Generate TTS audio file
     */
    static async generateTTS(userId, request) {
        // Get user's OpenAI token
        const user = await user_model_1.UserModel.findById(userId);
        if (!user) {
            throw new Error('User not found');
        }
        // Check if file already exists for this user and content hash
        const contentHash = audio_file_model_1.AudioFileModel.generateContentHash(request);
        const existingFile = await audio_file_model_1.AudioFileModel.findByUserAndHash(userId, contentHash);
        if (existingFile && existingFile.status === 'ready') {
            console.log(`Using existing TTS file for hash: ${contentHash.substring(0, 8)}`);
            return existingFile;
        }
        if (existingFile && existingFile.status === 'generating') {
            console.log(`TTS generation already in progress for hash: ${contentHash.substring(0, 8)}`);
            return existingFile;
        }
        // Create new audio file record
        const audioFile = await audio_file_model_1.AudioFileModel.create(userId, request);
        console.log(`Starting TTS generation for file: ${audioFile.id}`);
        // Start TTS generation in background
        this.performTTSGeneration(user.openai_token_hash, audioFile.id, request)
            .catch(error => {
            console.error(`TTS generation failed for file ${audioFile.id}:`, error);
            audio_file_model_1.AudioFileModel.updateStatus(audioFile.id, 'failed');
        });
        return audioFile;
    }
    /**
     * Perform actual TTS generation (runs in background)
     */
    static async performTTSGeneration(openaiTokenHash, fileId, request) {
        try {
            // We need to decrypt the OpenAI token to use it
            // For now, we'll need to rethink this - we can't store the actual token
            // Instead, let's use a different approach where the client provides the token
            // for each request, or we store encrypted tokens that can be decrypted
            // For MVP, let's require the token to be passed in the request
            throw new Error('Token handling needs to be implemented');
        }
        catch (error) {
            console.error(`TTS generation error for file ${fileId}:`, error);
            await audio_file_model_1.AudioFileModel.updateStatus(fileId, 'failed');
            throw error;
        }
    }
    /**
     * Alternative: Generate TTS with token provided in request
     */
    static async generateTTSWithToken(userId, openaiToken, request) {
        // Check if file already exists for this user and content hash
        const contentHash = audio_file_model_1.AudioFileModel.generateContentHash(request);
        const existingFile = await audio_file_model_1.AudioFileModel.findByUserAndHash(userId, contentHash);
        if (existingFile && existingFile.status === 'ready') {
            console.log(`Using existing TTS file for hash: ${contentHash.substring(0, 8)}`);
            return existingFile;
        }
        if (existingFile && existingFile.status === 'generating') {
            console.log(`TTS generation already in progress for hash: ${contentHash.substring(0, 8)}`);
            return existingFile;
        }
        // Create new audio file record
        const audioFile = await audio_file_model_1.AudioFileModel.create(userId, request);
        console.log(`Starting TTS generation for file: ${audioFile.id}`);
        // Start TTS generation
        try {
            await this.performTTSGenerationWithToken(openaiToken, audioFile.id, request);
        }
        catch (error) {
            console.error(`TTS generation failed for file ${audioFile.id}:`, error);
            await audio_file_model_1.AudioFileModel.updateStatus(audioFile.id, 'failed');
            throw error;
        }
        return audioFile;
    }
    /**
     * Perform TTS generation with provided OpenAI token
     */
    static async performTTSGenerationWithToken(openaiToken, fileId, request) {
        try {
            const openai = new openai_1.OpenAI({ apiKey: openaiToken });
            const storageDir = await this.ensureStorageDir();
            const fileName = `${fileId}.${request.format}`;
            const filePath = (0, path_1.join)(storageDir, fileName);
            console.log(`Generating TTS audio: ${fileName}`);
            // Call OpenAI TTS API
            const mp3Response = await openai.audio.speech.create({
                model: request.model,
                voice: request.voice,
                input: request.text,
                response_format: request.format,
                speed: request.speed || 1.0,
            });
            // Stream to file
            const buffer = Buffer.from(await mp3Response.arrayBuffer());
            const writeStream = (0, fs_1.createWriteStream)(filePath);
            await new Promise((resolve, reject) => {
                writeStream.on('error', reject);
                writeStream.on('finish', resolve);
                writeStream.write(buffer);
                writeStream.end();
            });
            // Get file size
            const fileStats = await (0, promises_2.stat)(filePath);
            // Update database record
            await audio_file_model_1.AudioFileModel.updateFileInfo(fileId, fileName, fileStats.size);
            console.log(`TTS generation completed: ${fileName} (${fileStats.size} bytes)`);
        }
        catch (error) {
            console.error(`TTS generation error for file ${fileId}:`, error);
            await audio_file_model_1.AudioFileModel.updateStatus(fileId, 'failed');
            throw error;
        }
    }
    /**
     * Get file status by content hash
     */
    static async getFileStatus(userId, contentHash) {
        return await audio_file_model_1.AudioFileModel.findByUserAndHash(userId, contentHash);
    }
    /**
     * Get file by ID (for downloading)
     */
    static async getFileById(userId, fileId) {
        const file = await audio_file_model_1.AudioFileModel.findById(fileId);
        // Ensure file belongs to the requesting user
        if (!file || file.user_id !== userId) {
            return null;
        }
        return file;
    }
    /**
     * Get file path for serving
     */
    static getFilePath(fileName) {
        const storageDir = process.env.STORAGE_PATH || './data/files';
        return (0, path_1.join)(storageDir, fileName);
    }
}
exports.TTSService = TTSService;
//# sourceMappingURL=tts.service.js.map
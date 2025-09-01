"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.TTSService = void 0;
const openai_1 = require("openai");
const audio_file_model_1 = require("../models/audio-file.model");
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
     * Generate TTS with token provided in request (ASYNC - returns immediately)
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
        console.log(`Starting async TTS generation for file: ${audioFile.id}`);
        // Start TTS generation in background (don't await)
        this.performTTSGenerationWithToken(openaiToken, audioFile.id, request)
            .catch(error => {
            console.error(`TTS generation failed for file ${audioFile.id}:`, error);
            audio_file_model_1.AudioFileModel.updateStatus(audioFile.id, 'failed');
        });
        // Return immediately with 'generating' status
        return audioFile;
    }
    /**
     * Perform TTS generation with provided OpenAI token
     */
    static async performTTSGenerationWithToken(openaiToken, fileId, request) {
        try {
            const openai = new openai_1.OpenAI({
                apiKey: openaiToken,
                timeout: 300_000, // 5 minutes timeout for long generations
            });
            const storageDir = await this.ensureStorageDir();
            const fileName = `${fileId}.${request.format}`;
            const filePath = (0, path_1.join)(storageDir, fileName);
            console.log(`Generating TTS audio: ${fileName} (${request.text.length} characters)`);
            // For very large texts, we need to chunk them due to OpenAI's limits
            const chunks = this.chunkText(request.text, 4000); // OpenAI limit is ~4096 chars
            const audioBuffers = [];
            console.log(`Processing ${chunks.length} chunks for file: ${fileId}`);
            // Process each chunk
            for (let i = 0; i < chunks.length; i++) {
                const chunk = chunks[i];
                console.log(`Processing chunk ${i + 1}/${chunks.length} for file: ${fileId}`);
                try {
                    const mp3Response = await openai.audio.speech.create({
                        model: request.model,
                        voice: request.voice,
                        input: chunk,
                        response_format: request.format,
                        speed: request.speed || 1.0,
                    });
                    const buffer = Buffer.from(await mp3Response.arrayBuffer());
                    audioBuffers.push(buffer);
                    // Small delay between chunks to avoid rate limits
                    if (i < chunks.length - 1) {
                        await new Promise(resolve => setTimeout(resolve, 100));
                    }
                }
                catch (chunkError) {
                    console.error(`Error processing chunk ${i + 1}/${chunks.length} for file ${fileId}:`, chunkError);
                    throw chunkError;
                }
            }
            // Combine all audio buffers
            const combinedBuffer = Buffer.concat(audioBuffers);
            // Write combined audio to file
            const writeStream = (0, fs_1.createWriteStream)(filePath);
            await new Promise((resolve, reject) => {
                writeStream.on('error', reject);
                writeStream.on('finish', resolve);
                writeStream.write(combinedBuffer);
                writeStream.end();
            });
            // Get file size
            const fileStats = await (0, promises_2.stat)(filePath);
            // Update database record
            await audio_file_model_1.AudioFileModel.updateFileInfo(fileId, fileName, fileStats.size);
            console.log(`TTS generation completed: ${fileName} (${fileStats.size} bytes, ${chunks.length} chunks)`);
        }
        catch (error) {
            console.error(`TTS generation error for file ${fileId}:`, error);
            await audio_file_model_1.AudioFileModel.updateStatus(fileId, 'failed');
            throw error;
        }
    }
    /**
     * Split text into chunks for OpenAI TTS processing
     */
    static chunkText(text, maxChunkLength = 4000) {
        if (text.length <= maxChunkLength) {
            return [text];
        }
        const chunks = [];
        let currentChunk = "";
        // Split by sentences first
        const sentences = text.split(/(?<=[.!?])\s+/);
        for (const sentence of sentences) {
            // If single sentence is too long, split by words
            if (sentence.length > maxChunkLength) {
                if (currentChunk) {
                    chunks.push(currentChunk.trim());
                    currentChunk = "";
                }
                const words = sentence.split(/\s+/);
                for (const word of words) {
                    if (currentChunk.length + word.length + 1 <= maxChunkLength) {
                        currentChunk += (currentChunk ? " " : "") + word;
                    }
                    else {
                        if (currentChunk) {
                            chunks.push(currentChunk.trim());
                        }
                        currentChunk = word;
                    }
                }
            }
            else {
                // Normal sentence processing
                if (currentChunk.length + sentence.length + 1 <= maxChunkLength) {
                    currentChunk += (currentChunk ? " " : "") + sentence;
                }
                else {
                    if (currentChunk) {
                        chunks.push(currentChunk.trim());
                    }
                    currentChunk = sentence;
                }
            }
        }
        if (currentChunk.trim()) {
            chunks.push(currentChunk.trim());
        }
        return chunks.length > 0 ? chunks : [text];
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
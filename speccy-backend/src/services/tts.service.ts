import { OpenAI } from 'openai';
import { AudioFileModel } from '../models/audio-file.model';
import { UserModel } from '../models/user.model';
import { TTSRequest, AudioFile } from '../types';
import { createWriteStream } from 'fs';
import { join } from 'path';
import { mkdir } from 'fs/promises';
import { stat } from 'fs/promises';

export class TTSService {
  private static async ensureStorageDir(): Promise<string> {
    const storageDir = process.env.STORAGE_PATH || './data/files';
    await mkdir(storageDir, { recursive: true });
    return storageDir;
  }



  /**
   * Generate TTS with token provided in request (ASYNC - returns immediately)
   */
  static async generateTTSWithToken(
    userId: string, 
    openaiToken: string, 
    request: TTSRequest
  ): Promise<AudioFile> {
    // Check if file already exists for this user and content hash
    const contentHash = AudioFileModel.generateContentHash(request);
    const existingFile = await AudioFileModel.findByUserAndHash(userId, contentHash);
    
    if (existingFile && existingFile.status === 'ready') {
      console.log(`Using existing TTS file for hash: ${contentHash.substring(0, 8)}`);
      return existingFile;
    }

    if (existingFile && existingFile.status === 'generating') {
      console.log(`TTS generation already in progress for hash: ${contentHash.substring(0, 8)}`);
      return existingFile;
    }

    // Create new audio file record
    const audioFile = await AudioFileModel.create(userId, request);
    console.log(`Starting async TTS generation for file: ${audioFile.id}`);

    // Start TTS generation in background (don't await)
    this.performTTSGenerationWithToken(openaiToken, audioFile.id, request)
      .catch(error => {
        console.error(`TTS generation failed for file ${audioFile.id}:`, error);
        AudioFileModel.updateStatus(audioFile.id, 'failed');
      });

    // Return immediately with 'generating' status
    return audioFile;
  }

  /**
   * Perform TTS generation with provided OpenAI token
   */
  private static async performTTSGenerationWithToken(
    openaiToken: string,
    fileId: string,
    request: TTSRequest
  ): Promise<void> {
    try {
      const openai = new OpenAI({ 
        apiKey: openaiToken,
        timeout: 300_000, // 5 minutes timeout for long generations
      });
      const storageDir = await this.ensureStorageDir();
      const fileName = `${fileId}.${request.format}`;
      const filePath = join(storageDir, fileName);

      console.log(`Generating TTS audio: ${fileName} (${request.text.length} characters)`);
      
      // For very large texts, we need to chunk them due to OpenAI's limits
      const chunks = this.chunkText(request.text, 4000); // OpenAI limit is ~4096 chars
      const audioBuffers: Buffer[] = [];
      
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
            response_format: request.format as any,
            speed: request.speed || 1.0,
          });

          const buffer = Buffer.from(await mp3Response.arrayBuffer());
          audioBuffers.push(buffer);
          
          // Small delay between chunks to avoid rate limits
          if (i < chunks.length - 1) {
            await new Promise(resolve => setTimeout(resolve, 100));
          }
          
        } catch (chunkError: any) {
          console.error(`Error processing chunk ${i + 1}/${chunks.length} for file ${fileId}:`, chunkError);
          throw chunkError;
        }
      }

      // Combine all audio buffers
      const combinedBuffer = Buffer.concat(audioBuffers);
      
      // Write combined audio to file
      const writeStream = createWriteStream(filePath);
      
      await new Promise<void>((resolve, reject) => {
        writeStream.on('error', reject);
        writeStream.on('finish', resolve);
        writeStream.write(combinedBuffer);
        writeStream.end();
      });

      // Get file size
      const fileStats = await stat(filePath);
      
      // Update database record
      await AudioFileModel.updateFileInfo(fileId, fileName, fileStats.size);
      
      console.log(`TTS generation completed: ${fileName} (${fileStats.size} bytes, ${chunks.length} chunks)`);

    } catch (error: any) {
      console.error(`TTS generation error for file ${fileId}:`, error);
      await AudioFileModel.updateStatus(fileId, 'failed');
      throw error;
    }
  }
  
  /**
   * Split text into chunks for OpenAI TTS processing
   */
  private static chunkText(text: string, maxChunkLength: number = 4000): string[] {
    if (text.length <= maxChunkLength) {
      return [text];
    }
    
    const chunks: string[] = [];
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
          } else {
            if (currentChunk) {
              chunks.push(currentChunk.trim());
            }
            currentChunk = word;
          }
        }
      } else {
        // Normal sentence processing
        if (currentChunk.length + sentence.length + 1 <= maxChunkLength) {
          currentChunk += (currentChunk ? " " : "") + sentence;
        } else {
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
  static async getFileStatus(userId: string, contentHash: string): Promise<AudioFile | null> {
    return await AudioFileModel.findByUserAndHash(userId, contentHash);
  }

  /**
   * Get file by ID (for downloading)
   */
  static async getFileById(userId: string, fileId: string): Promise<AudioFile | null> {
    const file = await AudioFileModel.findById(fileId);
    
    // Ensure file belongs to the requesting user
    if (!file || file.user_id !== userId) {
      return null;
    }
    
    return file;
  }

  /**
   * Get file path for serving
   */
  static getFilePath(fileName: string): string {
    const storageDir = process.env.STORAGE_PATH || './data/files';
    return join(storageDir, fileName);
  }
}
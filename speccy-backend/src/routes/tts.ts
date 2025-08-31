import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { TTSService } from '../services/tts.service';
import { AudioFileModel } from '../models/audio-file.model';
import { TTSRequest, TTSResponse, FileStatusResponse } from '../types';
import { createReadStream } from 'fs';
import { stat } from 'fs/promises';

const ttsRequestSchema = z.object({
  text: z.string().min(1, 'Text is required').max(50000, 'Text too long'), // Increased to 50k characters (~10-15 pages
  voice: z.enum(['alloy', 'echo', 'fable', 'onyx', 'nova', 'shimmer']),
  model: z.enum(['tts-1', 'tts-1-hd']),
  format: z.enum(['mp3', 'opus', 'aac', 'flac']).default('mp3'),
  speed: z.number().min(0.25).max(4.0).default(1.0),
  openai_token: z.string().min(1, 'OpenAI token is required'), // Token provided per request for now
});

export async function ttsRoutes(fastify: FastifyInstance) {
  // POST /tts/generate - Generate TTS audio
  fastify.post<{ Body: TTSRequest & { openai_token: string }; Reply: TTSResponse }>('/generate', {
    preHandler: [fastify.authMiddleware],
    schema: {
      body: {
        type: 'object',
        required: ['text', 'voice', 'model', 'openai_token'],
        properties: {
          text: { type: 'string', minLength: 1, maxLength: 50000 },
          voice: { type: 'string', enum: ['alloy', 'echo', 'fable', 'onyx', 'nova', 'shimmer'] },
          model: { type: 'string', enum: ['tts-1', 'tts-1-hd'] },
          format: { type: 'string', enum: ['mp3', 'opus', 'aac', 'flac'], default: 'mp3' },
          speed: { type: 'number', minimum: 0.25, maximum: 4.0, default: 1.0 },
          openai_token: { type: 'string', minLength: 1 }
        }
      },
      response: {
        200: {
          type: 'object',
          properties: {
            file_id: { type: 'string' },
            content_hash: { type: 'string' },
            status: { type: 'string', enum: ['generating', 'ready', 'failed'] },
            url: { type: 'string' },
            expires_at: { type: 'string' }
          }
        }
      }
    }
  }, async (request, reply) => {
    try {
      const user = (request as any).user!;
      const requestData = ttsRequestSchema.parse(request.body);
      
      // Extract OpenAI token and TTS request
      const { openai_token, ...ttsRequest } = requestData;

      // Generate TTS
      const audioFile = await TTSService.generateTTSWithToken(
        user.id, 
        openai_token, 
        ttsRequest
      );

      const response: TTSResponse = {
        file_id: audioFile.id,
        content_hash: audioFile.content_hash,
        status: audioFile.status as any,
        url: audioFile.status === 'ready' ? `/files/${audioFile.id}` : undefined,
        expires_at: audioFile.expires_at,
      };

      return reply.code(200).send(response);

    } catch (error: any) {
      console.error('TTS generation error:', error);
      
      if (error instanceof z.ZodError) {
        return reply.code(400).send({
          error: 'Bad Request',
          message: error.errors.map(e => e.message).join(', ')
        });
      }

      return reply.code(500).send({
        error: 'Internal Server Error',
        message: 'TTS generation failed'
      });
    }
  });

  // GET /tts/:contentHash/status - Get file status by content hash
  fastify.get<{ Params: { contentHash: string }; Reply: FileStatusResponse }>('/status/:contentHash', {
    preHandler: [fastify.authMiddleware],
    schema: {
      params: {
        type: 'object',
        required: ['contentHash'],
        properties: {
          contentHash: { type: 'string', minLength: 64, maxLength: 64 }
        }
      },
      response: {
        200: {
          type: 'object',
          properties: {
            status: { type: 'string', enum: ['generating', 'ready', 'failed', 'not_found'] },
            file_id: { type: 'string' },
            expires_at: { type: 'string' }
          }
        }
      }
    }
  }, async (request, reply) => {
    try {
      const user = (request as any).user!;
      const { contentHash } = request.params;

      const audioFile = await TTSService.getFileStatus(user.id, contentHash);

      if (!audioFile) {
        return reply.code(200).send({
          status: 'not_found'
        });
      }

      const response: FileStatusResponse = {
        status: audioFile.status as any,
        file_id: audioFile.id,
        expires_at: audioFile.expires_at,
      };

      return reply.code(200).send(response);

    } catch (error: any) {
      console.error('File status check error:', error);
      return reply.code(500).send({
        error: 'Internal Server Error',
        message: 'Failed to check file status'
      });
    }
  });

  // DELETE /tts/:fileId - Delete file
  fastify.delete<{ Params: { fileId: string } }>('/delete/:fileId', {
    preHandler: [fastify.authMiddleware],
    schema: {
      params: {
        type: 'object',
        required: ['fileId'],
        properties: {
          fileId: { type: 'string' }
        }
      },
      response: {
        200: {
          type: 'object',
          properties: {
            deleted: { type: 'boolean' }
          }
        }
      }
    }
  }, async (request, reply) => {
    try {
      const user = (request as any).user!;
      const { fileId } = request.params;

      const audioFile = await TTSService.getFileById(user.id, fileId);
      
      if (!audioFile) {
        return reply.code(404).send({
          error: 'Not Found',
          message: 'File not found'
        });
      }

      // Mark as expired (soft delete)
      await AudioFileModel.updateStatus(fileId, 'expired');

      return reply.code(200).send({
        deleted: true
      });

    } catch (error: any) {
      console.error('File deletion error:', error);
      return reply.code(500).send({
        error: 'Internal Server Error',
        message: 'Failed to delete file'
      });
    }
  });
}
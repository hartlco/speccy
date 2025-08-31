"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ttsRoutes = ttsRoutes;
const zod_1 = require("zod");
const tts_service_1 = require("../services/tts.service");
const audio_file_model_1 = require("../models/audio-file.model");
const ttsRequestSchema = zod_1.z.object({
    text: zod_1.z.string().min(1, 'Text is required').max(4096, 'Text too long'),
    voice: zod_1.z.enum(['alloy', 'echo', 'fable', 'onyx', 'nova', 'shimmer']),
    model: zod_1.z.enum(['tts-1', 'tts-1-hd']),
    format: zod_1.z.enum(['mp3', 'opus', 'aac', 'flac']).default('mp3'),
    speed: zod_1.z.number().min(0.25).max(4.0).default(1.0),
    openai_token: zod_1.z.string().min(1, 'OpenAI token is required'), // Token provided per request for now
});
async function ttsRoutes(fastify) {
    // POST /tts/generate - Generate TTS audio
    fastify.post('/generate', {
        preHandler: [fastify.authMiddleware],
        schema: {
            body: {
                type: 'object',
                required: ['text', 'voice', 'model', 'openai_token'],
                properties: {
                    text: { type: 'string', minLength: 1, maxLength: 4096 },
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
            const user = request.user;
            const requestData = ttsRequestSchema.parse(request.body);
            // Extract OpenAI token and TTS request
            const { openai_token, ...ttsRequest } = requestData;
            // Generate TTS
            const audioFile = await tts_service_1.TTSService.generateTTSWithToken(user.id, openai_token, ttsRequest);
            const response = {
                file_id: audioFile.id,
                content_hash: audioFile.content_hash,
                status: audioFile.status,
                url: audioFile.status === 'ready' ? `/files/${audioFile.id}` : undefined,
                expires_at: audioFile.expires_at,
            };
            return reply.code(200).send(response);
        }
        catch (error) {
            console.error('TTS generation error:', error);
            if (error instanceof zod_1.z.ZodError) {
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
    fastify.get('/status/:contentHash', {
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
            const user = request.user;
            const { contentHash } = request.params;
            const audioFile = await tts_service_1.TTSService.getFileStatus(user.id, contentHash);
            if (!audioFile) {
                return reply.code(200).send({
                    status: 'not_found'
                });
            }
            const response = {
                status: audioFile.status,
                file_id: audioFile.id,
                expires_at: audioFile.expires_at,
            };
            return reply.code(200).send(response);
        }
        catch (error) {
            console.error('File status check error:', error);
            return reply.code(500).send({
                error: 'Internal Server Error',
                message: 'Failed to check file status'
            });
        }
    });
    // DELETE /tts/:fileId - Delete file
    fastify.delete('/delete/:fileId', {
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
            const user = request.user;
            const { fileId } = request.params;
            const audioFile = await tts_service_1.TTSService.getFileById(user.id, fileId);
            if (!audioFile) {
                return reply.code(404).send({
                    error: 'Not Found',
                    message: 'File not found'
                });
            }
            // Mark as expired (soft delete)
            await audio_file_model_1.AudioFileModel.updateStatus(fileId, 'expired');
            return reply.code(200).send({
                deleted: true
            });
        }
        catch (error) {
            console.error('File deletion error:', error);
            return reply.code(500).send({
                error: 'Internal Server Error',
                message: 'Failed to delete file'
            });
        }
    });
}
//# sourceMappingURL=tts.js.map
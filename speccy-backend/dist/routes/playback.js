"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.playbackRoutes = playbackRoutes;
const zod_1 = require("zod");
const playback_state_model_1 = require("../models/playback-state.model");
const audio_file_model_1 = require("../models/audio-file.model");
const playbackStateSchema = zod_1.z.object({
    document_id: zod_1.z.string().min(1, 'Document ID is required'),
    title: zod_1.z.string().min(1, 'Title is required'),
    text_content: zod_1.z.string().min(1, 'Text content is required'),
    language_code: zod_1.z.string().optional(),
    resume_key: zod_1.z.string().min(1, 'Resume key is required'),
    progress: zod_1.z.number().min(0).max(1),
    is_playing: zod_1.z.boolean(),
    is_paused: zod_1.z.boolean(),
    is_loading: zod_1.z.boolean(),
    current_title: zod_1.z.string().min(1, 'Current title is required'),
});
async function playbackRoutes(fastify) {
    // POST /playback/sync - Sync playback state to backend
    fastify.post('/sync', {
        preHandler: [fastify.authMiddleware],
        schema: {
            body: {
                type: 'object',
                required: ['document_id', 'title', 'text_content', 'resume_key', 'progress', 'is_playing', 'is_paused', 'is_loading', 'current_title'],
                properties: {
                    document_id: { type: 'string', minLength: 1 },
                    title: { type: 'string', minLength: 1 },
                    text_content: { type: 'string', minLength: 1 },
                    language_code: { type: 'string' },
                    resume_key: { type: 'string', minLength: 1 },
                    progress: { type: 'number', minimum: 0, maximum: 1 },
                    is_playing: { type: 'boolean' },
                    is_paused: { type: 'boolean' },
                    is_loading: { type: 'boolean' },
                    current_title: { type: 'string', minLength: 1 }
                }
            },
            response: {
                200: {
                    type: 'object',
                    properties: {
                        id: { type: 'string' },
                        document_id: { type: 'string' },
                        title: { type: 'string' },
                        text_content: { type: 'string' },
                        language_code: { type: 'string' },
                        resume_key: { type: 'string' },
                        progress: { type: 'number' },
                        is_playing: { type: 'boolean' },
                        is_paused: { type: 'boolean' },
                        is_loading: { type: 'boolean' },
                        current_title: { type: 'string' },
                        created_at: { type: 'string' },
                        updated_at: { type: 'string' }
                    }
                }
            }
        }
    }, async (request, reply) => {
        try {
            const user = request.user;
            const requestData = playbackStateSchema.parse(request.body);
            const playbackState = await playback_state_model_1.PlaybackStateModel.createOrUpdate(user.id, requestData);
            return reply.code(200).send(playbackState);
        }
        catch (error) {
            console.error('Playback state sync error:', error);
            if (error instanceof zod_1.z.ZodError) {
                return reply.code(400).send({
                    error: 'Bad Request',
                    message: error.errors.map(e => e.message).join(', ')
                });
            }
            return reply.code(500).send({
                error: 'Internal Server Error',
                message: 'Failed to sync playback state'
            });
        }
    });
    // GET /playback/states - Get all playback states for user
    fastify.get('/states', {
        preHandler: [fastify.authMiddleware],
        schema: {
            response: {
                200: {
                    type: 'array',
                    items: {
                        type: 'object',
                        properties: {
                            id: { type: 'string' },
                            document_id: { type: 'string' },
                            title: { type: 'string' },
                            text_content: { type: 'string' },
                            language_code: { type: 'string' },
                            resume_key: { type: 'string' },
                            progress: { type: 'number' },
                            is_playing: { type: 'boolean' },
                            is_paused: { type: 'boolean' },
                            is_loading: { type: 'boolean' },
                            current_title: { type: 'string' },
                            created_at: { type: 'string' },
                            updated_at: { type: 'string' }
                        }
                    }
                }
            }
        }
    }, async (request, reply) => {
        try {
            const user = request.user;
            const playbackStates = playback_state_model_1.PlaybackStateModel.findByUserId(user.id);
            return reply.code(200).send(playbackStates);
        }
        catch (error) {
            console.error('Get playback states error:', error);
            return reply.code(500).send({
                error: 'Internal Server Error',
                message: 'Failed to get playback states'
            });
        }
    });
    // GET /playback/state/:documentId - Get playback state for specific document
    fastify.get('/state/:documentId', {
        preHandler: [fastify.authMiddleware],
        schema: {
            params: {
                type: 'object',
                required: ['documentId'],
                properties: {
                    documentId: { type: 'string', minLength: 1 }
                }
            },
            response: {
                200: {
                    type: ['object', 'null'],
                    properties: {
                        id: { type: 'string' },
                        document_id: { type: 'string' },
                        title: { type: 'string' },
                        text_content: { type: 'string' },
                        language_code: { type: 'string' },
                        resume_key: { type: 'string' },
                        progress: { type: 'number' },
                        is_playing: { type: 'boolean' },
                        is_paused: { type: 'boolean' },
                        is_loading: { type: 'boolean' },
                        current_title: { type: 'string' },
                        created_at: { type: 'string' },
                        updated_at: { type: 'string' }
                    }
                }
            }
        }
    }, async (request, reply) => {
        try {
            const user = request.user;
            const { documentId } = request.params;
            const playbackState = playback_state_model_1.PlaybackStateModel.findByUserAndDocument(user.id, documentId);
            return reply.code(200).send(playbackState);
        }
        catch (error) {
            console.error('Get playback state error:', error);
            return reply.code(500).send({
                error: 'Internal Server Error',
                message: 'Failed to get playback state'
            });
        }
    });
    // DELETE /playback/state/:documentId - Delete playback state for specific document
    fastify.delete('/state/:documentId', {
        preHandler: [fastify.authMiddleware],
        schema: {
            params: {
                type: 'object',
                required: ['documentId'],
                properties: {
                    documentId: { type: 'string', minLength: 1 }
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
            const { documentId } = request.params;
            await playback_state_model_1.PlaybackStateModel.deleteByUserAndDocument(user.id, documentId);
            return reply.code(200).send({ deleted: true });
        }
        catch (error) {
            console.error('Delete playback state error:', error);
            return reply.code(500).send({
                error: 'Internal Server Error',
                message: 'Failed to delete playback state'
            });
        }
    });
    // GET /playback/deleted-files - Get list of files deleted from backend since timestamp
    fastify.get('/deleted-files', {
        preHandler: [fastify.authMiddleware],
        schema: {
            querystring: {
                type: 'object',
                properties: {
                    since: { type: 'string' }
                }
            },
            response: {
                200: {
                    type: 'object',
                    properties: {
                        deleted_files: {
                            type: 'array',
                            items: { type: 'string' }
                        }
                    }
                }
            }
        }
    }, async (request, reply) => {
        try {
            const user = request.user;
            const { since } = request.query;
            // Get expired/deleted files for this user
            const expiredFiles = await audio_file_model_1.AudioFileModel.findExpiredFiles();
            const userExpiredFiles = expiredFiles
                .filter(file => file.user_id === user.id)
                .filter(file => !since || file.expires_at > since)
                .map(file => file.id);
            return reply.code(200).send({ deleted_files: userExpiredFiles });
        }
        catch (error) {
            console.error('Get deleted files error:', error);
            return reply.code(500).send({
                error: 'Internal Server Error',
                message: 'Failed to get deleted files'
            });
        }
    });
}
//# sourceMappingURL=playback.js.map
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.fileRoutes = fileRoutes;
const fs_1 = require("fs");
const promises_1 = require("fs/promises");
const tts_service_1 = require("../services/tts.service");
async function fileRoutes(fastify) {
    // GET /files/:fileId - Download audio file
    fastify.get('/:fileId', {
        preHandler: [fastify.authMiddleware],
        schema: {
            params: {
                type: 'object',
                required: ['fileId'],
                properties: {
                    fileId: { type: 'string' }
                }
            }
        }
    }, async (request, reply) => {
        try {
            const user = request.user;
            const { fileId } = request.params;
            // Get file info and verify ownership
            const audioFile = await tts_service_1.TTSService.getFileById(user.id, fileId);
            if (!audioFile) {
                return reply.code(404).send({
                    error: 'Not Found',
                    message: 'File not found'
                });
            }
            if (audioFile.status !== 'ready') {
                return reply.code(404).send({
                    error: 'Not Found',
                    message: 'File not ready for download'
                });
            }
            if (!audioFile.file_name) {
                return reply.code(404).send({
                    error: 'Not Found',
                    message: 'File name not available'
                });
            }
            const filePath = tts_service_1.TTSService.getFilePath(audioFile.file_name);
            // Check if file exists on disk
            if (!(0, fs_1.existsSync)(filePath)) {
                console.error(`File not found on disk: ${filePath}`);
                return reply.code(404).send({
                    error: 'Not Found',
                    message: 'File not found on disk'
                });
            }
            // Get file stats
            const fileStats = await (0, promises_1.stat)(filePath);
            // Set appropriate headers
            const mimeTypes = {
                'mp3': 'audio/mpeg',
                'opus': 'audio/opus',
                'aac': 'audio/aac',
                'flac': 'audio/flac'
            };
            const extension = audioFile.file_name.split('.').pop();
            const mimeType = mimeTypes[extension] || 'application/octet-stream';
            reply.header('Content-Type', mimeType);
            reply.header('Content-Length', fileStats.size);
            reply.header('Content-Disposition', `attachment; filename="${audioFile.file_name}"`);
            reply.header('Cache-Control', 'public, max-age=3600'); // Cache for 1 hour
            // Stream the file
            const stream = (0, fs_1.createReadStream)(filePath);
            return reply.send(stream);
        }
        catch (error) {
            console.error('File download error:', error);
            return reply.code(500).send({
                error: 'Internal Server Error',
                message: 'Failed to download file'
            });
        }
    });
}
//# sourceMappingURL=files.js.map
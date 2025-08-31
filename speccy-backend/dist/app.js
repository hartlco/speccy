"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.createApp = createApp;
const fastify_1 = __importDefault(require("fastify"));
const cors_1 = __importDefault(require("@fastify/cors"));
const jwt_1 = __importDefault(require("@fastify/jwt"));
const auth_middleware_1 = require("./middleware/auth.middleware");
const auth_1 = require("./routes/auth");
const tts_1 = require("./routes/tts");
const files_1 = require("./routes/files");
const cleanup_service_1 = require("./services/cleanup.service");
function createApp() {
    const fastify = (0, fastify_1.default)({
        logger: {
            level: process.env.LOG_LEVEL || 'info'
        }
    });
    // Register CORS plugin
    fastify.register(cors_1.default, {
        origin: process.env.NODE_ENV === 'production'
            ? process.env.ALLOWED_ORIGINS?.split(',') || []
            : true, // Allow all origins in development
        credentials: true
    });
    // Register JWT plugin
    fastify.register(jwt_1.default, {
        secret: process.env.JWT_SECRET || 'your-secret-key-change-this-in-production'
    });
    // Add auth middleware to fastify instance
    fastify.decorate('authMiddleware', auth_middleware_1.authMiddleware);
    // Health check route
    fastify.get('/health', async () => {
        return {
            status: 'ok',
            timestamp: new Date().toISOString(),
            version: process.env.npm_package_version || '1.0.0'
        };
    });
    // Register route handlers
    fastify.register(auth_1.authRoutes, { prefix: '/auth' });
    fastify.register(tts_1.ttsRoutes, { prefix: '/tts' });
    fastify.register(files_1.fileRoutes, { prefix: '/files' });
    // Start cleanup service
    cleanup_service_1.CleanupService.startPeriodicCleanup();
    // Graceful shutdown
    const gracefulShutdown = async () => {
        console.log('Shutting down gracefully...');
        try {
            await fastify.close();
            console.log('Server closed');
            process.exit(0);
        }
        catch (error) {
            console.error('Error during shutdown:', error);
            process.exit(1);
        }
    };
    process.on('SIGINT', gracefulShutdown);
    process.on('SIGTERM', gracefulShutdown);
    return fastify;
}
// Start server if this file is run directly
if (require.main === module) {
    const start = async () => {
        try {
            const app = createApp();
            const port = parseInt(process.env.PORT || '3000');
            const host = process.env.HOST || '0.0.0.0';
            await app.listen({ port, host });
            console.log(`🚀 Server listening on http://${host}:${port}`);
        }
        catch (error) {
            console.error('Failed to start server:', error);
            process.exit(1);
        }
    };
    start();
}
//# sourceMappingURL=app.js.map
import Fastify from 'fastify';
import cors from '@fastify/cors';
import jwt from '@fastify/jwt';
import { authMiddleware } from './middleware/auth.middleware';
import { authRoutes } from './routes/auth';
import { ttsRoutes } from './routes/tts';
import { fileRoutes } from './routes/files';
import { CleanupService } from './services/cleanup.service';

// Add auth middleware to Fastify instance type
declare module 'fastify' {
  interface FastifyInstance {
    authMiddleware: typeof authMiddleware;
  }
}

export function createApp() {
  const fastify = Fastify({
    logger: {
      level: process.env.LOG_LEVEL || 'info'
    }
  });

  // Register CORS plugin
  fastify.register(cors, {
    origin: process.env.NODE_ENV === 'production' 
      ? process.env.ALLOWED_ORIGINS?.split(',') || []
      : true, // Allow all origins in development
    credentials: true
  });

  // Register JWT plugin
  fastify.register(jwt, {
    secret: process.env.JWT_SECRET || 'your-secret-key-change-this-in-production'
  });

  // Add auth middleware to fastify instance
  fastify.decorate('authMiddleware', authMiddleware);

  // Health check route
  fastify.get('/health', async () => {
    return { 
      status: 'ok', 
      timestamp: new Date().toISOString(),
      version: process.env.npm_package_version || '1.0.0'
    };
  });

  // Register route handlers
  fastify.register(authRoutes, { prefix: '/auth' });
  fastify.register(ttsRoutes, { prefix: '/tts' });
  fastify.register(fileRoutes, { prefix: '/files' });

  // Start cleanup service
  CleanupService.startPeriodicCleanup();

  // Graceful shutdown
  const gracefulShutdown = async () => {
    console.log('Shutting down gracefully...');
    try {
      await fastify.close();
      console.log('Server closed');
      process.exit(0);
    } catch (error) {
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
      
    } catch (error) {
      console.error('Failed to start server:', error);
      process.exit(1);
    }
  };

  start();
}
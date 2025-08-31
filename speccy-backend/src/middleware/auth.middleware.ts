import { FastifyRequest, FastifyReply } from 'fastify';
import { AuthService } from '../services/auth.service';
import { User } from '../types';

declare module 'fastify' {
  interface FastifyInstance {
    authMiddleware: typeof authMiddleware;
  }
}

interface AuthenticatedRequest extends FastifyRequest {
  user: User;
}

export async function authMiddleware(request: FastifyRequest, reply: FastifyReply) {
  try {
    const authHeader = request.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return reply.code(401).send({ 
        error: 'Unauthorized', 
        message: 'Missing or invalid Authorization header' 
      });
    }

    const token = authHeader.substring(7); // Remove 'Bearer ' prefix
    
    // Verify JWT token
    const decoded = await request.jwtVerify();
    const userId = (decoded as any).userId;
    
    if (!userId) {
      return reply.code(401).send({ 
        error: 'Unauthorized', 
        message: 'Invalid token payload' 
      });
    }

    // Validate user still exists and update last seen
    const user = await AuthService.validateUser(userId);
    if (!user) {
      return reply.code(401).send({ 
        error: 'Unauthorized', 
        message: 'User not found or token expired' 
      });
    }

    // Attach user to request
    (request as any).user = user;
  } catch (error: any) {
    console.error('Auth middleware error:', error);
    
    if (error.message?.includes('jwt')) {
      return reply.code(401).send({ 
        error: 'Unauthorized', 
        message: 'Invalid or expired token' 
      });
    }
    
    return reply.code(500).send({ 
      error: 'Internal Server Error', 
      message: 'Authentication error' 
    });
  }
}
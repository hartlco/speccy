import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { AuthService } from '../services/auth.service';
import { AuthRequest, AuthResponse } from '../types';

const authRequestSchema = z.object({
  openai_token: z.string().min(1, 'OpenAI token is required'),
});

export async function authRoutes(fastify: FastifyInstance) {
  // POST /auth/verify - Verify OpenAI token and get session token
  fastify.post<{ Body: AuthRequest; Reply: AuthResponse }>('/verify', {
    schema: {
      body: {
        type: 'object',
        required: ['openai_token'],
        properties: {
          openai_token: { type: 'string', minLength: 1 }
        }
      },
      response: {
        200: {
          type: 'object',
          properties: {
            user_id: { type: 'string' },
            session_token: { type: 'string' }
          }
        },
        401: {
          type: 'object',
          properties: {
            error: { type: 'string' },
            message: { type: 'string' }
          }
        }
      }
    }
  }, async (request, reply) => {
    try {
      // Validate request body
      const { openai_token } = authRequestSchema.parse(request.body);

      // Authenticate with OpenAI token
      const user = await AuthService.authenticateWithOpenAI(openai_token);
      
      if (!user) {
        return reply.code(401).send({
          error: 'Unauthorized',
          message: 'Invalid OpenAI API token'
        });
      }

      // Generate JWT session token
      const sessionToken = await reply.jwtSign(
        { userId: user.id },
        { expiresIn: '7d' } // Token valid for 7 days
      );

      return reply.code(200).send({
        user_id: user.id,
        session_token: sessionToken
      });

    } catch (error: any) {
      console.error('Auth verification error:', error);
      
      if (error instanceof z.ZodError) {
        return reply.code(400).send({
          error: 'Bad Request',
          message: error.errors.map(e => e.message).join(', ')
        });
      }

      return reply.code(500).send({
        error: 'Internal Server Error',
        message: 'Authentication failed'
      });
    }
  });

  // POST /auth/refresh - Refresh session token
  fastify.post('/refresh', {
    preHandler: [fastify.authMiddleware],
    schema: {
      response: {
        200: {
          type: 'object',
          properties: {
            user_id: { type: 'string' },
            session_token: { type: 'string' }
          }
        }
      }
    }
  }, async (request, reply) => {
    try {
      const user = (request as any).user!;

      // Generate new JWT session token
      const sessionToken = await reply.jwtSign(
        { userId: user.id },
        { expiresIn: '7d' }
      );

      return reply.code(200).send({
        user_id: user.id,
        session_token: sessionToken
      });

    } catch (error: any) {
      console.error('Token refresh error:', error);
      return reply.code(500).send({
        error: 'Internal Server Error',
        message: 'Token refresh failed'
      });
    }
  });
}
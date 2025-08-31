import { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { PlaybackStateModel } from '../models/playback-state.model';
import { AudioFileModel } from '../models/audio-file.model';
import { PlaybackStateRequest, PlaybackStateResponse, DeletedFilesResponse } from '../types';

const playbackStateSchema = z.object({
  document_id: z.string().min(1, 'Document ID is required'),
  title: z.string().min(1, 'Title is required'),
  text_content: z.string().min(1, 'Text content is required'),
  language_code: z.string().optional(),
  resume_key: z.string().min(1, 'Resume key is required'),
  progress: z.number().min(0).max(1),
  is_playing: z.boolean(),
  is_paused: z.boolean(),
  is_loading: z.boolean(),
  current_title: z.string().min(1, 'Current title is required'),
});

export async function playbackRoutes(fastify: FastifyInstance) {
  // POST /playback/sync - Sync playback state to backend
  fastify.post<{ Body: PlaybackStateRequest; Reply: PlaybackStateResponse }>('/sync', {
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
      const user = (request as any).user!;
      const requestData = playbackStateSchema.parse(request.body);

      const playbackState = await PlaybackStateModel.createOrUpdate(user.id, requestData);

      return reply.code(200).send(playbackState);

    } catch (error: any) {
      console.error('Playback state sync error:', error);
      
      if (error instanceof z.ZodError) {
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
  fastify.get<{ Reply: PlaybackStateResponse[] }>('/states', {
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
      const user = (request as any).user!;
      const playbackStates = PlaybackStateModel.findByUserId(user.id);
      return reply.code(200).send(playbackStates);

    } catch (error: any) {
      console.error('Get playback states error:', error);
      return reply.code(500).send({
        error: 'Internal Server Error',
        message: 'Failed to get playback states'
      });
    }
  });

  // GET /playback/state/:documentId - Get playback state for specific document
  fastify.get<{ Params: { documentId: string }; Reply: PlaybackStateResponse | null }>('/state/:documentId', {
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
      const user = (request as any).user!;
      const { documentId } = request.params;

      const playbackState = PlaybackStateModel.findByUserAndDocument(user.id, documentId);
      return reply.code(200).send(playbackState);

    } catch (error: any) {
      console.error('Get playback state error:', error);
      return reply.code(500).send({
        error: 'Internal Server Error',
        message: 'Failed to get playback state'
      });
    }
  });

  // DELETE /playback/state/:documentId - Delete playback state for specific document
  fastify.delete<{ Params: { documentId: string } }>('/state/:documentId', {
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
      const user = (request as any).user!;
      const { documentId } = request.params;

      await PlaybackStateModel.deleteByUserAndDocument(user.id, documentId);
      return reply.code(200).send({ deleted: true });

    } catch (error: any) {
      console.error('Delete playback state error:', error);
      return reply.code(500).send({
        error: 'Internal Server Error',
        message: 'Failed to delete playback state'
      });
    }
  });

  // GET /playback/deleted-files - Get list of files deleted from backend since timestamp
  fastify.get<{ 
    Querystring: { since?: string };
    Reply: DeletedFilesResponse 
  }>('/deleted-files', {
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
      const user = (request as any).user!;
      const { since } = request.query;

      // Get expired/deleted files for this user
      const expiredFiles = await AudioFileModel.findExpiredFiles();
      const userExpiredFiles = expiredFiles
        .filter(file => file.user_id === user.id)
        .filter(file => !since || file.expires_at > since)
        .map(file => file.id);

      return reply.code(200).send({ deleted_files: userExpiredFiles });

    } catch (error: any) {
      console.error('Get deleted files error:', error);
      return reply.code(500).send({
        error: 'Internal Server Error',
        message: 'Failed to get deleted files'
      });
    }
  });
}
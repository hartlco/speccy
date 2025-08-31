import { FastifyRequest, FastifyReply } from 'fastify';
declare module 'fastify' {
    interface FastifyInstance {
        authMiddleware: typeof authMiddleware;
    }
}
export declare function authMiddleware(request: FastifyRequest, reply: FastifyReply): Promise<undefined>;
//# sourceMappingURL=auth.middleware.d.ts.map
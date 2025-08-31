"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.authMiddleware = authMiddleware;
const auth_service_1 = require("../services/auth.service");
async function authMiddleware(request, reply) {
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
        const userId = decoded.userId;
        if (!userId) {
            return reply.code(401).send({
                error: 'Unauthorized',
                message: 'Invalid token payload'
            });
        }
        // Validate user still exists and update last seen
        const user = await auth_service_1.AuthService.validateUser(userId);
        if (!user) {
            return reply.code(401).send({
                error: 'Unauthorized',
                message: 'User not found or token expired'
            });
        }
        // Attach user to request
        request.user = user;
    }
    catch (error) {
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
//# sourceMappingURL=auth.middleware.js.map
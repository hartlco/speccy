"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.UserModel = void 0;
const connection_1 = __importDefault(require("../database/connection"));
const uuid_1 = require("uuid");
const crypto_1 = require("crypto");
class UserModel {
    static findByTokenHashStmt = connection_1.default.prepare(`
    SELECT * FROM users WHERE openai_token_hash = ?
  `);
    static createStmt = connection_1.default.prepare(`
    INSERT INTO users (id, openai_token_hash, created_at, last_seen_at)
    VALUES (?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
  `);
    static updateLastSeenStmt = connection_1.default.prepare(`
    UPDATE users SET last_seen_at = CURRENT_TIMESTAMP WHERE id = ?
  `);
    static findByIdStmt = connection_1.default.prepare(`
    SELECT * FROM users WHERE id = ?
  `);
    static hashToken(token) {
        return (0, crypto_1.createHash)('sha256').update(token).digest('hex');
    }
    static async findOrCreateByToken(openaiToken) {
        const tokenHash = this.hashToken(openaiToken);
        // Try to find existing user
        let user = this.findByTokenHashStmt.get(tokenHash);
        if (!user) {
            // Create new user
            const userId = (0, uuid_1.v4)();
            this.createStmt.run(userId, tokenHash);
            user = this.findByIdStmt.get(userId);
        }
        else {
            // Update last seen
            this.updateLastSeenStmt.run(user.id);
            user.last_seen_at = new Date().toISOString();
        }
        return user;
    }
    static async findById(userId) {
        const user = this.findByIdStmt.get(userId);
        return user || null;
    }
    static async updateLastSeen(userId) {
        this.updateLastSeenStmt.run(userId);
    }
}
exports.UserModel = UserModel;
//# sourceMappingURL=user.model.js.map
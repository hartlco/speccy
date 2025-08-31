import db from '../database/connection';
import { User } from '../types';
import { v4 as uuidv4 } from 'uuid';
import { createHash } from 'crypto';

export class UserModel {
  private static findByTokenHashStmt = db.prepare(`
    SELECT * FROM users WHERE openai_token_hash = ?
  `);

  private static createStmt = db.prepare(`
    INSERT INTO users (id, openai_token_hash, created_at, last_seen_at)
    VALUES (?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
  `);

  private static updateLastSeenStmt = db.prepare(`
    UPDATE users SET last_seen_at = CURRENT_TIMESTAMP WHERE id = ?
  `);

  private static findByIdStmt = db.prepare(`
    SELECT * FROM users WHERE id = ?
  `);

  static hashToken(token: string): string {
    return createHash('sha256').update(token).digest('hex');
  }

  static async findOrCreateByToken(openaiToken: string): Promise<User> {
    const tokenHash = this.hashToken(openaiToken);
    
    // Try to find existing user
    let user = this.findByTokenHashStmt.get(tokenHash) as User | undefined;
    
    if (!user) {
      // Create new user
      const userId = uuidv4();
      this.createStmt.run(userId, tokenHash);
      user = this.findByIdStmt.get(userId) as User;
    } else {
      // Update last seen
      this.updateLastSeenStmt.run(user.id);
      user.last_seen_at = new Date().toISOString();
    }

    return user;
  }

  static async findById(userId: string): Promise<User | null> {
    const user = this.findByIdStmt.get(userId) as User | undefined;
    return user || null;
  }

  static async updateLastSeen(userId: string): Promise<void> {
    this.updateLastSeenStmt.run(userId);
  }
}
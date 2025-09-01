"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.PlaybackStateModel = void 0;
const connection_1 = __importDefault(require("../database/connection"));
const uuid_1 = require("uuid");
class PlaybackStateModel {
    static createOrUpdateStmt = connection_1.default.prepare(`
    INSERT INTO playback_states (
      id, user_id, document_id, title, text_content, language_code,
      resume_key, progress, is_playing, is_paused, is_loading, current_title,
      created_at, updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    ON CONFLICT(user_id, document_id) DO UPDATE SET
      title = excluded.title,
      text_content = excluded.text_content,
      language_code = excluded.language_code,
      resume_key = excluded.resume_key,
      progress = excluded.progress,
      is_playing = excluded.is_playing,
      is_paused = excluded.is_paused,
      is_loading = excluded.is_loading,
      current_title = excluded.current_title,
      updated_at = CURRENT_TIMESTAMP
  `);
    static findByUserAndDocumentStmt = connection_1.default.prepare(`
    SELECT * FROM playback_states 
    WHERE user_id = ? AND document_id = ?
  `);
    static findByUserIdStmt = connection_1.default.prepare(`
    SELECT * FROM playback_states 
    WHERE user_id = ?
    ORDER BY updated_at DESC
  `);
    static deleteByUserAndDocumentStmt = connection_1.default.prepare(`
    DELETE FROM playback_states 
    WHERE user_id = ? AND document_id = ?
  `);
    static deleteExpiredStatesStmt = connection_1.default.prepare(`
    DELETE FROM playback_states 
    WHERE updated_at < datetime('now', '-30 days')
  `);
    static async createOrUpdate(userId, input) {
        const id = (0, uuid_1.v4)();
        this.createOrUpdateStmt.run(id, userId, input.document_id, input.title, input.text_content, input.language_code || null, input.resume_key, input.progress, input.is_playing ? 1 : 0, input.is_paused ? 1 : 0, input.is_loading ? 1 : 0, input.current_title);
        // Return the updated/created state
        return this.findByUserAndDocument(userId, input.document_id);
    }
    static findByUserAndDocument(userId, documentId) {
        const state = this.findByUserAndDocumentStmt.get(userId, documentId);
        if (!state)
            return null;
        return {
            ...state,
            is_playing: Boolean(state.is_playing),
            is_paused: Boolean(state.is_paused),
            is_loading: Boolean(state.is_loading),
        };
    }
    static findByUserId(userId) {
        const states = this.findByUserIdStmt.all(userId);
        return states.map(state => ({
            ...state,
            is_playing: Boolean(state.is_playing),
            is_paused: Boolean(state.is_paused),
            is_loading: Boolean(state.is_loading),
        }));
    }
    static async deleteByUserAndDocument(userId, documentId) {
        this.deleteByUserAndDocumentStmt.run(userId, documentId);
    }
    static async cleanupExpiredStates() {
        const result = this.deleteExpiredStatesStmt.run();
        return result.changes;
    }
}
exports.PlaybackStateModel = PlaybackStateModel;
//# sourceMappingURL=playback-state.model.js.map
import db from '../database/connection';
import { v4 as uuidv4 } from 'uuid';

export interface PlaybackState {
  id: string;
  user_id: string;
  document_id: string;
  title: string;
  text_content: string;
  language_code?: string;
  resume_key: string;
  progress: number;
  is_playing: boolean;
  is_paused: boolean;
  is_loading: boolean;
  current_title: string;
  created_at: string;
  updated_at: string;
}

export interface PlaybackStateInput {
  document_id: string;
  title: string;
  text_content: string;
  language_code?: string;
  resume_key: string;
  progress: number;
  is_playing: boolean;
  is_paused: boolean;
  is_loading: boolean;
  current_title: string;
}

export class PlaybackStateModel {
  private static createOrUpdateStmt = db.prepare(`
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

  private static findByUserAndDocumentStmt = db.prepare(`
    SELECT * FROM playback_states 
    WHERE user_id = ? AND document_id = ?
  `);

  private static findByUserIdStmt = db.prepare(`
    SELECT * FROM playback_states 
    WHERE user_id = ?
    ORDER BY updated_at DESC
  `);

  private static deleteByUserAndDocumentStmt = db.prepare(`
    DELETE FROM playback_states 
    WHERE user_id = ? AND document_id = ?
  `);

  private static deleteExpiredStatesStmt = db.prepare(`
    DELETE FROM playback_states 
    WHERE updated_at < datetime('now', '-30 days')
  `);

  static async createOrUpdate(userId: string, input: PlaybackStateInput): Promise<PlaybackState> {
    const id = uuidv4();
    
    this.createOrUpdateStmt.run(
      id,
      userId,
      input.document_id,
      input.title,
      input.text_content,
      input.language_code || null,
      input.resume_key,
      input.progress,
      input.is_playing ? 1 : 0,
      input.is_paused ? 1 : 0,
      input.is_loading ? 1 : 0,
      input.current_title
    );

    // Return the updated/created state
    return this.findByUserAndDocument(userId, input.document_id)!;
  }

  static findByUserAndDocument(userId: string, documentId: string): PlaybackState | null {
    const state = this.findByUserAndDocumentStmt.get(userId, documentId) as any;
    if (!state) return null;

    return {
      ...state,
      is_playing: Boolean(state.is_playing),
      is_paused: Boolean(state.is_paused),
      is_loading: Boolean(state.is_loading),
    };
  }

  static findByUserId(userId: string): PlaybackState[] {
    const states = this.findByUserIdStmt.all(userId) as any[];
    return states.map(state => ({
      ...state,
      is_playing: Boolean(state.is_playing),
      is_paused: Boolean(state.is_paused),
      is_loading: Boolean(state.is_loading),
    }));
  }

  static async deleteByUserAndDocument(userId: string, documentId: string): Promise<void> {
    this.deleteByUserAndDocumentStmt.run(userId, documentId);
  }

  static async cleanupExpiredStates(): Promise<number> {
    const result = this.deleteExpiredStatesStmt.run();
    return result.changes;
  }
}
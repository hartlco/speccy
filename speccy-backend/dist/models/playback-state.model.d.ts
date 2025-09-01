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
export declare class PlaybackStateModel {
    private static createOrUpdateStmt;
    private static findByUserAndDocumentStmt;
    private static findByUserIdStmt;
    private static deleteByUserAndDocumentStmt;
    private static deleteExpiredStatesStmt;
    static createOrUpdate(userId: string, input: PlaybackStateInput): Promise<PlaybackState>;
    static findByUserAndDocument(userId: string, documentId: string): PlaybackState | null;
    static findByUserId(userId: string): PlaybackState[];
    static deleteByUserAndDocument(userId: string, documentId: string): Promise<void>;
    static cleanupExpiredStates(): Promise<number>;
}
//# sourceMappingURL=playback-state.model.d.ts.map
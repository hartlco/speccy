export declare class CleanupService {
    /**
     * Clean up expired files (older than 7 days)
     * Should be run periodically (e.g., daily)
     */
    static cleanupExpiredFiles(): Promise<void>;
    /**
     * Clean up failed generation files (older than 1 hour)
     * These are files that got stuck in 'generating' status
     */
    static cleanupFailedGenerations(): Promise<void>;
    /**
     * Start periodic cleanup jobs
     */
    static startPeriodicCleanup(): void;
}
//# sourceMappingURL=cleanup.service.d.ts.map
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.CleanupService = void 0;
const audio_file_model_1 = require("../models/audio-file.model");
const tts_service_1 = require("./tts.service");
const promises_1 = require("fs/promises");
const fs_1 = require("fs");
class CleanupService {
    /**
     * Clean up expired files (older than 7 days)
     * Should be run periodically (e.g., daily)
     */
    static async cleanupExpiredFiles() {
        try {
            console.log('Starting cleanup of expired files...');
            // Get all expired files
            const expiredFiles = await audio_file_model_1.AudioFileModel.findExpiredFiles();
            if (expiredFiles.length === 0) {
                console.log('No expired files to clean up');
                return;
            }
            console.log(`Found ${expiredFiles.length} expired files to clean up`);
            let cleanedCount = 0;
            let errorCount = 0;
            for (const audioFile of expiredFiles) {
                try {
                    // Delete physical file if it exists
                    if (audioFile.file_name) {
                        const filePath = tts_service_1.TTSService.getFilePath(audioFile.file_name);
                        if ((0, fs_1.existsSync)(filePath)) {
                            await (0, promises_1.unlink)(filePath);
                            console.log(`Deleted file: ${audioFile.file_name}`);
                        }
                    }
                    // Update database status to expired
                    await audio_file_model_1.AudioFileModel.updateStatus(audioFile.id, 'expired');
                    cleanedCount++;
                }
                catch (error) {
                    console.error(`Error cleaning up file ${audioFile.id}:`, error);
                    errorCount++;
                }
            }
            console.log(`Cleanup completed: ${cleanedCount} files cleaned, ${errorCount} errors`);
        }
        catch (error) {
            console.error('Cleanup service error:', error);
        }
    }
    /**
     * Clean up failed generation files (older than 1 hour)
     * These are files that got stuck in 'generating' status
     */
    static async cleanupFailedGenerations() {
        try {
            console.log('Starting cleanup of failed generations...');
            // Get files stuck in generating status for more than 1 hour
            const failedFiles = await audio_file_model_1.AudioFileModel.findStuckGenerations();
            if (failedFiles.length === 0) {
                console.log('No stuck generations to clean up');
                return;
            }
            console.log(`Found ${failedFiles.length} stuck generations to clean up`);
            for (const audioFile of failedFiles) {
                try {
                    // Mark as failed
                    await audio_file_model_1.AudioFileModel.updateStatus(audioFile.id, 'failed');
                    console.log(`Marked stuck generation as failed: ${audioFile.id}`);
                }
                catch (error) {
                    console.error(`Error updating stuck generation ${audioFile.id}:`, error);
                }
            }
        }
        catch (error) {
            console.error('Failed generations cleanup error:', error);
        }
    }
    /**
     * Start periodic cleanup jobs
     */
    static startPeriodicCleanup() {
        // Run expired files cleanup every 6 hours
        setInterval(() => {
            this.cleanupExpiredFiles();
        }, 6 * 60 * 60 * 1000);
        // Run failed generations cleanup every hour
        setInterval(() => {
            this.cleanupFailedGenerations();
        }, 60 * 60 * 1000);
        // Run initial cleanup
        setTimeout(() => {
            this.cleanupExpiredFiles();
            this.cleanupFailedGenerations();
        }, 5000); // Start after 5 seconds
        console.log('Periodic cleanup jobs started');
    }
}
exports.CleanupService = CleanupService;
//# sourceMappingURL=cleanup.service.js.map
import { AudioFileModel } from '../models/audio-file.model';
import { TTSService } from './tts.service';
import { unlink } from 'fs/promises';
import { existsSync } from 'fs';

export class CleanupService {
  /**
   * Clean up expired files (older than 7 days)
   * Should be run periodically (e.g., daily)
   */
  static async cleanupExpiredFiles(): Promise<void> {
    try {
      console.log('Starting cleanup of expired files...');
      
      // Get all expired files
      const expiredFiles = await AudioFileModel.findExpiredFiles();
      
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
            const filePath = TTSService.getFilePath(audioFile.file_name);
            
            if (existsSync(filePath)) {
              await unlink(filePath);
              console.log(`Deleted file: ${audioFile.file_name}`);
            }
          }

          // Update database status to expired
          await AudioFileModel.updateStatus(audioFile.id, 'expired');
          cleanedCount++;

        } catch (error: any) {
          console.error(`Error cleaning up file ${audioFile.id}:`, error);
          errorCount++;
        }
      }

      console.log(`Cleanup completed: ${cleanedCount} files cleaned, ${errorCount} errors`);
      
    } catch (error: any) {
      console.error('Cleanup service error:', error);
    }
  }

  /**
   * Clean up failed generation files (older than 1 hour)
   * These are files that got stuck in 'generating' status
   */
  static async cleanupFailedGenerations(): Promise<void> {
    try {
      console.log('Starting cleanup of failed generations...');
      
      // Get files stuck in generating status for more than 1 hour
      const failedFiles = await AudioFileModel.findStuckGenerations();
      
      if (failedFiles.length === 0) {
        console.log('No stuck generations to clean up');
        return;
      }

      console.log(`Found ${failedFiles.length} stuck generations to clean up`);
      
      for (const audioFile of failedFiles) {
        try {
          // Mark as failed
          await AudioFileModel.updateStatus(audioFile.id, 'failed');
          console.log(`Marked stuck generation as failed: ${audioFile.id}`);
          
        } catch (error: any) {
          console.error(`Error updating stuck generation ${audioFile.id}:`, error);
        }
      }
      
    } catch (error: any) {
      console.error('Failed generations cleanup error:', error);
    }
  }

  /**
   * Start periodic cleanup jobs
   */
  static startPeriodicCleanup(): void {
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
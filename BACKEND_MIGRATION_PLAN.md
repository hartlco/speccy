# Speccy Backend Migration Plan

## Overview
Migrate from iCloud-based sync to a self-hosted backend service that handles TTS generation and file storage, eliminating cross-device sync issues and providing a more reliable user experience.

## Architecture Goals
- **Centralized TTS**: All OpenAI TTS calls happen on backend (cost control, consistency)
- **Reliable Sync**: Backend provides single source of truth for all audio files
- **Simple Auth**: Users authenticate with their OpenAI API token
- **Temporary Storage**: Files stored for 7 days (configurable)
- **Cross-Platform**: Same backend serves macOS and iOS clients

## Technology Stack Recommendation

### Backend: **Node.js + TypeScript**
**Rationale:**
- Fast development and deployment
- Excellent OpenAI SDK support
- Great ecosystem for file handling and APIs
- TypeScript for type safety and maintainability
- Docker-friendly for easy deployment

### Framework: **Fastify**
- High performance (~20% faster than Express)
- Built-in validation and serialization
- TypeScript-first design
- Excellent plugin ecosystem

### Database: **SQLite + Better-SQLite3**
- Zero configuration and maintenance
- Perfect for single-instance deployment
- Fast for read-heavy workloads
- Built-in backup capabilities
- Easy migration to PostgreSQL later if needed

### File Storage: **Local filesystem + cleanup jobs**
- Simple and reliable
- No external dependencies
- Easy backup strategies
- Can migrate to S3/GCS later if needed

## API Design

### Authentication
```
POST /auth/verify
Body: { "openai_token": "sk-..." }
Response: { "user_id": "uuid", "session_token": "jwt" }
```

### TTS Generation & Retrieval
```
POST /tts/generate
Headers: Authorization: Bearer <session_token>
Body: { 
  "text": "content", 
  "voice": "alloy", 
  "model": "tts-1",
  "format": "mp3",
  "speed": 1.0
}
Response: { 
  "file_id": "uuid", 
  "content_hash": "sha256",
  "status": "generating|ready|failed",
  "url": "/files/:file_id",
  "expires_at": "2024-01-01T00:00:00Z"
}

GET /files/:file_id
Headers: Authorization: Bearer <session_token>
Response: Audio file stream

GET /tts/:content_hash/status
Headers: Authorization: Bearer <session_token>
Response: { "status": "generating|ready|failed", "file_id": "uuid?" }

DELETE /tts/:file_id
Headers: Authorization: Bearer <session_token>
Response: { "deleted": true }
```

### User Management
```
GET /user/usage
Headers: Authorization: Bearer <session_token>
Response: { 
  "files_count": 42, 
  "storage_used_mb": 156,
  "generated_today": 5,
  "last_cleanup": "2024-01-01T00:00:00Z"
}
```

## Database Schema

```sql
-- Users table
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  openai_token_hash TEXT UNIQUE NOT NULL,
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  last_seen_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Audio files table  
CREATE TABLE audio_files (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  content_hash TEXT NOT NULL,
  text_content TEXT NOT NULL,
  voice TEXT NOT NULL,
  model TEXT NOT NULL,
  format TEXT NOT NULL,
  speed REAL NOT NULL,
  file_path TEXT,
  file_size INTEGER,
  status TEXT NOT NULL, -- generating, ready, failed, expired
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  expires_at DATETIME NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX idx_audio_files_user_hash ON audio_files(user_id, content_hash);
CREATE INDEX idx_audio_files_expires ON audio_files(expires_at);
CREATE INDEX idx_audio_files_status ON audio_files(status);
```

## Implementation Phases

### Phase 1: Backend Core (Days 1-2)
1. **Project Setup**
   - Initialize Node.js project with TypeScript
   - Set up Fastify server with essential middleware
   - Configure SQLite database with migrations
   - Set up Docker configuration

2. **Authentication System**
   - Implement OpenAI token verification
   - JWT session management
   - User creation and lookup
   - Rate limiting per user

### Phase 2: TTS Service (Days 2-3)  
1. **TTS Generation**
   - OpenAI TTS API integration
   - File storage and management
   - Content hash-based deduplication
   - Background job processing for TTS

2. **File Management**
   - Secure file serving
   - Automatic cleanup jobs (7-day retention)
   - Storage usage tracking
   - Error handling and retries

### Phase 3: Client Integration (Days 3-4)
1. **API Client Layer**
   - Create HTTP client service
   - Authentication flow
   - File caching strategy
   - Error handling and offline mode

2. **Replace iCloud Sync**
   - Remove iCloudSyncManager
   - Update SpeechService to use backend
   - Implement progress tracking for downloads
   - Update UI for backend-based sync status

### Phase 4: Testing & Deployment (Day 5)
1. **Integration Testing**
   - End-to-end client-backend tests
   - Multi-device sync verification
   - Error scenario testing
   - Performance testing

2. **Deployment**
   - Production server setup
   - SSL/TLS configuration
   - Monitoring and logging
   - Backup strategies

## File Structure

```
speccy-backend/
├── src/
│   ├── routes/
│   │   ├── auth.ts
│   │   ├── tts.ts
│   │   └── files.ts
│   ├── services/
│   │   ├── auth.service.ts
│   │   ├── tts.service.ts
│   │   ├── file.service.ts
│   │   └── cleanup.service.ts
│   ├── models/
│   │   ├── user.model.ts
│   │   └── audio-file.model.ts
│   ├── middleware/
│   │   ├── auth.middleware.ts
│   │   └── validation.middleware.ts
│   ├── database/
│   │   ├── migrations/
│   │   └── connection.ts
│   └── app.ts
├── tests/
├── docker/
└── docs/
```

## Client Changes

### New Service: `BackendSyncService`
```swift
class BackendSyncService {
    func authenticate(openAIToken: String) async throws -> Bool
    func generateTTS(text: String, config: TTSConfig) async throws -> AudioFile
    func downloadFile(fileId: String) async throws -> URL
    func checkFileStatus(contentHash: String) async throws -> FileStatus
    func getUserUsage() async throws -> UsageInfo
}
```

### Updated `SpeechService`
- Remove all iCloud sync code
- Replace with `BackendSyncService` calls
- Maintain same public interface for UI compatibility
- Add progress tracking for backend operations

## Migration Strategy

1. **Parallel Development**: Build backend while keeping existing client code
2. **Feature Flag**: Add backend toggle in settings for gradual rollout
3. **Data Migration**: Users can optionally migrate existing TTS files
4. **Gradual Rollout**: Enable backend for beta users first
5. **Full Migration**: Remove iCloud code once backend is stable

## Benefits of New Architecture

✅ **Reliability**: No more cross-device sync issues
✅ **Performance**: Centralized TTS with caching and deduplication  
✅ **Cost Control**: Backend can implement usage limits and monitoring
✅ **Consistency**: Same audio files across all devices immediately
✅ **Simplicity**: Clients become much simpler, just download and play
✅ **Scalability**: Easy to add features like user accounts, sharing, etc.
✅ **Maintenance**: Single codebase handles TTS complexity

## Security Considerations

- OpenAI tokens stored hashed, never in plaintext
- JWT tokens with reasonable expiry times
- Rate limiting to prevent abuse
- File access restricted to file owners
- HTTPS/TLS for all communications
- Regular security audits and updates

## Operational Considerations  

- **Monitoring**: Health checks, error rates, response times
- **Backups**: Database and file backups with retention policy
- **Scaling**: Horizontal scaling plan for multiple instances
- **Updates**: Zero-downtime deployment strategy
- **Costs**: Server costs vs. reduced development complexity

## Next Steps

1. **Approve Plan**: Review and approve this architectural approach
2. **Setup Environment**: Prepare development and deployment environments  
3. **Start Phase 1**: Begin with backend core implementation
4. **Regular Check-ins**: Daily progress reviews and plan adjustments

This migration eliminates the fundamental iCloud sync issues while providing a more robust, scalable, and user-friendly architecture.
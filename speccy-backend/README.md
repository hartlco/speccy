# Speccy Backend Service

A self-hosted backend service for the Speccy TTS app that handles text-to-speech generation via OpenAI's API and manages file storage with automatic cleanup.

## Features

- **User Authentication**: Users authenticate using their OpenAI API tokens
- **TTS Generation**: Proxies requests to OpenAI TTS API with caching
- **File Storage**: 7-day retention policy with automatic cleanup
- **Background Jobs**: Automatic cleanup of expired and failed files
- **Content Hash Deduplication**: Prevents duplicate TTS generation
- **JWT Session Management**: Secure session tokens for API access

## Architecture

The service replaces direct client-side OpenAI API calls and iCloud sync with:
1. Clients authenticate with OpenAI tokens via backend
2. Backend validates tokens and issues JWT session tokens
3. TTS requests are processed by backend using user's OpenAI token
4. Files are stored locally on backend with 7-day expiration
5. Clients download generated files via backend API

## Setup

### Development

1. Install dependencies:
```bash
npm install
```

2. Copy environment configuration:
```bash
cp .env.example .env
```

3. Edit `.env` with your configuration:
```bash
# Database
DATABASE_PATH=./data/speccy.db

# File Storage
STORAGE_PATH=./data/files
FILE_RETENTION_DAYS=7

# JWT Secret (generate with: openssl rand -base64 32)
JWT_SECRET=your-super-secret-jwt-key-here

# Server Configuration
PORT=3000
HOST=0.0.0.0
NODE_ENV=development
```

4. Run database migrations:
```bash
npm run migrate
```

5. Start development server:
```bash
npm run dev
```

### Production

1. Build the application:
```bash
npm run build
```

2. Set production environment variables:
```bash
export NODE_ENV=production
export JWT_SECRET="your-production-jwt-secret"
export DATABASE_PATH="/var/lib/speccy/database.db"
export STORAGE_PATH="/var/lib/speccy/files"
export PORT=3000
```

3. Run migrations:
```bash
npm run migrate
```

4. Start the server:
```bash
npm start
```

### Docker Deployment

```dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production
COPY . .
RUN npm run build
EXPOSE 3000
CMD ["npm", "start"]
```

### Systemd Service

```ini
[Unit]
Description=Speccy Backend Service
After=network.target

[Service]
Type=simple
User=speccy
WorkingDirectory=/opt/speccy-backend
ExecStart=/usr/bin/node dist/app.js
Restart=always
RestartSec=10
Environment=NODE_ENV=production
Environment=JWT_SECRET=your-jwt-secret
Environment=DATABASE_PATH=/var/lib/speccy/database.db
Environment=STORAGE_PATH=/var/lib/speccy/files

[Install]
WantedBy=multi-user.target
```

## API Documentation

### Authentication

#### POST /auth/verify
Authenticate with OpenAI API token and receive session token.

**Request:**
```json
{
  "openai_token": "sk-..."
}
```

**Response (200):**
```json
{
  "user_id": "uuid",
  "session_token": "jwt-token"
}
```

#### POST /auth/refresh
Refresh session token (requires authentication).

**Response (200):**
```json
{
  "user_id": "uuid", 
  "session_token": "new-jwt-token"
}
```

### TTS Generation

#### POST /tts/generate
Generate TTS audio (requires authentication).

**Request:**
```json
{
  "text": "Text to synthesize",
  "voice": "nova",
  "model": "tts-1",
  "format": "mp3",
  "speed": 1.0,
  "openai_token": "sk-..."
}
```

**Response (200):**
```json
{
  "file_id": "uuid",
  "content_hash": "sha256-hash",
  "status": "ready|generating|failed",
  "url": "/files/uuid",
  "expires_at": "2025-09-06T10:00:00Z"
}
```

#### GET /tts/status/:contentHash
Check file status by content hash (requires authentication).

**Response (200):**
```json
{
  "status": "ready|generating|failed|not_found",
  "file_id": "uuid",
  "expires_at": "2025-09-06T10:00:00Z"
}
```

#### DELETE /tts/delete/:fileId
Delete file (requires authentication).

**Response (200):**
```json
{
  "deleted": true
}
```

### File Serving

#### GET /files/:fileId
Download audio file (requires authentication).

Returns the audio file with appropriate Content-Type headers.

### Health Check

#### GET /health
Server health status (no authentication required).

**Response:**
```json
{
  "status": "ok",
  "timestamp": "2025-08-30T10:00:00Z",
  "version": "1.0.0"
}
```

## File Management

- Files are automatically deleted after 7 days (configurable)
- Cleanup jobs run every 6 hours for expired files
- Failed generations are cleaned up every hour
- Content hash deduplication prevents duplicate TTS generation
- Local file cache uses SHA-256 content hashing

## Security

- JWT tokens expire after 7 days
- OpenAI tokens are validated on each TTS request
- User data is isolated by user ID
- Files are served only to authenticated users who own them
- CORS is configured for production origins

## Client Integration

Update your iOS/macOS client to:
1. Use `TTSBackendService` instead of direct OpenAI calls
2. Remove iCloud sync dependencies  
3. Cache files locally as before
4. Handle authentication and file downloads via backend API

## Monitoring

The service logs all requests and errors. Key metrics to monitor:
- Request latency (especially TTS generation)
- File storage usage
- Failed authentication attempts
- Cleanup job performance

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NODE_ENV` | `development` | Environment mode |
| `PORT` | `3000` | Server port |
| `HOST` | `0.0.0.0` | Server host |
| `DATABASE_PATH` | `./data/speccy.db` | SQLite database path |
| `STORAGE_PATH` | `./data/files` | File storage directory |
| `FILE_RETENTION_DAYS` | `7` | Days to keep files |
| `JWT_SECRET` | required | JWT signing secret |
| `LOG_LEVEL` | `info` | Logging level |
| `ALLOWED_ORIGINS` | all in dev | CORS allowed origins |
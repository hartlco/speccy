# Speccy Backend Deployment Guide

## Quick Start

### Development
```bash
npm install
npm run dev
```

### Production with Docker
```bash
# Build and run with Docker Compose
npm run docker:compose:prod
```

## Environment Configuration

### Development
Uses hardcoded `http://localhost:3000` in the iOS app.

### Production
1. **Backend**: Update `.env.production` with your server details
2. **iOS App**: Set `BackendBaseURL` in `Info.plist` or build with production configuration

## Production Deployment Options

### Option 1: Docker Compose (Recommended)
```bash
# 1. Clone the repository
git clone <your-repo>
cd speccy-backend

# 2. Configure environment
cp .env.production .env
# Edit .env with your production values

# 3. Configure SSL certificates (if using nginx)
mkdir ssl
# Copy your SSL certificates to ./ssl/cert.pem and ./ssl/key.pem

# 4. Start services
docker-compose --profile production up -d

# 5. View logs
docker-compose logs -f
```

### Option 2: Direct Node.js Deployment
```bash
# 1. Install dependencies
npm install

# 2. Build TypeScript
npm run build

# 3. Run database migrations
npm run migrate

# 4. Start production server
npm run start:prod
```

### Option 3: Process Manager (PM2)
```bash
# Install PM2 globally
npm install -g pm2

# Start with PM2
pm2 start dist/app.js --name "speccy-backend" --env production

# View logs
pm2 logs speccy-backend

# Restart
pm2 restart speccy-backend
```

## Configuration Files

### Backend Configuration (.env.production)
```bash
NODE_ENV=production
PORT=3000
HOST=0.0.0.0
JWT_SECRET=your-super-secure-jwt-secret-key
ALLOWED_ORIGINS=https://your-domain.com
STORAGE_PATH=/app/data/files
DATABASE_PATH=/app/data/speccy.db
FILE_RETENTION_HOURS=168
LOG_LEVEL=info
```

### iOS App Configuration
In your iOS project's `Info.plist`, set:
```xml
<key>BackendBaseURL</key>
<string>https://your-domain.com</string>
```

Or update the default production URL in `TTSBackendService.swift`:
```swift
// Change this line:
return "https://your-server.com"
// To your actual server URL:
return "https://api.yourapp.com"
```

## SSL/HTTPS Setup

### With Nginx (Recommended)
1. Obtain SSL certificates (Let's Encrypt, Cloudflare, etc.)
2. Update `nginx.conf` with your domain and certificate paths
3. Use the production Docker Compose profile

### With Cloudflare Tunnel (Alternative)
```bash
# Install cloudflared
# Configure tunnel to point to localhost:3000
cloudflared tunnel --url http://localhost:3000
```

## Monitoring & Health Checks

### Health Check Endpoint
```bash
curl https://your-domain.com/health
# Response: {"status":"ok","timestamp":"...","version":"1.0.0"}
```

### Docker Health Checks
Built-in health checks are configured in Docker Compose.

### Logs
```bash
# Docker Compose
docker-compose logs -f speccy-backend

# Direct deployment
tail -f /var/log/speccy-backend.log

# PM2
pm2 logs speccy-backend
```

## Security Considerations

1. **JWT Secret**: Change the default JWT secret to a secure random string
2. **CORS**: Configure allowed origins for production
3. **SSL/TLS**: Always use HTTPS in production
4. **Rate Limiting**: Built-in rate limiting is configured
5. **File Permissions**: Ensure proper file system permissions
6. **Database**: SQLite file should be readable/writable by the app user only

## Scaling Considerations

### Single Instance (Current)
- Good for up to ~1000 concurrent users
- Uses local SQLite database
- Files stored on local filesystem

### Multi-Instance (Future)
- Use PostgreSQL instead of SQLite
- Use shared storage (S3, GCS, etc.) for files
- Use Redis for session storage
- Load balancer with sticky sessions

## Backup Strategy

### Database Backup
```bash
# Create backup
cp data/speccy.db backups/speccy-$(date +%Y%m%d).db

# Automated daily backup (add to crontab)
0 2 * * * cp /app/data/speccy.db /backups/speccy-$(date +\%Y\%m\%d).db
```

### File Storage Backup
```bash
# Backup audio files
tar -czf backups/files-$(date +%Y%m%d).tar.gz data/files/

# Sync to cloud storage
rsync -av data/ your-backup-location/
```

## Troubleshooting

### Common Issues

1. **Port Already in Use**
   ```bash
   # Check what's using port 3000
   lsof -i :3000
   # Kill the process or change PORT in .env
   ```

2. **Permission Denied on Storage**
   ```bash
   # Fix file permissions
   chown -R nodejs:nodejs /app/data
   chmod -R 755 /app/data
   ```

3. **SSL Certificate Issues**
   ```bash
   # Test SSL configuration
   curl -I https://your-domain.com/health
   # Check certificate expiry
   openssl s_client -connect your-domain.com:443 -servername your-domain.com
   ```

4. **High Memory Usage**
   - Monitor for memory leaks
   - Implement file cleanup
   - Consider reducing file retention period

### Debug Mode
```bash
# Enable debug logging
LOG_LEVEL=debug npm start
```

## Performance Optimization

1. **File Cleanup**: Automated cleanup runs every 6 hours
2. **Rate Limiting**: 10 requests/second per IP for general endpoints
3. **Caching**: Content hash-based deduplication prevents duplicate TTS generation
4. **Chunking**: Large texts are automatically chunked for OpenAI processing

## iOS App Updates Required

When deploying to production, update your iOS app:

1. **Set Production URL**: Update `BackendBaseURL` in `Info.plist`
2. **SSL Pinning** (Optional): Add certificate pinning for security
3. **Error Handling**: Ensure proper error handling for network issues
4. **Offline Mode**: Consider caching strategies for offline usage
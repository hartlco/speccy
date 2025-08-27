# CloudKit Migration Guide

## Model Changes Made

The following changes were made to support CloudKit sync:

### SpeechDocument
- Added default values to all non-optional properties
- All properties now CloudKit-compatible

### TTSAudioFile (New Model)
- New model for tracking synced audio files
- All properties have default values for CloudKit compatibility
- **IMPORTANT**: Removed `@Attribute(.unique)` from `contentHash` (CloudKit doesn't support unique constraints)
- Uniqueness is now enforced at application level with duplicate checking

## Potential Migration Issues

Since you're modifying existing SwiftData models, you may encounter:

1. **Model Container Errors**: If you have existing data, SwiftData may need to migrate it
2. **CloudKit Schema Conflicts**: First-time CloudKit sync may take time to set up

## CloudKit Limitations

### Key Constraints:
1. **No Unique Constraints**: CloudKit doesn't support `@Attribute(.unique)`
2. **Default Values Required**: All non-optional properties must have default values
3. **Optional Properties Preferred**: Consider making properties optional when possible

## Troubleshooting Steps

If you encounter "Core Data error" or CloudKit issues:

1. **Clear App Data** (Development only):
   - Delete app from simulator/device
   - Clean Xcode build folder (Cmd+Shift+K)
   - Rebuild and reinstall

2. **CloudKit Dashboard**:
   - Visit [CloudKit Dashboard](https://icloud.developer.apple.com/)
   - Verify "iCloud.com.speccy.documents" container exists
   - Check schema is properly created

3. **Device Requirements**:
   - Ensure device is signed into iCloud
   - CloudKit requires active iCloud account
   - Test on real devices for full CloudKit functionality

## Verification

After running the app:

1. Check console for any ModelContainer errors
2. Verify iCloud status in Settings view shows "Available"
3. Test creating documents on one device
4. Check if they appear on another device signed into same iCloud account

## Configuration Files Updated

### Info.plist
- Added `remote-notification` to `UIBackgroundModes` array
- Required for CloudKit push notifications to work properly

### Entitlements (speccy.entitlements)
- CloudKit capability
- iCloud Documents capability  
- Container identifier: `iCloud.com.speccy.documents`
- Push notification environment (development)

## Known Issues to Fix Next

### 1. Duplicate TTS Generation
**Problem**: If a file is already downloaded on one platform, the app shouldn't request it again from OpenAI and should instead download from CloudKit.

**Current Behavior**: 
- App may generate TTS on both devices for the same text
- Wastes OpenAI API calls and processing time

**Solution Needed**:
- Enhance `isAudioAvailableInSync()` to be used before starting TTS generation
- Add proper sync checking in UI before showing "Generate Audio" options
- Wait for CloudKit sync check before falling back to OpenAI

### 2. Missing CloudKit Operation Logging
**Problem**: No visibility into CloudKit upload/download operations for debugging.

**Current Behavior**:
- Silent CloudKit operations
- Difficult to debug sync issues
- Users don't know when files are being synced

**Solution Needed**:
- Add comprehensive logging for CloudKit file uploads
- Add logging for CloudKit file downloads  
- Add progress indicators in UI for sync operations
- Log sync errors and conflicts

### 3. Missing User Consent for TTS Generation
**Problem**: App automatically generates TTS without asking user permission, especially problematic when same file might be generating on different platform.

**Current Behavior**:
- Automatic TTS generation on download
- No user control over expensive operations
- Potential for duplicate work across devices

**Solution Needed**:
- Add explicit user confirmation before TTS generation
- Show estimated cost/time for TTS generation
- Add setting to control automatic TTS behavior
- Check CloudKit for existing files before prompting user
- Show "Audio available on other device - download instead?" option
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

## Completed Issues ✅

### 1. Duplicate TTS Generation ✅ FIXED
**Problem**: If a file is already downloaded on one platform, the app shouldn't request it again from OpenAI and should instead download from CloudKit.

**Solution Implemented**:
- Enhanced `DocumentDetailView.checkAndStartDownload()` to use `isAudioAvailableInSync()` before TTS generation
- Added async CloudKit sync check before falling back to OpenAI
- Updated UI logic to prevent duplicate TTS generation across devices

### 2. CloudKit Operation Logging ✅ FIXED
**Problem**: No visibility into CloudKit upload/download operations for debugging.

**Solution Implemented**:
- Added comprehensive logging throughout `iCloudSyncManager`:
  - Upload operations with file sizes and progress
  - Download operations with timing and error details
  - Database record creation/updates
  - iCloud availability checks and error conditions
- All CloudKit operations now log start, progress, and completion states
- Enhanced error messages with specific failure reasons

### 3. User Consent for TTS Generation ✅ FIXED
**Problem**: App automatically generates TTS without asking user permission, especially problematic when same file might be generating on different platform.

**Solution Implemented**:
- Created new `TTSConsentManager` service for handling user consent
- Added `TTSConsentDialog` view with cost/time estimates
- Integrated consent checks in both `DocumentDetailView` and `SpeechPlayerView`
- Auto-approves small texts (<100 chars) to avoid friction
- Shows estimated cost (based on OpenAI pricing), time, and chunk count
- Includes CloudKit availability check information
- Users can approve or decline TTS generation with full information
import SwiftUI

struct iCloudStatusView: View {
    @ObservedObject private var syncManager = iCloudSyncManager.shared
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: syncManager.iCloudAvailable ? "icloud" : "icloud.slash")
                .foregroundColor(syncManager.iCloudAvailable ? .green : .red)
            
            Text(syncManager.iCloudAvailable ? "iCloud Available" : "iCloud Unavailable")
                .font(.caption)
                .foregroundColor(syncManager.iCloudAvailable ? .secondary : .red)
            
            if case .syncing = syncManager.syncStatus {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.tertiary)
        .cornerRadius(8)
    }
}

#Preview {
    iCloudStatusView()
}
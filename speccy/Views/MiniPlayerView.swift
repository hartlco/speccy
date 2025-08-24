import SwiftUI

struct MiniPlayerView: View {
    @ObservedObject private var playbackManager = PlaybackManager.shared
    @State private var showingFullPlayer = false
    
    var body: some View {
        if playbackManager.showMiniPlayer {
            VStack(spacing: 0) {
                // Progress bar at top
                ProgressView(value: playbackManager.progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                    .scaleEffect(y: 0.5)
                
                // Mini player content
                HStack(spacing: 12) {
                    // Play/Pause button
                    Button(action: playbackManager.togglePlayback) {
                        Image(systemName: playPauseIcon)
                            .font(.title2)
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    .disabled(playbackManager.isLoading)
                    
                    // Title and status
                    VStack(alignment: .leading, spacing: 2) {
                        Text(playbackManager.currentTitle)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        
                        Text(statusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Stop button
                    Button(action: playbackManager.stopPlayback) {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial)
            }
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 8, y: 4)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .transition(.asymmetric(
                insertion: .move(edge: .bottom).combined(with: .opacity),
                removal: .move(edge: .bottom).combined(with: .opacity)
            ))
            .onTapGesture {
                openFullPlayer()
            }
            .sheet(isPresented: $showingFullPlayer) {
                if let session = playbackManager.openFullPlayer() {
                    SpeechPlayerView(
                        text: session.text,
                        title: session.title,
                        languageCode: session.languageCode,
                        resumeKey: session.resumeKey
                    )
                }
            }
        }
    }
    
    private var playPauseIcon: String {
        if playbackManager.isLoading {
            return "circle.dotted"
        } else if playbackManager.isPlaying {
            return "pause.fill"
        } else {
            return "play.fill"
        }
    }
    
    private var statusText: String {
        if playbackManager.isLoading {
            return "Loading..."
        } else if playbackManager.isPlaying {
            return "Playing"
        } else if playbackManager.isPaused {
            return "Paused"
        } else {
            return "Ready"
        }
    }
    
    private func openFullPlayer() {
        showingFullPlayer = true
    }
}

// MARK: - Mini Player Container

struct MiniPlayerContainer<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            content
            
            MiniPlayerView()
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: PlaybackManager.shared.showMiniPlayer)
    }
}

#Preview {
    MiniPlayerContainer {
        NavigationView {
            List {
                ForEach(0..<10) { i in
                    Text("Item \(i)")
                }
            }
            .navigationTitle("Test")
        }
    }
}
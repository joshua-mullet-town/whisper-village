import SwiftUI

struct WhisperVillageAboutView: View {
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Header with logo
                VStack(spacing: 16) {
                    Image("whisper-village-logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    
                    VStack(spacing: 8) {
                        Text("Whisper Village")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text("Community Voice Dictation")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        
                        Text("Version \(appVersion)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top)
                
                // About Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("About")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Whisper Village is a free, community-focused voice dictation tool built for everyone.")
                        Text("Transform your voice into text instantly with privacy-first, offline processing.")
                        Text("No trials, no limits, no subscriptions - just powerful voice transcription that works.")
                    }
                    .font(.body)
                    .foregroundColor(.primary)
                }
                
                // Features
                VStack(alignment: .leading, spacing: 16) {
                    Text("Features")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        FeatureRow(icon: "mic.fill", title: "Instant Transcription", description: "Real-time voice-to-text with 99% accuracy")
                        FeatureRow(icon: "lock.shield.fill", title: "Privacy First", description: "100% offline - your data never leaves your device")
                        FeatureRow(icon: "keyboard.fill", title: "Global Shortcuts", description: "Quick recording with customizable hotkeys")
                        FeatureRow(icon: "book.fill", title: "Custom Words", description: "Train the AI with your vocabulary")
                        FeatureRow(icon: "doc.text.fill", title: "Full History", description: "Access all your past transcriptions")
                    }
                }
                
                // Community & Support
                VStack(alignment: .leading, spacing: 16) {
                    Text("Community & Support")
                        .font(.headline)
                    
                    VStack(spacing: 12) {
                        Link(destination: URL(string: "mailto:joshua@mullet.town")!) {
                            HStack {
                                Image(systemName: "envelope.fill")
                                Text("joshua@mullet.town")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }
                            .padding()
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Link(destination: URL(string: "https://mullet.town")!) {
                            HStack {
                                Image(systemName: "globe")
                                Text("Visit Mullet Town")
                                Spacer()
                                Image(systemName: "arrow.up.right")
                            }
                            .padding()
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                // Open Source
                VStack(alignment: .leading, spacing: 16) {
                    Text("Open Source")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Whisper Village is built on open source technology:")
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("• whisper.cpp - High-performance AI transcription")
                            Text("• Apple Speech Framework - Native macOS integration") 
                            Text("• GPL v3.0 - Free and open forever")
                            
                            HStack(alignment: .top, spacing: 4) {
                                Text("•")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Forked from VoiceInk - Thanks for all the amazing code!")
                                    
                                    HStack(spacing: 12) {
                                        Link(destination: URL(string: "https://github.com/Beingpax/VoiceInk")!) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "link.circle")
                                                    .font(.system(size: 12))
                                                Text("GitHub")
                                                    .font(.system(size: 12))
                                            }
                                            .foregroundColor(.accentColor)
                                        }
                                        
                                        Link(destination: URL(string: "https://tryvoiceink.com/")!) {
                                            HStack(spacing: 4) {
                                                Image(systemName: "globe.americas")
                                                    .font(.system(size: 12))
                                                Text("Website")
                                                    .font(.system(size: 12))
                                            }
                                            .foregroundColor(.accentColor)
                                        }
                                    }
                                }
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                
                // Footer
                Text("Made with ❤️ by Mullet Town")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top)
                
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.accentColor)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    WhisperVillageAboutView()
}
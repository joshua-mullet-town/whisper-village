import SwiftUI

// Homestead brand colors
extension Color {
    static let homesteadOrange = Color(red: 1.0, green: 0.4, blue: 0.0)
    static let homesteadYellow = Color(red: 1.0, green: 0.8, blue: 0.0)
    static let homesteadGreen = Color(red: 0.0, green: 1.0, blue: 0.4)
    static let homesteadRed = Color(red: 1.0, green: 0.2, blue: 0.2)
    static let homesteadBlack = Color(red: 0.05, green: 0.05, blue: 0.05)
}

struct HomesteadView: View {
    @StateObject private var homesteadManager = HomesteadManager.shared
    @AppStorage("homesteadManagedPort") private var port: Int = 3007

    var body: some View {
        ZStack {
            Color.homesteadBlack.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Main content
                VStack(spacing: 32) {
                    // Logo & Status
                    heroSection

                    // Big launch button
                    launchButton

                    // Quick actions (only when running)
                    if homesteadManager.isServerRunning {
                        quickActions
                    }

                    // Port config
                    portSection
                }
                .padding(40)

                Spacer()

                // Footer
                footer
            }
        }
        .onAppear {
            homesteadManager.refreshStatus()
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 16) {
            // House icon with status glow
            ZStack {
                // Glow effect
                if homesteadManager.isServerRunning {
                    Circle()
                        .fill(Color.homesteadGreen.opacity(0.3))
                        .frame(width: 120, height: 120)
                        .blur(radius: 20)
                }

                // Icon container
                ZStack {
                    Rectangle()
                        .fill(homesteadManager.isServerRunning ? Color.homesteadGreen : Color.homesteadOrange)
                        .frame(width: 80, height: 80)

                    Image(systemName: "house.fill")
                        .font(.system(size: 40, weight: .black))
                        .foregroundStyle(.black)
                }
                .overlay(Rectangle().stroke(.black, lineWidth: 4))
                .offset(x: -4, y: -4)
                .background(
                    Rectangle()
                        .fill(.black)
                        .frame(width: 80, height: 80)
                        .offset(x: 4, y: 4)
                )
            }

            // Title
            VStack(spacing: 4) {
                Text("HOMESTEAD")
                    .font(.system(size: 32, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.homesteadOrange)

                Text("MOBILE COMMAND CENTER")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }

            // Status badge
            HStack(spacing: 8) {
                Circle()
                    .fill(homesteadManager.isServerRunning ? Color.homesteadGreen : Color.homesteadRed)
                    .frame(width: 12, height: 12)

                Text(homesteadManager.isServerRunning ? "ONLINE" : "OFFLINE")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(homesteadManager.isServerRunning ? Color.homesteadGreen : Color.homesteadRed)

                if homesteadManager.isServerRunning {
                    Text(":\(port)")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.black)
            .overlay(
                Rectangle()
                    .stroke(homesteadManager.isServerRunning ? Color.homesteadGreen : Color.homesteadRed, lineWidth: 2)
            )
        }
    }

    // MARK: - Launch Button

    private var launchButton: some View {
        Button(action: { homesteadManager.launchTerminal() }) {
            HStack(spacing: 12) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 20, weight: .bold))

                Text("OPEN HOMESTEAD TERMINAL")
                    .font(.system(size: 16, weight: .black, design: .monospaced))
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(Color.homesteadOrange)
            .overlay(Rectangle().stroke(.black, lineWidth: 4))
        }
        .buttonStyle(.plain)
        .offset(x: -3, y: -3)
        .background(
            Rectangle()
                .fill(.black)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .offset(x: 3, y: 3)
        )
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        HStack(spacing: 16) {
            // Open in browser
            Button(action: { homesteadManager.openInBrowser() }) {
                HStack(spacing: 6) {
                    Image(systemName: "safari")
                        .font(.system(size: 12, weight: .bold))
                    Text("OPEN")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.homesteadGreen)
                .overlay(Rectangle().stroke(.black, lineWidth: 2))
            }
            .buttonStyle(.plain)

            // Copy URL
            Button(action: { homesteadManager.copyURL() }) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .bold))
                    Text("COPY URL")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(Color.homesteadYellow)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black)
                .overlay(Rectangle().stroke(Color.homesteadYellow, lineWidth: 2))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Port Section

    private var portSection: some View {
        HStack(spacing: 12) {
            Text("PORT")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))

            TextField("", value: $port, format: .number)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.homesteadOrange)
                .frame(width: 60)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black)
                .overlay(Rectangle().stroke(Color.homesteadOrange.opacity(0.4), lineWidth: 1))
                .multilineTextAlignment(.center)

            Text("(restart terminal to apply)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 8) {
            Text("Manage Homestead from the terminal")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))

            Text("Install • Update • Start • Stop • Logs")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
        }
        .padding(.bottom, 24)
    }
}

#Preview {
    HomesteadView()
        .frame(width: 700, height: 600)
}

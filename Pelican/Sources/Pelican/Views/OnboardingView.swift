import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(Theme.hud)
                .shadow(color: Theme.hud.opacity(0.6), radius: 10)

            Text("Give Pelican Full Disk Access")
                .font(.title2.weight(.semibold))

            Text("macOS hides parts of your disk (Mail, Messages, Safari, other apps' containers and Time Machine data) from apps without Full Disk Access. Without it, Pelican will under-report how much space is used.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                step(1, "Click “Open System Settings” below.")
                step(2, "Turn on the switch next to Pelican (use + to add it if it isn't listed).")
                step(3, "Return here and click “Check Again”. macOS may ask you to relaunch Pelican.")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))

            HStack {
                Button("Continue Without") { model.dismissOnboarding() }
                Spacer()
                Button("Check Again") { model.recheckFullDiskAccess() }
                Button("Open System Settings") { FullDiskAccess.openSystemSettings() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 520)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(Theme.mono(12, weight: .bold))
                .foregroundStyle(Theme.hud)
                .frame(width: 18, height: 18)
                .overlay(Circle().stroke(Theme.hud, lineWidth: 1))
            Text(text)
        }
    }
}

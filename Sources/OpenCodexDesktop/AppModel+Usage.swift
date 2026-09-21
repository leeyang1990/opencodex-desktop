import Foundation

extension AppModel {
    func loadUsage() async {
        guard isOnline else { return }
        isLoadingUsage = true
        defer { isLoadingUsage = false }
        do {
            usageReport = try await client.usage()
            usageErrorMessage = nil
        } catch {
            // Keep the last successful snapshot visible during a transient refresh failure.
            usageErrorMessage = error.localizedDescription
        }
    }
}

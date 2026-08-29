import Foundation

extension AppModel {
    func saveConnection() async {
        let trimmedHost = connectionHost.trimmingCharacters(in: .whitespacesAndNewlines)
        connectionHost = trimmedHost.isEmpty ? AppConstants.Connection.defaultHost : trimmedHost
        connectionPort = min(
            max(connectionPort, AppConstants.Connection.validPortRange.lowerBound),
            AppConstants.Connection.validPortRange.upperBound
        )
        defaults.set(connectionHost, forKey: "connectionHost")
        defaults.set(connectionPort, forKey: "connectionPort")
        await client.updateConnection(host: connectionHost, port: connectionPort)
        await refresh()
    }

}

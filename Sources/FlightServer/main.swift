import Foundation
import FlightCore
import Hummingbird

ConfigService.ensureDirectories()

let store = SessionStore()
await store.hydrateFromConfig()

let router = buildRouter(store: store)

let port = Int(ProcessInfo.processInfo.environment["FLIGHT_PORT"] ?? "") ?? 7007
let app = Application(
    router: router,
    configuration: .init(
        address: .hostname("0.0.0.0", port: port),
        serverName: "FlightServer"
    )
)

try await app.runService()

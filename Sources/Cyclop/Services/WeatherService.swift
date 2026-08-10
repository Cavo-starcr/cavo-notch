import AppKit
import SwiftUI

/// Current weather for the collapsed notch and the calendar tab.
///
/// Open-Meteo, because it is the one real weather source that needs no key, no
/// account and no contract — WeatherKit wants a paid developer programme, and
/// api.weather.com wants an IBM licence. The city is chosen by hand in the
/// appearance window, which is also what keeps this permission-free: no
/// CoreLocation prompt, no "allow location" dialog, just a name typed once.
///
/// This is the app's first and only network caller, so the rules are strict:
/// it runs only while the switch is on, it speaks to exactly two hosts (the
/// geocoder and the forecast endpoint), and it sends nothing but coordinates.
@MainActor
final class WeatherService: ObservableObject {
    static let shared = WeatherService()

    struct Reading: Equatable {
        let tempC: Double
        let code: Int
        let isDay: Bool

        /// WMO weather code → SF Symbol, day and night variants where they exist.
        var symbol: String {
            switch code {
            case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
            case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
            case 3: return "cloud.fill"
            case 45, 48: return "cloud.fog.fill"
            case 51...57: return "cloud.drizzle.fill"
            case 61...67: return "cloud.rain.fill"
            case 71...77, 85, 86: return "cloud.snow.fill"
            case 80...82: return "cloud.heavyrain.fill"
            case 95...99: return "cloud.bolt.rain.fill"
            default: return "cloud.fill"
            }
        }

        var tempText: String { "\(Int(tempC.rounded()))°" }
    }

    enum Status: Equatable {
        case idle
        case looking
        case ok
        case cityNotFound
        case offline
    }

    @Published private(set) var reading: Reading?
    @Published private(set) var status: Status = .idle
    /// The resolved place name — what the geocoder actually found, shown back so
    /// a typo in the city field is caught by eye rather than by wrong weather.
    @Published private(set) var placeName: String

    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "weather.enabled")
            enabled ? start() : stop()
        }
    }

    private var lat: Double
    private var lon: Double
    private var timer: Timer?

    private init() {
        let d = UserDefaults.standard
        enabled = d.bool(forKey: "weather.enabled")
        placeName = d.string(forKey: "weather.place") ?? ""
        lat = d.double(forKey: "weather.lat")
        lon = d.double(forKey: "weather.lon")
        if enabled { start() }
    }

    // MARK: - Lifecycle

    /// Refreshes now and then every twenty minutes. Weather changes on the hour
    /// scale; anything more frequent is traffic for its own sake. The tolerance
    /// is generous for the same reason the panel's own timers carry one — this
    /// wake-up has no right moment, only a rough one.
    func start() {
        guard enabled, lat != 0 || lon != 0 else { return }
        stop()
        Task { await fetch() }
        let t = Timer(timeInterval: 20 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.fetch() }
        }
        t.tolerance = 120
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Geocoding

    /// Resolves a typed city and, on success, remembers it and fetches at once.
    func setCity(_ name: String) async {
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        status = .looking
        var comps = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        comps.queryItems = [
            .init(name: "name", value: query),
            .init(name: "count", value: "1"),
        ]
        do {
            let (data, _) = try await URLSession.shared.data(from: comps.url!)
            struct Geo: Decodable { let results: [Place]? }
            struct Place: Decodable {
                let latitude: Double
                let longitude: Double
                let name: String
                let country_code: String?
            }
            guard let place = try JSONDecoder().decode(Geo.self, from: data).results?.first else {
                status = .cityNotFound
                return
            }
            lat = place.latitude
            lon = place.longitude
            placeName = [place.name, place.country_code].compactMap { $0 }.joined(separator: ", ")
            let d = UserDefaults.standard
            d.set(lat, forKey: "weather.lat")
            d.set(lon, forKey: "weather.lon")
            d.set(placeName, forKey: "weather.place")
            if enabled { start() } else { await fetch() }
        } catch {
            status = .offline
        }
    }

    // MARK: - Forecast

    private func fetch() async {
        guard lat != 0 || lon != 0 else { return }
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            .init(name: "latitude", value: String(lat)),
            .init(name: "longitude", value: String(lon)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
        ]
        do {
            let (data, _) = try await URLSession.shared.data(from: comps.url!)
            struct Response: Decodable { let current: Current }
            struct Current: Decodable {
                let temperature_2m: Double
                let weather_code: Int
                let is_day: Int
            }
            let current = try JSONDecoder().decode(Response.self, from: data).current
            reading = Reading(
                tempC: current.temperature_2m,
                code: current.weather_code,
                isDay: current.is_day == 1
            )
            status = .ok
        } catch {
            // The last reading stays on screen: twenty-minute-old weather beats
            // a blank wing, and the status line in settings says what happened.
            status = .offline
            NSLog("CAVO Notch: weather fetch failed: \(error.localizedDescription)")
        }
    }
}

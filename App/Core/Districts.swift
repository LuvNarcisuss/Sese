import Foundation

enum DistrictPlaceKind: String, CaseIterable, Codable {
    case street, building, attraction

    var title: String { rawValue.capitalized }
    var plural: String { title + "s" }
}

struct DistrictPlace: Identifiable {
    let id: String
    let kind: DistrictPlaceKind
    let name: String
    let description: String
}

enum DistrictStyle: String, CaseIterable, Codable {
    case desert, snow, forest

    var title: String {
        switch self {
        case .desert: return "Desert"
        case .snow: return "Snow"
        case .forest: return "Forest"
        }
    }

    var artwork: String {
        switch self {
        case .desert: return CityDistrict.sahara.artwork
        case .snow: return CityDistrict.tundra.artwork
        case .forest: return CityDistrict.rainforest.artwork
        }
    }

    func places(for plan: DistrictPlan) -> [DistrictPlace] {
        let options: [(String, String, String, String)]
        switch self {
        case .desert:
            options = [
                ("Saffron Avenue", "Shade sails stretch across a broad avenue lined with spice stalls.",
                 "Copper Lantern Lane", "Copper lanterns lead through a winding lane between sandstone walls."),
                ("Sandstone Library", "A quiet reading room stays cool behind thick sandstone walls.",
                 "Sun Dial Workshop", "A courtyard displays the workshop's sundials, from pocket pieces to a clock as tall as a door."),
                ("Moonstone Oasis", "Stone paths circle a pool where the palms reflect in the water.",
                 "Sunset Dunes", "A ridge above the rooftops is the last place to catch the evening light.")
            ]
        case .snow:
            options = [
                ("Blue Ice Avenue", "Blue ice lines the avenue, with heated benches along its sheltered side.",
                 "Snowbell Lane", "Covered walkways lead past little shops and snowbell-shaped lights."),
                ("Glasshouse Café", "A warm café sits under a glass roof where snow collects at the edges.",
                 "Winter Tram Depot", "The depot shelters the trams and their plows between winter runs."),
                ("Polar Lights Deck", "An open deck faces the northern sky above the last row of houses.",
                 "Crystal Pond", "A trail circles the frozen pond, where ridges in the ice catch the light.")
            ]
        case .forest:
            options = [
                ("Mosswood Lane", "Low stone walls and mossy steps follow the slope of this forest street.",
                 "Vinebridge Way", "Short wooden bridges carry the street over a series of little streams."),
                ("Fern Library", "A reading room above the forest floor opens onto a balcony lined with ferns.",
                 "Rainglass Studio", "A glass-roofed studio collects rainwater into a courtyard pool."),
                ("Firefly Garden", "The path dips into a clearing where fireflies gather at dusk.",
                 "Waterfall Overlook", "A rocky ledge gives a view across the falls and the treetops below.")
            ]
        }
        return zip(DistrictPlaceKind.allCases, options).flatMap { pair -> [DistrictPlace] in
            let (kind, option) = pair
            let prefix = rawValue + "-" + kind.rawValue
            let choices = [DistrictPlace(id: prefix + "-1", kind: kind, name: option.0, description: option.1),
                           DistrictPlace(id: prefix + "-2", kind: kind, name: option.2, description: option.3)]
            return plan.choice(for: kind) == .both ? choices : [choices[plan.choice(for: kind) == .first ? 0 : 1]]
        }
    }
}

enum DistrictPlaceChoice: Int, CaseIterable, Codable {
    case first, second, both
}

struct DistrictPlan: Codable, Equatable {
    var street: DistrictPlaceChoice = .first
    var building: DistrictPlaceChoice = .first
    var attraction: DistrictPlaceChoice = .first

    func choice(for kind: DistrictPlaceKind) -> DistrictPlaceChoice {
        switch kind {
        case .street: return street
        case .building: return building
        case .attraction: return attraction
        }
    }

    mutating func select(_ choice: DistrictPlaceChoice, for kind: DistrictPlaceKind) {
        switch kind {
        case .street: street = choice
        case .building: building = choice
        case .attraction: attraction = choice
        }
    }
}

struct BuiltDistrict: Codable, Identifiable {
    static let price = 120

    let id: UUID
    let name: String
    let style: DistrictStyle
    let plan: DistrictPlan
    let diamonds: Int
    let date: Date

    static func validName(_ input: String) -> String? {
        let name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...30).contains(name.count), name.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        return name
    }

    var mapID: String { id.uuidString }
    var places: [DistrictPlace] { style.places(for: plan) }
}

extension CityDistrict {
    var artwork: String { self == .central ? "background" : rawValue }

    var overview: String {
        switch self {
        case .central: return "Follow the city's transit lines from the market streets to the downtown skyline."
        case .sahara: return "Follow palm-lined avenues into warm stone plazas lit by evening lanterns."
        case .tundra: return "Cross snowy streets and watch elevated trains pass through the city's coldest district."
        case .rainforest: return "Explore misty terraces and suspended paths among layers of tree canopy."
        }
    }

    var places: [DistrictPlace] {
        switch self {
        case .central:
            return [
                .init(id: "station-avenue", kind: .street, name: "Station Avenue", description: "Follow the tram tracks past the ticket hall and into the center of the city."),
                .init(id: "lantern-lane", kind: .street, name: "Lantern Lane", description: "A narrow street connects the evening market to the river beneath strings of lights."),
                .init(id: "central-station", kind: .building, name: "Central Station", description: "The city's transit hub links the downtown concourse with each climate district."),
                .init(id: "city-hall", kind: .building, name: "City Hall", description: "Broad stone steps lead to a public hall with a map of the city set into the floor."),
                .init(id: "skyline-lookout", kind: .attraction, name: "Skyline Lookout", description: "Trains curve between the towers below this open viewpoint at the top of the hill."),
                .init(id: "city-hall-plaza", kind: .attraction, name: "City Hall Plaza", description: "Follow the plaza's broad steps for a view of the downtown skyline and elevated trains.")
            ]
        case .sahara:
            return [
                .init(id: "palm-promenade", kind: .street, name: "Palm Promenade", description: "Palm trees frame an open avenue with shaded benches and views across the district."),
                .init(id: "sandstone-lane", kind: .street, name: "Sandstone Lane", description: "Warm stone walls shade a lane that winds from the market to the dunes."),
                .init(id: "lantern-market", kind: .building, name: "Lantern Market", description: "At sundown, lanterns light the stalls inside a covered sandstone hall."),
                .init(id: "sunstone-pavilion", kind: .building, name: "Sunstone Pavilion", description: "Light spills through the carved roof and moves across the pavilion floor throughout the day."),
                .init(id: "dune-lookout", kind: .attraction, name: "Dune Lookout", description: "The walkway ends above the rooftops where the city gives way to rolling sand."),
                .init(id: "oasis-garden", kind: .attraction, name: "Oasis Garden", description: "Small bridges cross the reflecting pools, and the palms give shade all afternoon.")
            ]
        case .tundra:
            return [
                .init(id: "glacier-walk", kind: .street, name: "Glacier Walk", description: "Snowbanks and blue ice line this sheltered pedestrian route."),
                .init(id: "snowdrift-lane", kind: .street, name: "Snowdrift Lane", description: "Covered entrances and windbreaks make the lane walkable after heavy snow."),
                .init(id: "frostline-station", kind: .building, name: "Frostline Station", description: "Watch trains cross the snow from an elevated platform above the district's streets."),
                .init(id: "ice-conservatory", kind: .building, name: "Ice Conservatory", description: "A glass hall protects cold-weather plants in sheltered beds below the street."),
                .init(id: "aurora-deck", kind: .attraction, name: "Aurora Deck", description: "The deck faces away from the city lights for the clearest view of the night sky."),
                .init(id: "frozen-canal", kind: .attraction, name: "Frozen Canal", description: "Stone crossings lead to the towpath along a canal that freezes in winter.")
            ]
        case .rainforest:
            return [
                .init(id: "fernway", kind: .street, name: "Fernway", description: "A stepped street climbs from the forest floor to the platforms above the ferns."),
                .init(id: "rootbridge-lane", kind: .street, name: "Rootbridge Lane", description: "The lane crosses a stream on low bridges between the exposed roots of tall trees."),
                .init(id: "canopy-observatory", kind: .building, name: "Canopy Observatory", description: "Viewing rooms at three heights show how the forest changes from floor to canopy."),
                .init(id: "rainforest-tram", kind: .building, name: "Rainforest Tram Station", description: "A sheltered terminal connects the low platforms with the highest walkways."),
                .init(id: "canopy-walk", kind: .attraction, name: "Canopy Walk", description: "A suspended walkway crosses the trees and looks down through several levels of canopy."),
                .init(id: "mist-terrace", kind: .attraction, name: "Mist Terrace", description: "Fine mist drifts around platforms woven through the forest at its lowest level.")
            ]
        }
    }
}

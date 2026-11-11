import Foundation

public enum CoverCollection: String, CaseIterable, Sendable {
    case subjects, linen, waves, patterns, botanical, textures, originals
    public var title: String { rawValue.capitalized }
}

/// Stable identifiers stored in the existing coverColorRawValue column.
/// The original five values stay compatible; artwork changes never touch page data.
public enum CoverStyle: String, CaseIterable, Sendable {
    case sage, blue, sand, rose, graphite
    case ivoryLinen = "linen.ivory", peachLinen = "linen.peach", blushLinen = "linen.blush"
    case lavenderLinen = "linen.lavender", blueLinen = "linen.blue", sageLinen = "linen.sage"
    case navyLinen = "linen.navy", charcoalLinen = "linen.charcoal"
    case creamWaves = "waves.cream", roseWaves = "waves.rose", lilacWaves = "waves.lilac"
    case blueWaves = "waves.blue", oliveWaves = "waves.olive", sandWaves = "waves.sand"
    case midnightWaves = "waves.midnight", mistyWaves = "waves.misty"
    case lavenderGingham = "patterns.lavender", blueGingham = "patterns.blue", roseGingham = "patterns.rose"
    case sageGingham = "patterns.sage", gridCover = "patterns.grid", dottedCover = "patterns.dotted"
    case ruledCover = "patterns.ruled", stripedCover = "patterns.stripes"
    case oliveBranches = "botanical.olive", lavenderSprigs = "botanical.lavender", pinkBlossom = "botanical.blossom"
    case tulips = "botanical.tulips", eucalyptus = "botanical.eucalyptus", daisies = "botanical.daisies"
    case blueLeaves = "botanical.blue", forgetMeNots = "botanical.forgetmenots"
    case sunsetClouds = "textures.sunset", blueSky = "textures.sky", whiteMarble = "textures.whiteMarble"
    case roseMarble = "textures.roseMarble", sageMarble = "textures.sageMarble", warmTerrazzo = "textures.warmTerrazzo"
    case coolTerrazzo = "textures.coolTerrazzo", moonlight = "textures.moonlight"
    case mathematicsCover = "subjects.mathematics", scienceCover = "subjects.science", historyCover = "subjects.history"
    case biologyCover = "subjects.biology", chemistryCover = "subjects.chemistry", physicsCover = "subjects.physics"
    case literatureCover = "subjects.literature", geographyCover = "subjects.geography", computingCover = "subjects.computing"
    case economicsCover = "subjects.economics", languagesCover = "subjects.languages", artCover = "subjects.art"

    public var subject: NotebookSubject? {
        guard rawValue.hasPrefix("subjects.") else { return nil }
        return NotebookSubject(rawValue: String(rawValue.dropFirst("subjects.".count)))
    }

    public var artworkIndex: Int? {
        // Freeze the original atlas contract; appended collections never index those tiles.
        guard let index = Self.allCases.firstIndex(of: self), (5..<45).contains(index) else { return nil }
        return index - 5
    }

    public var collection: CoverCollection {
        if subject != nil { return .subjects }
        guard let index = artworkIndex else { return .originals }
        return [.linen, .waves, .patterns, .botanical, .textures][index / 8]
    }

    public var title: String {
        if let subject { return subject.title }
        guard let index = artworkIndex else { return rawValue.capitalized }
        return [
            "Ivory Linen", "Peach Linen", "Blush Linen", "Lavender Linen", "Blue Linen", "Sage Linen", "Navy Linen", "Charcoal Linen",
            "Cream Waves", "Rose Waves", "Lilac Waves", "Blue Waves", "Olive Waves", "Sand Waves", "Midnight Waves", "Misty Waves",
            "Lavender Gingham", "Blue Gingham", "Rose Gingham", "Sage Gingham", "Fine Grid", "Soft Dots", "Ruled Paper", "Blue Stripes",
            "Olive Branches", "Lavender Sprigs", "Pink Blossom", "Tulips", "Eucalyptus", "Daisies", "Blue Leaves", "Forget-Me-Nots",
            "Sunset Clouds", "Blue Sky", "White Marble", "Rose Marble", "Sage Marble", "Warm Terrazzo", "Cool Terrazzo", "Moonlight"
        ][index]
    }

    /// A small consistent color cue for tabs and the editor header.
    public var accentColor: CoverColor {
        if let subject { return subject.accentColor }
        return switch self {
        case .blue, .blueLinen, .navyLinen, .blueWaves, .midnightWaves, .mistyWaves,
             .blueGingham, .stripedCover, .blueLeaves, .forgetMeNots, .blueSky, .coolTerrazzo: .blue
        case .sand, .ivoryLinen, .peachLinen, .creamWaves, .sandWaves, .ruledCover, .whiteMarble, .warmTerrazzo: .sand
        case .rose, .blushLinen, .lavenderLinen, .roseWaves, .lilacWaves, .lavenderGingham,
             .roseGingham, .lavenderSprigs, .pinkBlossom, .tulips, .sunsetClouds, .roseMarble: .rose
        case .graphite, .charcoalLinen, .gridCover, .dottedCover, .moonlight: .graphite
        default: .sage
        }
    }
}

import Foundation

public enum NotebookSubject: String, CaseIterable, Sendable {
    case mathematics, science, history, biology, chemistry, physics
    case literature, geography, computing, economics, languages, art

    public var title: String {
        switch self { case .computing: "Computer Science"; default: rawValue.capitalized }
    }
    public var subtitle: String {
        switch self {
        case .mathematics: "Patterns & proof"
        case .science: "Questions & discovery"
        case .history: "Stories through time"
        case .biology: "Life & living systems"
        case .chemistry: "Elements & reactions"
        case .physics: "Motion & matter"
        case .literature: "Words & worlds"
        case .geography: "Places & perspectives"
        case .computing: "Ideas into programs"
        case .economics: "Choices & connections"
        case .languages: "A world of expression"
        case .art: "Observe & create"
        }
    }
    public var searchTerms: String {
        switch self {
        case .mathematics: "matemáticas matematicas álgebra algebra cálculo calculo geometry geometría"
        case .science: "ciencias ciencia laboratorio discovery"
        case .history: "historia antigüedad civilizaciones history"
        case .biology: "biología biologia botánica botanica life"
        case .chemistry: "química quimica elementos laboratorio"
        case .physics: "física fisica mecánica mecanica energía energia"
        case .literature: "literatura lectura libros lengua poetry"
        case .geography: "geografía geografia mapas mundo earth"
        case .computing: "informática informatica programación programacion computación computacion software"
        case .economics: "economía economia finanzas finanzas negocios business"
        case .languages: "idiomas inglés ingles español frances francés languages"
        case .art: "arte dibujo pintura diseño diseno art"
        }
    }
    public var accentColor: CoverColor {
        switch self {
        case .mathematics, .physics, .languages: .blue
        case .science, .biology, .geography: .sage
        case .history, .economics: .sand
        case .chemistry, .literature, .art: .rose
        case .computing: .graphite
        }
    }
}

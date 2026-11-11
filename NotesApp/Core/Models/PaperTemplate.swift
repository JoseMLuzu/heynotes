import Foundation

public enum TemplateCategory: String, CaseIterable, Sendable {
    case paper, study, planning, productivity
    public var title: String {
        switch self { case .paper: "Notes & Paper"; case .study: "Study"; case .planning: "Planner & Calendar"; case .productivity: "Productivity" }
    }
    public var symbol: String {
        switch self { case .paper: "doc.text"; case .study: "graduationcap"; case .planning: "calendar"; case .productivity: "checklist" }
    }
}

public enum PaperTemplate: String, Codable, CaseIterable, Sendable {
    // Preserve these raw values: existing drawings keep their original paper alignment.
    case blank, ruled, grid
    case dotted, isometric, music
    case cornell, lecture, flashcardSheet, studyPlan
    case dailyPlanner, weeklyPlanner, monthlyCalendar
    case todo, kanban, habitTracker

    public var title: String {
        switch self {
        case .blank: "Blank"; case .ruled: "Ruled"; case .grid: "Grid"
        case .dotted: "Dotted"; case .isometric: "Isometric"; case .music: "Music Staff"
        case .cornell: "Cornell Notes"; case .lecture: "Lecture Notes"
        case .flashcardSheet: "Flashcard Sheet"; case .studyPlan: "Study Plan"
        case .dailyPlanner: "Daily Planner"; case .weeklyPlanner: "Weekly Planner"
        case .monthlyCalendar: "Undated Calendar"; case .todo: "To-Do List"
        case .kanban: "Kanban Board"; case .habitTracker: "Habit Tracker"
        }
    }
    public var category: TemplateCategory {
        switch self {
        case .blank, .ruled, .grid, .dotted, .isometric, .music: .paper
        case .cornell, .lecture, .flashcardSheet, .studyPlan: .study
        case .dailyPlanner, .weeklyPlanner, .monthlyCalendar: .planning
        case .todo, .kanban, .habitTracker: .productivity
        }
    }
    public var detail: String {
        switch self {
        case .blank: "Room for anything."; case .ruled: "Simple lines for everyday notes."
        case .grid: "Structure for equations and diagrams."; case .dotted: "A light guide for ideas and sketches."
        case .isometric: "A guide for spatial drawings."; case .music: "Blank staves for your music."
        case .cornell: "Cues, notes and a summary."; case .lecture: "Subject, date and room to listen."
        case .flashcardSheet: "Four question-and-answer writing cards."; case .studyPlan: "Topics, goals and review dates."
        case .dailyPlanner: "Schedule, priorities and notes."; case .weeklyPlanner: "A little space for every day."
        case .monthlyCalendar: "Fill in any month and year."; case .todo: "One task at a time."
        case .kanban: "To do, doing and done."; case .habitTracker: "An undated 31-day habit sheet."
        }
    }
}

public enum CoverColor: String, Codable, CaseIterable, Sendable {
    case sage, blue, sand, rose, graphite

    public var title: String { rawValue.capitalized }
}

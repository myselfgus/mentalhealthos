import SwiftUI
import Charts
import HealthOSCore

struct SessionData: Identifiable {
    let id: String
    let label: String
    let date: Date?
    let completedStages: Int
}

public struct SessionsChartCard: View {
    let sessions: [PatientSessionIndex]

    public init(sessions: [PatientSessionIndex] = []) {
        self.sessions = sessions
    }

    private var data: [SessionData] {
        sessions.enumerated().map { index, session in
            SessionData(
                id: session.sessionId,
                label: session.date?.healthOSDisplayDate ?? session.sessionId,
                date: session.date.flatMap { ISO8601DateFormatter().date(from: $0) },
                completedStages: session.status.completedCount
            )
        }
        .sorted { lhs, rhs in
            switch (lhs.date, rhs.date) {
            case let (left?, right?): left < right
            case (.some, nil): false
            case (nil, .some): true
            case (nil, nil): lhs.id < rhs.id
            }
        }
    }

    public var body: some View {
        HealthOSPanel {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(
                    title: "Evolução de sessões",
                    subtitle: "Etapas concluídas por sessão",
                    systemImage: "chart.xyaxis.line"
                )

                if data.isEmpty {
                    EmptyStateView(
                        title: "Sem sessões indexadas",
                        message: "Quando pacientes tiverem sessões em patient.json, o progresso do pipeline aparece aqui.",
                        systemImage: "calendar.badge.exclamationmark"
                    )
                    .frame(height: 180)
                } else {
                    Chart(data) { item in
                        BarMark(
                            x: .value("Sessão", item.label),
                            y: .value("Etapas", item.completedStages)
                        )
                        .foregroundStyle(Color.healthPrimary.gradient)
                        .annotation(position: .top) {
                            Text("\(item.completedStages)")
                                .font(.healthCaption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .chartYScale(domain: 0...6)
                    .chartYAxisLabel("Etapas")
                    .frame(height: 220)
                }
            }
        }
    }
}

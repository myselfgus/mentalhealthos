import SwiftUI
import HealthOSCore

struct HealthOSPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            )
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var systemImage: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.healthPrimary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.healthHeadline)
                if let subtitle {
                    Text(subtitle)
                        .font(.healthCaption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.healthHeadline)
            Text(message)
                .font(.healthCallout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(24)
    }
}

struct StatusBadge: View {
    let title: String
    let isComplete: Bool

    var body: some View {
        Label(title, systemImage: isComplete ? "checkmark.circle.fill" : "circle")
            .font(.healthCaption)
            .foregroundStyle(isComplete ? Color.healthPositive : .secondary)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(isComplete ? Color.healthPositive.opacity(0.12) : Color.secondary.opacity(0.08), in: Capsule())
    }
}

struct PipelineProgressBar: View {
    let status: SessionPipelineStatus

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PipelineStage.allCases, id: \.self) { stage in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(status.isComplete(stage) ? Color.healthPrimary : Color.secondary.opacity(0.16))
                    .frame(height: 6)
                    .help(stage.displayName)
            }
        }
        .accessibilityLabel("Pipeline \(status.completedCount) de 6 etapas concluidas")
    }
}

struct MetricRow: View {
    let title: String
    let value: String
    var systemImage: String = "circle.fill"
    var color: Color = .healthPrimary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .frame(width: 20)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
        .font(.healthCallout)
    }
}

extension PatientStatus {
    var displayName: String {
        switch self {
        case .active: "Ativo"
        case .inactive: "Inativo"
        case .archived: "Arquivado"
        case .discharged: "Alta"
        }
    }

    var color: Color {
        switch self {
        case .active: .healthPositive
        case .inactive: .secondary
        case .archived: .orange
        case .discharged: .blue
        }
    }
}

extension PatientArtifactKind {
    var displayName: String {
        switch self {
        case .audio: "Audio"
        case .transcription: "Transcricao"
        case .patientSpeech: "Fala"
        case .asl: "ASL"
        case .vdlp: "VDLP"
        case .gem: "GEM"
        case .clinicalDocument: "Documento"
        case .source: "Fonte"
        case .other: "Outro"
        }
    }
}

extension String {
    var healthOSDisplayDate: String {
        if let date = ISO8601DateFormatter().date(from: self) {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
        return self
    }
}

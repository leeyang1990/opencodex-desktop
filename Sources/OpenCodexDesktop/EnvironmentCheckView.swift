import SwiftUI

struct FirstLaunchEnvironmentCheckView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Label("启动环境检查", systemImage: "checkmark.shield.fill")
                    .font(.title2.weight(.semibold))
                Text("确认 OpenCodex Desktop 可以安全访问本机运行目录，并正确找到 Core 与 Codex CLI。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            EnvironmentCheckList(report: model.environmentReport)

            if model.environmentReport.needsAttention {
                Label("有项目需要处理。你可以稍后在“诊断与修复”中重新检查。", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(AppPalette.warning)
            } else {
                Label("环境检查通过，可以正常使用。", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AppPalette.success)
            }

            HStack {
                Button("重新检查") { model.runEnvironmentCheck() }
                Spacer()
                Button("完成") { model.completeFirstLaunchEnvironmentCheck() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 620)
    }
}

struct EnvironmentCheckList: View {
    let report: EnvironmentCheckReport

    var body: some View {
        VStack(spacing: 0) {
            if report.items.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("正在检查运行环境…")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 10)
            } else {
                ForEach(Array(report.items.enumerated()), id: \.element.id) { index, item in
                    EnvironmentCheckRow(item: item)
                    if index < report.items.count - 1 { Divider() }
                }
            }
        }
    }
}

private struct EnvironmentCheckRow: View {
    let item: EnvironmentCheckItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.callout.weight(.medium))
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    private var symbol: String {
        switch item.state {
        case .passed: "checkmark.circle.fill"
        case .attention: "exclamationmark.triangle.fill"
        case .pending: "clock.fill"
        }
    }

    private var color: Color {
        switch item.state {
        case .passed: AppPalette.success
        case .attention: AppPalette.warning
        case .pending: .secondary
        }
    }
}

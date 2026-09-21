import Foundation

/// Subagents: the small, common workflow for choosing and ordering models.
/// Fallback policy and polling remain in the Core console.
extension AppModel {
    func loadSubagents() async {
        guard isOnline else { return }
        isLoadingSubagents = true
        defer { isLoadingSubagents = false }
        do {
            let selection = try await client.subagentSelection()
            // Keep the user's in-progress order if they are mid-edit when a refresh lands.
            if !isReorderingSubagents {
                subagentModels = selection.chosen
            }
            subagentAvailable = selection.available
            subagentErrorMessage = nil
        } catch {
            subagentErrorMessage = error.localizedDescription
        }
    }

    func isSubagentModelSelected(_ model: String) -> Bool {
        subagentModels.contains(model)
    }

    func toggleSubagentModel(_ model: String) async {
        var next = subagentModels
        if let index = next.firstIndex(of: model) {
            next.remove(at: index)
        } else if next.count < SubagentSelection.maximumChosen {
            next.append(model)
        } else {
            subagentErrorMessage = "最多只能选择 \(SubagentSelection.maximumChosen) 个模型，请先取消一个。"
            return
        }
        await applySubagentSelection(next)
    }

    /// Reorders the chosen models; order is the preference order the Core follows.
    func moveSubagentModel(_ model: String, by offset: Int) async {
        guard let index = subagentModels.firstIndex(of: model) else { return }
        let target = index + offset
        guard subagentModels.indices.contains(target) else { return }
        var next = subagentModels
        next.swapAt(index, target)
        await applySubagentSelection(next)
    }

    func clearSubagentModels() async {
        await applySubagentSelection([])
    }

    private func applySubagentSelection(_ next: [String]) async {
        guard !isUpdatingSubagents else { return }
        isUpdatingSubagents = true
        defer { isUpdatingSubagents = false }
        do {
            try await setSubagentSelectionOperation(next)
            subagentModels = Array(next.prefix(SubagentSelection.maximumChosen))
            // The Core rewrites the Codex catalog, so a running ChatGPT holds a stale list.
            if chatGPT.isRunning { isChatGPTRestartPending = true }
            subagentErrorMessage = nil
            errorMessage = nil
        } catch {
            subagentErrorMessage = error.localizedDescription
        }
    }
}

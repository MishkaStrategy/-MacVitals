from pathlib import Path


def replace_once(path: str, old: str, new: str, label: str) -> None:
    file = Path(path)
    text = file.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected 1 anchor, found {count}")
    file.write_text(text.replace(old, new, 1))


replace_once(
    "MacVitals/Persistence/SettingsStore.swift",
    "  @Published var samplingIntervalOnBattery: Double {\n",
    "  @Published private(set) var samplingInterval: Double\n"
    "  @Published var samplingIntervalOnBattery: Double {\n",
    "active interval property",
)

replace_once(
    "MacVitals/Persistence/SettingsStore.swift",
    "    samplingIntervalOnBattery = samplingIntervals.onBattery\n"
    "    samplingIntervalOnExternalPower = samplingIntervals.onExternalPower\n",
    "    samplingInterval = samplingIntervals.onExternalPower\n"
    "    samplingIntervalOnBattery = samplingIntervals.onBattery\n"
    "    samplingIntervalOnExternalPower = samplingIntervals.onExternalPower\n",
    "active interval initialization",
)

replace_once(
    "MacVitals/Persistence/SettingsStore.swift",
    "  func setNotificationAuthorizationState(_ state: NotificationAuthorizationState) {\n"
    "    notificationAuthorizationState = state\n"
    "  }\n\n",
    "  func setNotificationAuthorizationState(_ state: NotificationAuthorizationState) {\n"
    "    notificationAuthorizationState = state\n"
    "  }\n\n"
    "  func setEffectiveSamplingInterval(_ interval: TimeInterval) {\n"
    "    samplingInterval = SamplingIntervalPolicy.normalized(interval)\n"
    "  }\n\n",
    "active interval setter",
)

replace_once(
    "MacVitals/App/AppDelegate.swift",
    "    coordinator.configureSamplingIntervals(\n"
    "      onBattery: settings.samplingIntervalOnBattery,\n"
    "      onExternalPower: settings.samplingIntervalOnExternalPower)\n"
    "    statusController = StatusItemController(\n",
    "    coordinator.configureSamplingIntervals(\n"
    "      onBattery: settings.samplingIntervalOnBattery,\n"
    "      onExternalPower: settings.samplingIntervalOnExternalPower)\n"
    "    settings.setEffectiveSamplingInterval(coordinator.effectiveSamplingInterval)\n"
    "    statusController = StatusItemController(\n",
    "initial active interval synchronization",
)

replace_once(
    "MacVitals/App/AppDelegate.swift",
    "      .sink { [weak self] interval in\n"
    "        self?.consumptionHistory.restart(interval: interval)\n"
    "      }\n",
    "      .sink { [weak self] interval in\n"
    "        self?.settings.setEffectiveSamplingInterval(interval)\n"
    "        self?.consumptionHistory.restart(interval: interval)\n"
    "      }\n",
    "active interval subscription",
)

pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import QtQuick

Singleton {
  id: root

  // CPU
  property real cpuPercent: 0
  property var cpuPerCore: [] // one 0..100 entry per logical core
  property string cpuUsage: "0%"
  property var prevJiffies: []

  // Memory (bytes)
  property real memPercent: 0
  property real memUsed: 0
  property real memTotal: 0
  property real memAvailable: 0
  property real swapPercent: 0
  property real swapUsed: 0
  property real swapTotal: 0
  property string memoryUsage: "0.0%"
  property string networkInfo: "Disconnected"
  property string networkType: "disconnected"

  // Which power source is online, if any. Empty means running on battery.
  // UPowerDevice exposes no "online" flag, so this comes from sysfs instead.
  property string acSource: ""

  Process {
    id: acProc
    command: ["sh", "-c", "for d in /sys/class/power_supply/*/; do [ -r \"$d/online\" ] || continue; if [ \"$(cat \"$d/online\" 2>/dev/null)\" = 1 ]; then basename \"$d\"; break; fi; done"]
    running: true

    stdout: StdioCollector {
      onStreamFinished: {
        root.acSource = text.trim().split("\n")[0].trim()
      }
    }
  }

  // Battery charge cycles, from the kernel's cycle_count. UPower reports the
  // same number, but Quickshell's UPowerDevice does not expose it. -1 means the
  // pack doesn't report one. It changes slowly, so it is read on demand
  // (the battery popup calls refreshBatteryCycles() when it opens).
  property int batteryCycles: -1

  function refreshBatteryCycles(): void {
    cyclesProc.running = true;
  }

  Process {
    id: cyclesProc
    command: ["sh", "-c", "for f in /sys/class/power_supply/BAT*/cycle_count; do [ -r \"$f\" ] && cat \"$f\" && break; done"]
    running: true

    stdout: StdioCollector {
      onStreamFinished: {
        const n = parseInt(text.trim());
        root.batteryCycles = isNaN(n) ? -1 : n;
      }
    }
  }

  // Battery
  // Read straight from UPower instead of polling /sys. The service pushes
  // property changes, so this costs no polling, and the bar pill and the
  // battery popup can no longer disagree with each other.
  // displayDevice is UPower's synthetic "DisplayDevice" aggregate, which does
  // not carry usable battery numbers (it reports a meaningless percentage).
  // The real pack is the Battery-typed entry in the device list.
  readonly property var device: {
    const all = UPower.devices.values;
    if (all) {
      for (const d of all) {
        if (d.type === UPowerDeviceType.Battery) return d;
      }
    }
    return UPower.displayDevice;
  }

  readonly property bool batteryPresent: device.isPresent
  readonly property int batteryState: device.state
  // Quickshell exposes percentage as a 0..1 fraction, not 0..100.
  readonly property real batteryFraction: device.percentage
  readonly property int batteryLevelRaw: Math.round(device.percentage * 100)
  readonly property string batteryLevel: root.batteryLevelRaw + "%"

  // UPower reports changeRate signed: positive discharging, negative charging.
  readonly property real batteryRate: device.changeRate
  readonly property real batteryWatts: Math.abs(device.changeRate)
  readonly property real batteryTimeToEmpty: device.timeToEmpty
  readonly property real batteryTimeToFull: device.timeToFull
  readonly property real batteryEnergy: device.energy
  readonly property real batteryEnergyFull: device.energyCapacity

  readonly property bool batteryCharging: device.state === UPowerDeviceState.Charging
  readonly property bool batteryFull: device.state === UPowerDeviceState.FullyCharged

  readonly property string batteryStateText: {
    switch (device.state) {
      case UPowerDeviceState.Charging: return "Charging";
      case UPowerDeviceState.Discharging: return "Discharging";
      case UPowerDeviceState.FullyCharged: return "Fully charged";
      case UPowerDeviceState.Empty: return "Empty";
      case UPowerDeviceState.PendingCharge: return "Pending charge";
      case UPowerDeviceState.PendingDischarge: return "Pending discharge";
      default: return "Unknown";
    }
  }

  readonly property string batteryIcon: root.batteryCharging ? ""
    : root.batteryLevelRaw >= 90 ? "󰁹"
    : root.batteryLevelRaw >= 80 ? "󰂂"
    : root.batteryLevelRaw >= 70 ? "󰂁"
    : root.batteryLevelRaw >= 60 ? "󰂀"
    : root.batteryLevelRaw >= 50 ? "󰁿"
    : root.batteryLevelRaw >= 40 ? "󰁾"
    : root.batteryLevelRaw >= 30 ? "󰁽"
    : root.batteryLevelRaw >= 20 ? "󰁼"
    : root.batteryLevelRaw >= 10 ? "󰁻"
    : "󰁺"

  // CPU Usage
  // /proc/stat reports cumulative jiffy counters, so real utilisation needs a
  // delta between two samples. "top -bn1" cannot do this -- in batch mode its
  // single iteration only ever prints the since-boot average.
  Process {
    id: cpuProc
    command: ["sh", "-c", "awk '/^Cpus_allowed_list/{print; exit}' /proc/self/status; cat /proc/stat"]
    running: true

    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.trim().split("\n");

        // This box has 16 online CPUs but qs is pinned to a subset, so the
        // per-core lines for CPUs we cannot run on would sit at 0% forever.
        // Keep only the allowed ones and total those, not the global line.
        let allowed = null;
        if (lines[0] && lines[0].startsWith("Cpus_allowed_list")) {
          allowed = new Set();
          const spec = lines[0].trim().split(/\s+/)[1] || "";
          for (const part of spec.split(",")) {
            const m = part.match(/^(\d+)(?:-(\d+))?$/);
            if (!m) continue;
            const lo = parseInt(m[1]);
            const hi = m[2] !== undefined ? parseInt(m[2]) : lo;
            for (let i = lo; i <= hi; i++) allowed.add(i);
          }
          lines.shift();
        }

        const agg = { total: 0, idle: 0 };
        const cores = [];

        for (const line of lines) {
          if (!line.startsWith("cpu")) continue;
          const p = line.trim().split(/\s+/);
          const isAggregate = p[0] === "cpu";

          if (!isAggregate && allowed) {
            const id = parseInt(p[0].slice(3), 10);
            if (!allowed.has(id)) continue;
          }

          let total = 0;
          for (let i = 1; i < p.length; i++) total += parseFloat(p[i]) || 0;
          // fields: user nice system idle iowait irq softirq steal ...
          // idle + iowait both count as not-busy, matching top
          const idle = (parseFloat(p[4]) || 0) + (parseFloat(p[5]) || 0);

          if (isAggregate) {
            agg.total = total;
            agg.idle = idle;
          } else {
            cores.push({ total: total, idle: idle });
          }
        }

        // index 0 is the aggregate, the rest are the cores we can use
        const now = [agg].concat(cores);

        const prev = root.prevJiffies;
        root.prevJiffies = now;
        // need two matching samples before any delta exists
        if (prev.length !== now.length || now.length < 2) return;

        function busy(cur, old) {
          const dTotal = cur.total - old.total;
          const dIdle = cur.idle - old.idle;
          if (dTotal <= 0) return 0;
          return Math.max(0, Math.min(100, (1 - dIdle / dTotal) * 100));
        }

        const perCore = [];
        for (let i = 1; i < now.length; i++) perCore.push(busy(now[i], prev[i]));

        root.cpuPercent = busy(now[0], prev[0]);
        root.cpuPerCore = perCore;
        root.cpuUsage = Math.round(root.cpuPercent) + "%";
      }
    }
  }

  // Memory Usage
  Process {
    id: memProc
    command: ["sh", "-c", "free -b | awk 'NR==2{printf \"%d %d %d\\n\", $2, $3, $7} NR==3{printf \"%d %d\\n\", $2, $3}'"]
    running: true

    stdout: StdioCollector {
      onStreamFinished: {
        const lines = text.trim().split("\n");
        if (lines.length < 2) return;

        const m = lines[0].trim().split(/\s+/).map(Number);
        const s = lines[1].trim().split(/\s+/).map(Number);

        root.memTotal = m[0] || 0;
        root.memUsed = m[1] || 0;
        root.memAvailable = m[2] || 0;
        root.memPercent = root.memTotal > 0 ? (root.memUsed / root.memTotal) * 100 : 0;
        root.memoryUsage = root.memPercent.toFixed(1) + "%";

        root.swapTotal = s[0] || 0;
        root.swapUsed = s[1] || 0;
        root.swapPercent = root.swapTotal > 0 ? (root.swapUsed / root.swapTotal) * 100 : 0;
      }
    }
  }

  // Network Info (ethernet takes priority over wifi)
  Process {
    id: netProc
    command: ["sh", "-c", "eth=$(nmcli -t -f type,state dev 2>/dev/null | grep '^ethernet:connected'); if [ -n \"$eth\" ]; then echo 'ethernet:Ethernet'; else wifi=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | grep '^yes' | cut -d: -f2); if [ -n \"$wifi\" ]; then echo \"wifi:$wifi\"; else echo 'disconnected:'; fi; fi"]
    running: true

    stdout: StdioCollector {
      onStreamFinished: {
        const result = text.trim()
        const colonIdx = result.indexOf(':')
        const type = result.substring(0, colonIdx)
        const info = result.substring(colonIdx + 1)
        root.networkType = type
        root.networkInfo = info || "Disconnected"
      }
    }
  }

  // CPU needs a short interval to give smooth deltas; the rest can stay lazy.
  Timer {
    interval: 1000
    running: true
    repeat: true
    onTriggered: cpuProc.running = true
  }

  // Update timer
  Timer {
    interval: 2000
    running: true
    repeat: true
    onTriggered: {
      memProc.running = true
      netProc.running = true
      acProc.running = true
    }
  }
}

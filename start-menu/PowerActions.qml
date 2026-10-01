import QtQuick

// Single source of truth for the power actions, shared by the bar's power menu
// and the start menu so the two always list the same options.
QtObject {
  // Codepoints verified against the installed font's own glyph names rather than
  // guessed: F0343 md-logout, F0904 md-power_sleep, F0709 md-restart,
  // F0902 md-power_off.
  readonly property var actions: [
    { key: "lock",     label: "Lock",      icon: String.fromCodePoint(0xF033E), danger: false, instant: true,
      hint: "Lock the screen, keeping everything running",
      cmd: ["sh", "-c", "pidof hyprlock >/dev/null || exec hyprlock"] },
    { key: "logout",   label: "Log out",   icon: String.fromCodePoint(0xF0343), danger: false,
      hint: "End this session and return to the login screen",
      cmd: ["loginctl", "terminate-user", "alltopafi"] },
    { key: "suspend",  label: "Suspend",   icon: String.fromCodePoint(0xF0904), danger: false,
      hint: "Sleep, keeping this session in memory",
      cmd: ["systemctl", "suspend"] },
    { key: "restart",  label: "Restart",   icon: String.fromCodePoint(0xF0709), danger: true,
      hint: "Reboot the machine",
      cmd: ["systemctl", "reboot"] },
    { key: "shutdown", label: "Shut down", icon: String.fromCodePoint(0xF0902), danger: true,
      hint: "Power the machine off",
      cmd: ["systemctl", "poweroff"] }
  ]
}

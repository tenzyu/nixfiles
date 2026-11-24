// KWin/Script, loaded only in the standalone KWin experiment.
// No new global shortcut is allowed to terminate the compositor.
function bind(id, key, callback) {
    if (!registerShortcut("neko5-" + id, "neko5 " + id, key, callback))
        print("neko5: shortcut registration failed: " + key);
}
function launch(name) {
    callDBus("org.freedesktop.systemd1", "/org/freedesktop/systemd1",
             "org.freedesktop.systemd1.Manager", "StartUnit",
             "neko5-kwin-" + name + ".service", "replace");
}
bind("terminal", "Meta+Return", () => launch("terminal"));
bind("launcher", "Meta+Space", () => launch("launcher"));
bind("browser", "Meta+B", () => launch("firefox"));
bind("osu", "Meta+O", () => launch("osu"));
bind("close", "Meta+Q", () => workspace.slotWindowClose());
bind("fullscreen", "Meta+F", () => workspace.slotWindowFullScreen());
bind("left", "Meta+H", () => workspace.slotSwitchWindowLeft());
bind("down", "Meta+J", () => workspace.slotSwitchWindowDown());
bind("up", "Meta+K", () => workspace.slotSwitchWindowUp());
bind("right", "Meta+L", () => workspace.slotSwitchWindowRight());
for (let i = 0; i < 10; i++) {
    const key = String((i + 1) % 10);
    bind("workspace-" + (i + 1), "Meta+" + key, () => {
        const desktop = workspace.desktops[i];
        if (desktop) workspace.currentDesktop = desktop;
    });
    bind("move-workspace-" + (i + 1), "Meta+Shift+" + key, () => {
        const desktop = workspace.desktops[i];
        const window = workspace.activeWindow;
        if (desktop && window) {
            window.desktops = [desktop];
            workspace.currentDesktop = desktop;
        }
    });
}

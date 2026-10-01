pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications

Singleton {
    id: root

    property list<var> notifications: []
    property bool doNotDisturb: false
    readonly property int count: notifications.length
    property int _seqCounter: 0

    // Past notifications for the bar's notification center. The popups above
    // only hold a notification while it is on screen; this outlives that.
    property var history: []      // newest first: { appName, summary, body, urgency, time }
    property int unread: 0
    readonly property int historyLimit: 50

    function removeFromHistory(entry): void {
        root.history = root.history.filter(function(h) { return h !== entry; });
    }

    function clearHistory(): void {
        root.history = [];
        root.unread = 0;
    }

    Component {
        id: notifDataComp
        NotificationData {}
    }

    NotificationServer {
        id: server
        actionsSupported:    true
        bodySupported:       true
        bodyMarkupSupported: true
        imageSupported:      true
        keepOnReload:        false

        onNotification: function(notification) {
            if (root.doNotDisturb) return;

            if (!notification.appName && !notification.summary
                && !notification.body && !notification.image) return;

            notification.tracked = true;

            root.history = [{
                appName: notification.appName || "",
                summary: notification.summary || "",
                body: notification.body || "",
                urgency: notification.urgency,
                time: Date.now()
            }, ...root.history].slice(0, root.historyLimit);
            root.unread += 1;

            const idStr = String(notification.id || "");
            if (idStr !== "") {
                const existing = root.notifications.find(function(n) {
                    return n.notifId === idStr;
                });
                if (existing && !existing.closed) {
                    existing.closed = true;
                    root.notifications = root.notifications.filter(function(n) {
                        return n !== existing;
                    });
                    existing.destroy();
                }
            }

            const data = notifDataComp.createObject(root, {
                notification: notification,
                seqId: String(root._seqCounter++)
            });

            root.notifications = [data, ...root.notifications];

            if (root.notifications.length > 5) {
                root.notifications[root.notifications.length - 1].dismiss();
            }
        }
    }

    function _remove(notifData): void {
        root.notifications = root.notifications.filter(function(n) {
            return n !== notifData;
        });
    }

    function dismiss(notifData): void {
        if (notifData) notifData.dismiss();
    }

    function dismissAll(): void {
        const toRemove = [...root.notifications];
        root.notifications = [];
        for (const n of toRemove) {
            if (!n.closed) {
                n.closed = true;
                if (n.notification) try { n.notification.dismiss(); } catch(e) {}
                n.destroy();
            }
        }
    }
}

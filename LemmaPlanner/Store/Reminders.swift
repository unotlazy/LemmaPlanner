import Foundation
import Observation
import UserNotifications

/// Phone notifications 2 weeks and 3 days before every upcoming deadline of
/// each saved program, and on the last day itself, at 9 in the morning. Only for deadlines with an exact day:
/// a month or an estimated date gets no reminder, since it could be wrong.
@MainActor
final class Reminders {
    static let shared = Reminders()
    static let daysBefore = [14, 3, 0]
    private static let prefix = "deadline."

    private let center = UNUserNotificationCenter.current()

    /// Asks once. When the family says yes, sets the reminders again, since
    /// the ones added before the answer were dropped by iOS.
    func askPermissionIfNeeded(_ state: AppState) {
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                guard granted else { return }
                Task { @MainActor in Reminders.shared.reschedule(state) }
            }
        }
    }

    /// Clears this app's reminders and sets them again from the saved list.
    func reschedule(_ state: AppState) {
        let wanted = state.remindersOn ? Self.requests(for: state) : []
        center.getPendingNotificationRequests { pending in
            let old = pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: old)
            wanted.forEach { center.add($0) }
        }
    }

    /// One notification, sent right away, when a new list moves the dates of
    /// saved programs the family is still considering or applying to.
    func announce(_ changes: [String: String], state: AppState) {
        guard let request = Self.announcement(changes, state: state) else { return }
        center.add(request)
    }

    static func announcement(_ changes: [String: String], state: AppState) -> UNNotificationRequest? {
        guard state.remindersOn else { return nil }
        let programs = state.savedPrograms.filter {
            changes[$0.key] != nil && state.saved[$0.key]?.wantsReminders == true
        }
        guard let first = programs.first else { return nil }
        let content = UNMutableNotificationContent()
        if programs.count == 1 {
            content.title = first.title
            content.body = (changes[first.key] ?? "") + " If it is in your calendar, change it there too."
            content.userInfo = ["key": first.key]
        } else {
            content.title = "Dates changed for \(programs.count) saved programs"
            content.body = programs.map(\.title).joined(separator: ", ")
        }
        content.sound = .default
        return UNNotificationRequest(identifier: "datechange." + programs.map(\.key).joined(separator: ","),
                                     content: content, trigger: nil)
    }

    static func requests(for state: AppState, now: Date = Date(), calendar: Calendar = .current) -> [UNNotificationRequest] {
        var out: [UNNotificationRequest] = []
        for p in state.savedPrograms {
            guard let status = state.saved[p.key], status.wantsReminders else { continue }
            // every deadline still ahead: the family may not open the app between two of them
            let ahead = Schedule(p, today: now, calendar: calendar).steps.filter {
                $0.isDeadline && !$0.isPast && $0.when.isExactDay
            }
            for next in ahead {
                let date = calendar.dateComponents([.year, .month, .day], from: next.when.start)
                let stamp = String(format: "%04d-%02d-%02d", date.year ?? 0, date.month ?? 0, date.day ?? 0)
                for days in daysBefore {
                    guard let day = calendar.date(byAdding: .day, value: -days, to: next.when.start),
                          let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day),
                          fire > now else { continue }
                    let content = UNMutableNotificationContent()
                    let what = next.label.isEmpty ? "Deadline" : next.label
                    switch days {
                    case 0:
                        content.title = "Last day: " + p.title
                        content.body = "\(what) today, \(DateText.when(next.when))."
                    case 3:
                        content.title = p.title
                        content.body = "\(what) in 3 days, on \(DateText.when(next.when))."
                    default:
                        content.title = p.title
                        content.body = "\(what) in 2 weeks, on \(DateText.when(next.when))."
                    }
                    content.sound = .default
                    content.userInfo = ["key": p.key]
                    let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
                    let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                    out.append(UNNotificationRequest(identifier: "\(prefix)\(p.key).\(stamp).\(days)", content: content, trigger: trigger))
                }
            }
        }
        // iOS keeps at most 64 pending notifications per app; keep the soonest.
        return Array(out.sorted { fireDate($0) < fireDate($1) }.prefix(60))
    }

    private static func fireDate(_ r: UNNotificationRequest) -> Date {
        // from the trigger's own date: nextTriggerDate() is nil once the date has passed
        (r.trigger as? UNCalendarNotificationTrigger).flatMap { Calendar.current.date(from: $0.dateComponents) } ?? .distantFuture
    }
}

/// Shows notifications while the app is open too. Without this, iOS drops a
/// notification that arrives with the app in front, and the date-change one
/// usually does. Also notes which notification the family tapped, so the app
/// can open that program.
@MainActor
@Observable
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    /// A tapped notification the app has not opened yet. The key is nil for
    /// the one about several programs.
    struct Tap: Equatable {
        var key: String?
    }
    var tap: Tap?

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let key = response.notification.request.content.userInfo["key"] as? String
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.tap = Tap(key: key) }
            completionHandler()
        }
    }
}

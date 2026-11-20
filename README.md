# Lemma Planner

A free iPhone app for families of STEM students. It asks four questions (grade, subjects, kinds of programs, cost and format), then shows the programs from the Lemma Resources pages that fit, sorted by the next deadline. Families can save programs, mark each one considering, applying, submitted, waitlisted, accepted, not accepted or turned down, add deadlines to their calendar, and get a notification 2 weeks and 3 days before each deadline and on the last day. Tapping a notification opens that program.

The app opens on Home. It shows three numbers (programs on the list, saved, and due in 2 weeks), the deadlines of saved programs, the next deadlines on the list that are not saved yet, programs added in the last 14 days, and a count of saved programs by status.

Search on My list looks through all the programs, in the name, organisation, description, subjects, kind, cost, format and timing. Programs that fit the answers come first. The ones that do not fit are listed under "Not on your list", so a family can find a program they heard about by name.

The look follows lemmacollegecounseling.com: navy and gold on a cream page, serif headings, the Lemma wordmark, and photos from the site. Colours, the logo view and the category icons are in `LemmaPlanner/Views/Theme.swift`. Dark mode uses a deep navy page with gold as the accent. Settings and Home both link to an About screen with the counselor's background and how to start working with Lemma. About and Settings say the app is made by Prager Technologies.

The app points families to Lemma in two places. Home ends with an "About Lemma College Counseling" row that opens the About screen. The page of a summer program, research program, internship, fellowship or scholarship has a "Get help with this application" row, which opens `intake.html` on the site. That row does not show when the grade is College. The rule is `LemmaOffer` in `Theme.swift`.

## Accounts

The app uses the same accounts as the Resources pages on lemmacollegecounseling.com, and it needs one. The first screen asks the family to create an account or log in with one they made on the website. Nothing else shows until that is done. It comes back after logging out, and when the 90-day login runs out. Registering asks for name, email, password, parent or student, grade, an optional mobile number and the two tick boxes from the website. The first screen and the form both link to the Terms of Use and the Privacy Policy. The age tick box has its own sentence for a student ("I am at least 13") and for a parent, because many students in grades 6 and 7 are under 13. The app does not check anyone's age. The site emails a link to confirm the address. If the link opens the website, the family comes back and taps Continue in the app. If iOS opens the link in the app, the app sends the token to the site, which confirms the address and logs the account in. That second way needs three things: the Associated Domains entitlement (`applinks:lemmacollegecounseling.com`, set in `project.yml`), the same capability on the App ID in the Apple developer account, and `.well-known/apple-app-site-association` deployed on the site. This has not been tried on a phone yet.

Apple's guideline 5.1.1(v) asks apps not to require a login for features that do not need one. The list itself needs no account, so App Review may ask why the app does. An earlier version let people read the list first and asked for the account at the first save.

The name is new. The site keeps it in a `name` column of the `signups` table, which `lib/db.js` adds by itself. The website's own forms do not ask for a name, so accounts made there have none. The admin page (`/api/signups`) shows it.

All of this goes through `/api/account` in the LemmaCollegeCounseling repo, into the `signups` table. Logging in sets the site's `lemma_session` cookie, which lasts 90 days and also lets the app download `programs.json`. After that the family logs in again and their list comes back.

The answers and saved programs are kept on the phone and also in the account (the `app_data` column). A change in the app goes up about 2 seconds later. Each time the app opens or comes back to the front it checks the site and takes changes made on another phone or on the website. If the phone also has changes that have not gone up yet, the two are merged: for each saved program the later change wins, and the later set of answers wins. The app keeps a time for each change in `app_data` (`stamps` and `profileAt`) for this. The website saves programs without a time, and those are kept. Logging in on a new phone brings everything back. Start over in Settings clears the answers and saved programs on the account too, and sets `onboarded` to false in `app_data` so every phone asks the questions again.

The grade is in two places on the site: the account's `grade` column, which the website uses, and the app's answers. The site copies a change in either one to the other, so changing the grade in the app changes it on the website, and the other way round. A parent can pick grades 6 to 12, College or Other. A student starts at grade 8, because most students in grades 6 and 7 are under 13. The app stores College as 13, the same as `programs.json`, and Other as 0. Other turns the grade filter off, so the list and the daily email show programs for every grade. The grade does not move up by itself. The app keeps the school year the grade is for (`gradeYear` in `app_data`, where 2026 means September 2026 to August 2027). When a later school year has started, My list asks "Is the student in grade 11 now?" and either answer stops the question until next September. It does not ask when the grade is College or Other. It asks because a student can repeat or skip a year, and because the website can change the grade without changing the year. Logging out clears the phone. Settings → Account edits the details, logs out, and deletes the account, which Apple requires for apps with sign-up. Changing the email or password happens on the website.

To try the app against the site running on this Mac (`npm run dev` in LemmaCollegeCounseling), launch the Debug build with the environment variable `LEMMA_API_BASE=http://localhost:3000`. The program list is read from there too.

## Where the programs come from

The list is `programs.json`, built from the `data/` folder in the LemmaCollegeCounseling repo:

```
cd ../LemmaCollegeCounseling
npm run programs:build -- --app
```

That writes `programs.json` at the site root and copies it into `LemmaPlanner/Resources/`. The app ships with that copy, so it works offline. When the app opens, and when the family comes back to it after 15 minutes or more, it also downloads `https://lemmacollegecounseling.com/programs.json` (that needs the login cookie, so without an account the app stays on the copy it shipped with). The app sends the ETag of the last list it read, so the site answers 304 with no body when nothing changed, and the 350 KB file only comes down when it is new. So fixing a date in `data/` and deploying the site reaches families without a new app release. Pulling down on My list or tapping Check for updates in Settings downloads it right away.

Every morning at 6:00 Boston time, Cloud Scheduler in Google Cloud (job `lemma-daily` in project `lemma-planner-510603`) starts a GitHub Action in the LemmaCollegeCounseling repo (`.github/workflows/daily.yml`). No one needs to be involved. On Mondays it first updates the list: `scripts/refresh-with-gemini.js` asks Gemini on Vertex AI, with Google Search, to check the 80 entries checked longest ago and to look for new programs in two categories, which take turns week by week. It uses a service account, the same way BoostT1D does. Answers that fail the checks are thrown away: no web sources, no page from the program's own site among them, dates it cannot read or more than two years out, deadlines that vanish or jump by more than a year, links that do not open. New programs run by tutoring, test prep or counseling businesses, or only for graduate students, are skipped, and so are programs already on any page. The Action then rebuilds `programs.json`, pushes to main and waits for Vercel to deploy. Every day, Mondays included, it then calls `/api/daily-email`, which sends through iCloud mail. There are two separate emails, each sent only when it has something. The reminders email can come any day: 14 days and 3 days before the deadlines of programs a family saved, and on the last day. The new programs email comes after the Monday update, with new programs in the categories the family picked in the app or on the account page. What changed each week is written to `data/auto-changes.md`. The admin page (`/api/signups`) has buttons to send a test email or today's email right away.

Because nobody checks these updates, the website, the emails and the Terms all say the list is updated by AI and must be confirmed on the official page. The app does not mention AI on its screens. It says that dates, costs and rules can be wrong and must be confirmed on the official page. A program page shows when the entry was last updated (`autoChecked`) and, for programs the weekly update found, when it was added (`added`). A program added in the last 14 days is marked NEW, in the app list, on its page in the app and on the website. The copy built into the app only changes when someone runs the build with `--app` again.

When a new list moves an upcoming deadline of a saved program, the app shows "Dates changed" on that program until the family opens it, and the program page says the old and new date. For programs marked considering or applying, with reminders on, it also sends one notification. Deadline reminders are set again for the new dates. Events the family added to their own calendar do not change, so the note asks them to fix those by hand.

## Building

The Xcode project is generated from `project.yml` with XcodeGen. After adding or removing files, run `xcodegen generate`, then open `LemmaPlanner.xcodeproj`.

Run the tests:

```
xcodebuild test -project LemmaPlanner.xcodeproj -scheme LemmaPlanner -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

The tests do not use the network, the notification center or the cache file. `AppState` takes a stand-in for the site (`AccountServer`), a made-up program list and a download function, and `LemmaPlannerTests/SyncTests.swift` uses them to test login, merging, Start over, the grade question, search and the list download.

## Before the App Store

- A privacy policy URL, screenshots and a description. The App Store privacy answers: the app collects name, email, phone number, and the answers and saved programs (which include the student's grade), linked to the account, for app functionality. `LemmaPlanner/Resources/PrivacyInfo.xcprivacy` says the same and gives the reason the app uses UserDefaults. Keep the two in step. The privacy policy on the site should mention the app.
- Turn on Associated Domains for the App ID, deploy `.well-known/apple-app-site-association` with the site, and try a confirmation email on a real phone.
- App Review needs a test account that is already confirmed. Make one on the site and give its email and password in App Store Connect.
- Deploy `programs.json` on the Lemma site. Until then the app uses the copy built in.
# LemmaPlanner

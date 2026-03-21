# Hawk Translations — Product Context

Distilled from the original PRD. Contains the two sections that remain useful
as living reference during UI development: user personas with daily workflows,
and the permanent out-of-scope boundaries.

Everything else from the PRD (tech stack, data model, feature list, deployment,
build order) has been translated into SCHEMA.md, CONVENTIONS.md, DECISIONS.md,
and ROADMAP.md — which are more accurate, as they reflect what was actually built.

---

## Personas

Four roles exist in the system. For MVP (solo translator), only Team Member is
active. The others are documented here to inform UI decisions — navigation, labels,
and permission affordances should not require rework when collaborators join.

### Platform Admin
The platform owner (initially the developer). Manages all organizations, approves
new org creation, oversees billing across the platform. Has access to everything.

### Org Admin
Manages their organization. Creates and manages teams, handles org-level billing,
assigns novels to teams, invites members.

### Team Admin
Manages a specific team. Invites members to the team, sets novel access levels for
the team, manages team membership.

### Team Member
The primary daily user. Works on novels assigned to their team within the bounds of
their permission level. Translators, editors, and bible keepers all hold this role.
This is the persona all MVP user stories are written against.

---

## Daily Workflows

These narratives informed the feature list and directly shape the UI. Design each
view with the relevant workflow in mind.

### Translator (Primary — the MVP user)

**Morning — picking up where they left off**
- Signs in via Google OAuth
- Lands on dashboard — sees assigned novels, chapter progress, pending jobs at a glance
- Picks the novel they are working on today

**Getting oriented on a novel**
- Opens the novel view
- Checks chapter list — sees what is translated, what is pending, what has been reviewed
- Reviews relevant bible entries before starting a new chapter

**Starting a new chapter**
- Uploads Korean source file for the next chapter
- Triggers PREREAD job
- Monitors job status — running → completed
- Reviews PREREAD output from the job record

**Running translation**
- Triggers translation job for the chapter
- Monitors job status
- Downloads translated output when job completes
- Reviews output against bible entries

**Updating the bible**
- Notices a new character appeared — adds a new character entry
- Corrects an existing terminology entry
- Triggers BIBLE BUILD job if a full rebuild is needed

**End of session**
- Marks chapter status as translated
- Logs out

### Editor (Secondary — future collaborator)
- Signs in, sees novels assigned to their team with editor-level access
- Opens a novel, navigates to chapters marked "translated"
- Downloads translated output to read
- Updates bible entries if they catch inconsistencies
- Marks chapter as reviewed when done
- Cannot trigger pipeline jobs — read and review access only

### Bible Keeper (Tertiary — future collaborator)
- Signs in, goes directly to the bible for their assigned novel
- Reviews recent entries added by the translator
- Searches for a term across the novel to check consistency
- Edits or expands entries as needed
- Uses cross-novel search to check if a term was established in a related series

---

## Novel Access & Permission Levels

A novel is assigned to a team via a `novel_team_assignments` record with a permission
level. Enforcement is deferred until the first collaborator joins — but UI affordances
(disabled buttons, locked states) should be designed with these levels in mind.

| Level | What they can do |
|-------|-----------------|
| **Viewer** | Read translated output and bible entries. No uploads, no jobs. |
| **Editor** | Upload files, update chapter status, edit bible entries. No jobs. |
| **Translator** | Full access including triggering PREREAD, BIBLE BUILD, POST-TRANSLATION REVIEW. |
| **Admin** | Translator access plus manage team assignments for this novel. |

### Discovery Access
A Team Member can see all novels within their org, not just those assigned to their
team. For unassigned novels they see only: title, Korean title, genre, summary, and
point of contact. A novel marked `hidden` does not appear in discovery at all.

---

## Permanent Out-of-Scope Boundaries

These are not deferred — they are explicitly outside the product by design, permanently.

- **Translation logic or prompt content** — remains in the Python pipeline, untouched
- **Modifying translated output files** — translated chapter files are read-only in this app
- **Mobile-native app** — the web app should be readable on mobile, not a native app
- **Commenting on or evaluating translation quality** — not a product feature

---

## Out of Scope for MVP (deferred, not permanent)

These will be built eventually but are not part of Phase 1 or Phase 2:

- Role and permission enforcement (schema built from day one; enforcement deferred)
- Invite flow and org/team onboarding UI
- Pricing tier enforcement and trial limits
- Email or push notifications for job completion
- In-app chapter annotations
- AI-assisted cross-novel summarization
- Formal access request workflow (contact POC is sufficient for now)
- Audit log / change history for bible entries
- Bible import automation beyond the initial one-time migration
- Additional OAuth providers beyond Google

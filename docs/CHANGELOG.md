# Hawk Translations — Changelog

---
## 2026-03-31
Added:
- `app/javascript/controllers/tabs_controller.ts` — tab strip controller; manages active tab class, lazy-loads Turbo Frame panels on first activation, persists selection to `sessionStorage` keyed by novel id
- `spec/system/novel_show_tabs_spec.rb` — 36 system spec examples for M23

Changed:
- `app/views/novels/show.html.erb` — fully rewritten: header block (cover slot, genre badge, title, Korean title, summary, progress bar) + four-tab strip (Chapters, Bible active; Review, Voice Calibration aria-disabled) + two lazy `<turbo-frame>` panels
- `app/assets/stylesheets/_novels.css` — added `.novel-show__header-block`, `.novel-show__genre-badge`, `.novel-show__progress-*`, `.novel-tabs`, `.novel-tab`, `.novel-tab--active`, `.novel-tab--disabled`; mobile rules for cover slot hide and tab strip scroll
- `app/javascript/controllers/index.ts` — registered `tabs` controller
- `spec/system/dashboard_novels_spec.rb` — updated stale novel show assertions (old section testids → tab strip testids)

Note: Committed

## 2026-03-25
Added:
- Sidebar user identity widget (bottom of sidebar): initials avatar, name, and highest-privilege role label
- `User#display_role` — returns Platform Admin > Team Admin > Team Member > No role assigned
- `app/views/components/_user_widget.html.erb` component partial
- Auto-provision workspace and novel assignment for new users
- `app/services/provision_workspace.rb` — idempotent, wrapped in a transaction, guards on `memberships.exists?`
- `app/services/auto_assign_novel.rb` — idempotent via `find_or_create_by!`, no-op if user has no teams

Changed:
- `SessionsController#create` — calls `ProvisionWorkspace` only when `user.previously_new_record?`
- `NovelsController#create` — calls `AutoAssignNovel` after successful save

Note: Committed

## 2026-03-22
Fixed:
- Drag-and-drop, filename preview, drag-over feature in `file_upload_controller.ts`

Changed: N/A
Note: Committed

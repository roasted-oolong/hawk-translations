## 2026-03-25
Added:
- Sidebar user identity widget (bottom of sidebar): initials avatar, name, and highest-privilege role label
- `User#display_role` — returns Platform Admin > Team Admin > Team Member > No role assigned
- `app/views/components/_user_widget.html.erb` component partial
- Auto-provision workspace and novel assignment for new users
- app/services/provision_workspace.rb — idempotent, wrapped in a
  transaction, guards on memberships.exists?
- app/services/auto_assign_novel.rb — idempotent via find_or_create_by!,
  no-op if user has no teams
Changed:
- SessionsController#create — calls ProvisionWorkspace only when
  user.previously_new_record?
- NovelsController#create — calls AutoAssignNovel after successful save
Note: Committed

## 2026-03-22
Fixed: 
- drag-and-drop, filename preview, drag-over feature
Changed: N/A
Note: Committed
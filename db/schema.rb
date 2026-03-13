# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_12_000008) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "role", null: false
    t.bigint "team_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["team_id"], name: "index_memberships_on_team_id"
    t.index ["user_id", "team_id"], name: "index_memberships_on_user_id_and_team_id", unique: true
    t.index ["user_id"], name: "index_memberships_on_user_id"
  end

  create_table "novel_team_assignments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "novel_id", null: false
    t.string "permission_level", null: false
    t.bigint "team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["novel_id", "team_id"], name: "index_novel_team_assignments_on_novel_id_and_team_id", unique: true
    t.index ["novel_id"], name: "index_novel_team_assignments_on_novel_id"
    t.index ["team_id"], name: "index_novel_team_assignments_on_team_id"
  end

  create_table "novels", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "genre"
    t.string "korean_title"
    t.text "notes"
    t.bigint "organization_id", null: false
    t.bigint "poc_user_id"
    t.bigint "series_id"
    t.text "summary"
    t.string "title", null: false
    t.text "tone"
    t.datetime "updated_at", null: false
    t.string "visibility", default: "discoverable", null: false
    t.index ["organization_id"], name: "index_novels_on_organization_id"
    t.index ["poc_user_id"], name: "index_novels_on_poc_user_id"
    t.index ["series_id"], name: "index_novels_on_series_id"
  end

  create_table "organizations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "series", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_series_on_organization_id"
  end

  create_table "teams", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "organization_id", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id"], name: "index_teams_on_organization_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name", null: false
    t.boolean "platform_admin", default: false, null: false
    t.string "provider", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
  end

  add_foreign_key "memberships", "teams"
  add_foreign_key "memberships", "users"
  add_foreign_key "novel_team_assignments", "novels"
  add_foreign_key "novel_team_assignments", "teams"
  add_foreign_key "novels", "organizations"
  add_foreign_key "novels", "series"
  add_foreign_key "novels", "users", column: "poc_user_id"
  add_foreign_key "series", "organizations"
  add_foreign_key "teams", "organizations"
end

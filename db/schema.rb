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

ActiveRecord::Schema[8.1].define(version: 2026_06_08_000001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "vector"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "bible_characters", force: :cascade do |t|
    t.text "aliases"
    t.datetime "created_at", null: false
    t.integer "first_appearance_chapter"
    t.text "honorifics_they_use"
    t.text "honorifics_used_toward"
    t.string "korean_name"
    t.datetime "last_updated_at"
    t.string "name", null: false
    t.text "notes"
    t.bigint "novel_id", null: false
    t.text "physical_description"
    t.text "relationships"
    t.string "role"
    t.string "significance"
    t.text "speech_pattern"
    t.datetime "updated_at", null: false
    t.index ["novel_id"], name: "index_bible_characters_on_novel_id"
  end

  create_table "bible_cultural_phrases", force: :cascade do |t|
    t.text "context"
    t.datetime "created_at", null: false
    t.string "established_translation"
    t.integer "first_appearance_chapter"
    t.text "intended_meaning"
    t.string "korean_phrase"
    t.datetime "last_updated_at"
    t.text "literal_translation"
    t.text "notes"
    t.bigint "novel_id", null: false
    t.string "phrase", null: false
    t.datetime "updated_at", null: false
    t.index ["novel_id"], name: "index_bible_cultural_phrases_on_novel_id"
  end

# Could not dump table "bible_embeddings" because of following StandardError
#   Unknown type 'vector(1024)' for column 'embedding'


  create_table "bible_locations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "first_appearance_chapter"
    t.string "korean_name"
    t.datetime "last_updated_at"
    t.string "location_type"
    t.string "name", null: false
    t.text "notes"
    t.bigint "novel_id", null: false
    t.text "significance"
    t.datetime "updated_at", null: false
    t.index ["novel_id"], name: "index_bible_locations_on_novel_id"
  end

  create_table "bible_story_entries", force: :cascade do |t|
    t.string "category", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.integer "first_appearance_chapter"
    t.datetime "last_updated_at"
    t.text "notes"
    t.bigint "novel_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["novel_id"], name: "index_bible_story_entries_on_novel_id"
  end

  create_table "bible_terminologies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "definition"
    t.integer "first_appearance_chapter"
    t.string "korean_term"
    t.datetime "last_updated_at"
    t.text "notes"
    t.bigint "novel_id", null: false
    t.string "term", null: false
    t.datetime "updated_at", null: false
    t.text "usage_notes"
    t.index ["novel_id"], name: "index_bible_terminologies_on_novel_id"
  end

  create_table "chapters", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "novel_id", null: false
    t.integer "number", null: false
    t.string "status", default: "untranslated", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["novel_id", "number"], name: "index_chapters_on_novel_id_and_number", unique: true
    t.index ["novel_id"], name: "index_chapters_on_novel_id"
  end

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
    t.string "directory_name"
    t.string "genre"
    t.string "korean_title"
    t.text "notes"
    t.bigint "organization_id", null: false
    t.bigint "poc_user_id"
    t.text "preread_dismissed_keys", default: "[]", null: false
    t.bigint "series_id"
    t.text "summary"
    t.string "title", null: false
    t.text "tone"
    t.datetime "updated_at", null: false
    t.string "visibility", default: "discoverable", null: false
    t.index ["organization_id", "directory_name"], name: "index_novels_on_organization_id_and_directory_name", unique: true
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

  create_table "translation_jobs", force: :cascade do |t|
    t.integer "chapter_end"
    t.integer "chapter_start"
    t.datetime "created_at", null: false
    t.string "job_type", null: false
    t.bigint "novel_id", null: false
    t.text "result_payload"
    t.string "solid_queue_job_id"
    t.string "status", default: "queued", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["job_type"], name: "index_translation_jobs_on_job_type"
    t.index ["novel_id", "created_at"], name: "index_translation_jobs_on_novel_id_and_created_at"
    t.index ["novel_id"], name: "index_translation_jobs_on_novel_id"
    t.index ["status"], name: "index_translation_jobs_on_status"
    t.index ["user_id"], name: "index_translation_jobs_on_user_id"
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

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "bible_characters", "novels"
  add_foreign_key "bible_cultural_phrases", "novels"
  add_foreign_key "bible_embeddings", "novels"
  add_foreign_key "bible_embeddings", "organizations"
  add_foreign_key "bible_locations", "novels"
  add_foreign_key "bible_story_entries", "novels"
  add_foreign_key "bible_terminologies", "novels"
  add_foreign_key "chapters", "novels"
  add_foreign_key "memberships", "teams"
  add_foreign_key "memberships", "users"
  add_foreign_key "novel_team_assignments", "novels"
  add_foreign_key "novel_team_assignments", "teams"
  add_foreign_key "novels", "organizations"
  add_foreign_key "novels", "series"
  add_foreign_key "novels", "users", column: "poc_user_id"
  add_foreign_key "series", "organizations"
  add_foreign_key "teams", "organizations"
  add_foreign_key "translation_jobs", "novels"
  add_foreign_key "translation_jobs", "users"
end

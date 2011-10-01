# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended to check this file into your version control system.

ActiveRecord::Schema.define(:version => 20111001044801) do

  create_table "auth_sources", :force => true do |t|
    t.string  "type"
    t.string  "name"
    t.string  "host"
    t.integer "port"
    t.string  "account"
    t.string  "base_dn"
    t.string  "attr_login"
    t.string  "attr_firstname"
    t.string  "attr_lastname"
    t.string  "attr_mail"
    t.string  "attr_member"
    t.boolean "tls"
    t.integer "ordinal",            :default => 100
    t.string  "encrypted_password"
  end

  create_table "controller_devices", :force => true do |t|
    t.integer  "controller_id"
    t.integer  "dependency_id"
    t.string   "ip"
    t.integer  "port"
    t.boolean  "tls",           :default => false
    t.boolean  "udp",           :default => false
    t.integer  "priority",      :default => 0
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "controller_logics", :force => true do |t|
    t.integer  "controller_id"
    t.integer  "dependency_id"
    t.integer  "priority",      :default => 0
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "controller_zones", :force => true do |t|
    t.integer  "controller_id"
    t.integer  "zone_id"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "controllers", :force => true do |t|
    t.string   "name"
    t.text     "description"
    t.boolean  "active",      :default => true
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "dependencies", :force => true do |t|
    t.integer  "dependency_id"
    t.string   "classname"
    t.string   "filename"
    t.string   "module_name"
    t.string   "actual_name"
    t.text     "description"
    t.datetime "version_loaded"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "groups", :force => true do |t|
    t.integer "auth_source_id"
    t.boolean "auth_only",      :default => false
    t.string  "identifier"
    t.string  "description"
    t.text    "notes"
  end

  create_table "rails_admin_histories", :force => true do |t|
    t.text     "message"
    t.string   "username"
    t.integer  "item"
    t.string   "table"
    t.integer  "month",      :limit => 2
    t.integer  "year",       :limit => 8
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "rails_admin_histories", ["item", "table", "month", "year"], :name => "index_rails_admin_histories"

  create_table "settings", :force => true do |t|
    t.integer  "object_id"
    t.string   "object_type"
    t.string   "name"
    t.text     "description"
    t.integer  "value_type"
    t.float    "float_value"
    t.integer  "integer_value"
    t.text     "text_value"
    t.datetime "datetime_value"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "trusted_devices", :force => true do |t|
    t.integer  "user_id"
    t.integer  "controller_id"
    t.string   "trusted_by"
    t.string   "description"
    t.text     "notes"
    t.string   "one_time_key"
    t.datetime "expires"
    t.datetime "last_authenticated"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "user_groups", :force => true do |t|
    t.integer "group_id"
    t.integer "user_id"
    t.boolean "group_admin",   :default => false
    t.boolean "forced",        :default => false
    t.boolean "revoke_access", :default => false
  end

  create_table "user_zones", :force => true do |t|
    t.integer  "user_id"
    t.integer  "zone_id"
    t.integer  "privilege_map"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "users", :force => true do |t|
    t.integer  "auth_source_id"
    t.string   "identifier"
    t.string   "description"
    t.text     "notes"
    t.integer  "privilege_map",   :default => 1
    t.boolean  "system_admin",    :default => false
    t.datetime "created_at"
    t.datetime "updated_at"
    t.string   "firstname"
    t.string   "lastname"
    t.string   "email"
    t.string   "password_digest"
    t.integer  "login_count",     :default => 0
  end

  create_table "zones", :force => true do |t|
    t.string   "name"
    t.text     "description"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

end

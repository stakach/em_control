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

ActiveRecord::Schema.define(:version => 20110507032735) do

  create_table "dependencies", :force => true do |t|
    t.integer "dependency_id"
    t.string  "classname"
    t.string  "filename"
    t.string  "module_name"
    t.string  "actual_name"
    t.text    "description"
  end

  create_table "scheme_devices", :force => true do |t|
    t.integer "scheme_id"
    t.integer "dependency_id"
    t.string  "ip"
    t.integer "port"
    t.boolean "tls",           :default => false
    t.boolean "udp",           :default => false
    t.integer "priority",      :default => 0
  end

  create_table "scheme_logics", :force => true do |t|
    t.integer "dependency_id"
    t.integer "scheme_id"
  end

  create_table "schemes", :force => true do |t|
    t.string  "name"
    t.text    "description"
    t.boolean "active",      :default => true
  end

end

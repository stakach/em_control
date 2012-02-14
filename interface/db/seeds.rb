# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)


auth = AuthSourceLocal.new
auth.name = 'local'
auth.save

user = User.new
user.auth_source_id = auth.id
user.identifier = 'admin'
user.description = 'admin'
user.system_admin = true
user.email = 'admin@local.host'
user.password = 'admin'
user.save


class Group < ActiveRecord::Base
	
	has_many	:user_groups, :dependent => :destroy
	has_many	:users,	:through => :user_groups
	belongs_to	:auth_source
	
end

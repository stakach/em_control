class Group < ActiveRecord::Base
	
	has_many	:user_groups, :dependent => :destroy
	has_many	:users,	:through => :user_groups
	belongs_to	:auth_source
	
end

#
# Mix in any project specific code
#
Group.class_eval &Login.group_mixin unless Login.group_mixin.nil?

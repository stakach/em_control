class Zone < ActiveRecord::Base
	has_many	:user_zones
	has_many	:controller_zones
	
	has_many	:groups, :through => :user_zones
	has_many	:controllers, :through => :controller_zones
end

class Zone < ActiveRecord::Base
	has_many	:user_zones
	has_many	:controller_zones
end

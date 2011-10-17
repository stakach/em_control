class Zone < ActiveRecord::Base
	has_many	:user_zones
	has_many	:controller_zones
	
	has_many	:groups, :through => :user_zones
	has_many	:control_systems, :through => :controller_zones
	
	
	protected
	
	
	validates_presence_of :name
end

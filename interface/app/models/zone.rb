class Zone < ActiveRecord::Base
	has_many	:user_zones
	has_many	:controller_zones
	
	has_many	:groups, :through => :user_zones
	has_many	:control_systems, :through => :controller_zones
	
	has_many :settings, :as => :object,	:dependent => :destroy
	
	
	protected
	
	
	validates_presence_of :name
	validates_uniqueness_of :name
end

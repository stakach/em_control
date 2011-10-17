class ControlSystem < ActiveRecord::Base
	has_many :devices,	:class_name => "ControllerDevice",	:order => 'priority ASC',	:dependent => :destroy
	has_many :logics,	:class_name => "ControllerLogic",	:order => 'priority ASC',	:dependent => :destroy
	
	has_many :controller_zones,		:dependent => :destroy
	has_many :zones,				:through => :controller_zones
	
	has_many :trusted_devices,		:dependent => :destroy
	
	
	protected
	
	
	validates_presence_of :name, :active
end

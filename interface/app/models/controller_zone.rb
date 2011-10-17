class ControllerZone < ActiveRecord::Base
	belongs_to	:control_system
	belongs_to	:zone
	
	
	protected
	
	
	validates_presence_of :control_system, :zone
end

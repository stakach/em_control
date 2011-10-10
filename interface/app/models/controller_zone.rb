class ControllerZone < ActiveRecord::Base
	belongs_to	:control_system
	belongs_to	:zone
end

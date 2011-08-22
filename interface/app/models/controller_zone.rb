class ControllerZone < ActiveRecord::Base
	belongs_to	:controller
	belongs_to	:zone
end

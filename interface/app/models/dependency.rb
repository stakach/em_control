class Dependency < ActiveRecord::Base
	has_many :devices,	:class_name => "ControllerDevice",	:dependent => :destroy
	has_many :logics,	:class_name => "ControllerLogic",	:dependent => :destroy
	
	has_many :settings,	:as => :object,		:dependent => :destroy
	
	scope :for_controller, lambda {|controller|
		includes(:devices, :logics)
		.where("(devices.dependency_id = dependencies.id AND devices.controller_id = ?) OR (logics.dependency_id = dependencies.id AND logics.controller_id = ?)", controller.id, controller.id)
	}
end

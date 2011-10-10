class Dependency < ActiveRecord::Base
	has_many :devices,	:class_name => "ControllerDevice",	:dependent => :destroy
	has_many :logics,	:class_name => "ControllerLogic",	:dependent => :destroy
	
	has_many :settings,	:as => :object,		:dependent => :destroy
	
	scope :for_controller, lambda {|controller|
		includes(:controller_devices, :controller_logics)
		.where("(controller_devices.dependency_id = dependencies.id AND controller_devices.control_system_id = ?) OR (controller_logics.dependency_id = dependencies.id AND controller_logics.control_system_id = ?)", controller.id, controller.id)
	}
end

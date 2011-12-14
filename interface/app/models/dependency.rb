class Dependency < ActiveRecord::Base
	has_many :devices,	:class_name => "ControllerDevice",		:dependent => :destroy
	has_many :logics,	:class_name => "ControllerLogic",		:dependent => :destroy
	has_many :services,	:class_name => "ControllerHttpService",	:dependent => :destroy
	
	has_many :settings,	:as => :object,		:dependent => :destroy
	
	scope :for_controller, lambda {|controller|
		includes(:controller_devices, :controller_logics, :controller_http_services)
		.where("(controller_devices.dependency_id = dependencies.id AND controller_devices.control_system_id = ?) OR (controller_logics.dependency_id = dependencies.id AND controller_logics.control_system_id = ?) OR (controller_http_services.dependency_id = dependencies.id AND controller_http_services.control_system_id = ?)", controller.id, controller.id, controller.id)
	}
	
	
	protected
	
	
	validates_presence_of :classname, :filename, :module_name, :actual_name
	validates_uniqueness_of :filename
	validates_uniqueness_of :actual_name
end

class Dependency < ActiveRecord::Base

	has_many :devices,	:dependent => :destroy
	has_many :logics,		:dependent => :destroy
	has_many :settings,	:as => :object,		:dependent => :destroy
	
	scope :for_controller, lambda {|controller|
		includes(:devices, :logics)
		.where("(devices.dependency_id = dependencies.id AND devices.controller_id = ?) OR (logics.dependency_id = dependencies.id AND logics.controller_id = ?)", controller.id, controller.id)
	}

end

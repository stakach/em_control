class Controller < ActiveRecord::Base

	has_many :devices,	:class_name => "ControllerDevice",	:dependent => :destroy
	has_many :logics,		:class_name => "ControllerLogic",	:dependent => :destroy

end

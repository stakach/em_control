class ControllerLogic < ActiveRecord::Base

	belongs_to	:controller
	belongs_to	:dependency
	has_many :settings, :as => :object,	:dependent => :destroy

end

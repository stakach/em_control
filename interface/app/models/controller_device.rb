class ControllerDevice < ActiveRecord::Base
	belongs_to	:control_system
	belongs_to	:dependency
	has_many :settings, :as => :object,		:dependent => :destroy
end

class ControllerHttpService < ActiveRecord::Base
	belongs_to	:control_system
	belongs_to	:dependency
	has_many :settings, :as => :object,		:dependent => :destroy
	
	protected
	
	validates_presence_of :control_system, :dependency, :uri
end

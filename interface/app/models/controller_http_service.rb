class ControllerHttpService < ActiveRecord::Base
	belongs_to	:control_system
	belongs_to	:dependency
	has_many :settings, :as => :object,		:dependent => :destroy
	
	before_validation :check_uri
	
	protected
	
	def check_uri
		if self[:uri].nil?
			self[:uri] = dependency.default_uri
		end
	end
	
	validates_presence_of :control_system, :dependency, :uri
end

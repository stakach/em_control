class ControllerDevice < ActiveRecord::Base
	belongs_to	:control_system
	belongs_to	:dependency
	has_many :settings, :as => :object,		:dependent => :destroy
	
	
	before_validation :check_port
	
	
	protected
	
	
	def check_port
		if self[:port].nil?
			self[:port] = dependency.default_port
		end
	end
	
	
	validates_presence_of :control_system, :dependency, :ip, :port
end

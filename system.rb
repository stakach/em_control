
module Control
	class System

		@@systems = {}
		
		def self.systems
			@@systems
		end

		def initialize(name)
			@name = name
			@devices = Devices.new
			@controllers = Controllers.new

			@@systems[name] = self
		end

		attr_accessor :devices
		attr_accessor :interfaces
		attr_accessor :controllers
		attr_reader :name
	
	end
end

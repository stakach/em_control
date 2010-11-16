

module Control
	class Controller
		def initialize(name, devices)
			@name = name
			@devices = devices
		end

		attr_accessor :devices
		attr_accessor :interfaces
		attr_reader :name
	
	end
end



module Control
	class Devices
		@@last
		@@connection_information = {}

		def initialize
			@device_list = []
			@device_map = {}
		end	


		
		def self.connections
			@@connection_information
		end

		#
		# device lookup
		#
		def [] (device)
			if device.class == Fixnum
				@device_list[device]
			else
				@device_map[device]
			end
		end
	

		#
		# Map devices name(s) to devices
		#
		def []= (device_id, device)
			if device_id.class == Fixnum
				@device_list[device_id] = device
			else
				@device_map[device_id] = device
			end
		end


		#
		# Add device to the list (load order)
		#
		def << (device)
			@device_list << device
			@@last = device
		end
	

		#
		# Get the last device to be loaded
		#
		def self.last
			@@last
		end
	end
end

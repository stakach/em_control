

module Control
	module Utilities
		#
		# Converts a hex encoded string into a raw byte string
		#
		def hex_to_byte(data)	# Assumes string - converts to binary string
			data.gsub!(/(0x|[^0-9A-Fa-f])*/, "")				# Removes invalid characters
			output = ""
			data = "0#{data}" if data.length % 2 > 0
			data.scan(/.{2}/) { |byte| output << byte.hex}	# Breaks string into an array of characters
			return output
		end
		
		#
		# Converts a raw byte string into a hex encoded string
		#
		def byte_to_hex(data)	# Assumes string - converts from a binary string
			output = ""
			data.each_byte { |c|
				s = c.to_s(16)
				s = "0#{s}" if s.length % 2 > 0
				output << s
			}
			return output
		end
		
		#
		# Converts a string into a byte array
		#
		def str_to_array(data)
			data.bytes.to_a
		end
		
		#
		# Converts an array into a raw byte string
		#
		def array_to_str(data)
			data.pack('c*')
		end
		
		#
		# Creates a new threaded task
		#
		def task(callback = nil, &block)
			if callback.nil?
				EM.defer &block					# Higher performance using blocks?
			else
				EM.defer(nil, callback, &block)
			end
		end
		
		
		#
		# runs an event every so many seconds
		#
		def periodic_timer(time, &block)
			timer = EM::PeriodicTimer.new(time) do
				EM.defer &block
			end
			return timer
		end
		
		#
		# Runs an event once after a particular amount of time
		#
		def one_shot(time, &block)
			timer = EM::Timer.new(time) do
				EM.defer &block
			end
			return timer
		end
		
		
		module_function :hex_to_byte
		module_function :byte_to_hex
		module_function :str_to_array
		module_function :array_to_str
		
		module_function :task
		module_function :periodic_timer
		module_function :one_shot
	end
end
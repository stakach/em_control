# :title:Kramer video switches
#
# Status information avaliable:
# -----------------------------
#
# (built in)
# connected
#
# (module defined)
# num_inputs
# num_outputs
#
# output_1 => input
# output_2
# output_3
#

class KramerSwitch < Control::Device

	def on_load
		
		#
		# Setup constants
		#
		self[:num_inputs] = nil
		self[:num_outputs] = nil
	end

	def connected
		#
		# Get current state of the switcher
		#
		get_machine_type
	end


	commands = {
		:reset_video => 0,
		:switch_video => 1,
		:status_video => 5,
		:define_machine => 62
	}

	def switch(map)
				# instr, inp,  outp, machine number
				# Switch video
		command = [1, 0x80, 0x80, 0xFF]
		
		map.each do |input, output|
			command[1] = 0x80 & input
			command[2] = 0x80 & output
			send(command)
		end
	end
	
	def received(data)
		return nil if data[0] & 0b1000000 == 0	# Check we are the destination

		data[1] = data[1] & 0b1111111	# input
		data[2] = data[2] & 0b1111111	# output

		case data[0] & 0b111111
		when commands[:define_machine]
			if data[1] == 1
				self[:num_inputs] = data[2]
			elsif data[1] == 2
				self[:num_outputs] = data[2]
			end
		when commands[:switch_video]
			self["output_#{data[2]}".to_sym] = data[1]
		end
	end
	
	
	private


	def get_machine_type
				# id com,    video
		command = [62, 0x81, 0x81, 0xFF]
		send(command)	# num inputs
		command[1] = 0x82
		send(command)	# num outputs
	end
end
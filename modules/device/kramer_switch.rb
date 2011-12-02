# :title:Kramer video switches
#
# Status information avaliable:
# -----------------------------
#
# (built in)
# connected
#
# (module defined)
# video_inputs
# video_outputs
#
# video1 => input
# video2
# video3
#

class KramerSwitch < Control::Device

	def on_load
		
		#
		# Setup constants
		#
		#self[:num_inputs] = nil
		#self[:num_outputs] = nil
	end

	def connected
		#
		# Get current state of the switcher
		#
		get_machine_type
	end

	
	COMMANDS = {
		:reset_video => 0,
		:switch_video => 1,
		:status_video => 5,
		:define_machine => 62
	}

	def switch(map)
				# instr, inp,  outp, machine number
				# Switch video
		command = [1, 0x80, 0x80, 0xFF]
		
		map.each do |input, outputs|
			outputs = [outputs] unless outputs.class == Array
			input = input.to_s if input.class == Symbol
			input = input.to_i if input.class == String
			outputs.each do |output|
				command[1] = 0x80 + input
				command[2] = 0x80 + output
				send(command, :wait => false)
				#
				# TODO:: request switcher for output status
				#
				self["video#{output}"] = input
			end
		end
	end
	alias :switch_video :switch
	
	def received(data, command)
		#logger.debug "Kramer sent #{byte_to_hex(data)}"
		
		data = str_to_array(data)
		
		return nil if data[0] & 0b1000000 == 0	# Check we are the destination

		data[1] = data[1] & 0b1111111	# input
		data[2] = data[2] & 0b1111111	# output

		case data[0] & 0b111111
		when COMMANDS[:define_machine]
			if data[1] == 1
				self[:video_inputs] = data[2]
			elsif data[1] == 2
				self[:video_outputs] = data[2]
			end
		when COMMANDS[:status_video]
			self["video#{data[2]}"] = data[1]
		end
		
		return :success
	end
	
	
	private


	def get_machine_type
				# id com,    video
		command = [62, 0x81, 0x81, 0x81]
		send(command)	# num inputs
		command[1] = 0x82
		send(command)	# num outputs
	end
end
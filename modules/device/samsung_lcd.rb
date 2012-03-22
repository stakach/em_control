class SamsungLcd < Control::Device

	#
	# Called on module load complete
	#	Alternatively you can use initialize however will
	#	not have access to settings and this is called
	#	soon afterwards
	#
	def on_load
		#
		# Setup constants
		#
		self[:volume_min] = 0
		self[:volume_max] = 100
	end
	
	def connected
		@polling_timer = schedule.every('60s') do
			logger.debug "Polling Samsung LCD"
			do_poll
		end
	end

	def disconnected
		#
		# Disconnected may be called without calling connected
		#	Hence the check if timer is nil here
		#
		@polling_timer.unschedule unless @polling_timer.nil?
		@polling_timer = nil
	end
	
	
	
	COMMANDS = {
		:power => 0x11,
		:volume => 0x12,
		:input => 0x14,
		:screen_mode => 0x18,
		:screen_size => 0x19,
		:pip_control => 0x3C,
		:auto_adjust => 0x3D,
		:video_wall_mode => 0x5C,
		:safety_lock => 0x5D
	}
	COMMAND_LOOKUP = COMMANDS.invert
	
	
	
	#
	# Power commands
	#
	def power(state)
		power_on? do |result|
			if [On, "on", :on].include?(state)
				if result == Off
					do_send(COMMANDS[:power], 1, :delay => 7)
					logger.debug "LG LCD, requested to power on"
				end
			else
				if result == On
					do_send(COMMANDS[:power], 0, :delay => 7)
					logger.debug "LG LCD, requested to power off"
				end
			end
		end
	end
	
	def power_on?(&block)
		do_send(COMMANDS[:power], nil, {:emit => {:power => block}})
	end
	

	#
	# Input selection
	#
	INPUTS = {
		:vga => 0x14,		# PC or D-SUB in manual
		:component => 0x08,
		:hdmi => 0x21,
		:hdmi1 => 0x21,
		:hdmi2 => 0x23,
		:svideo => 0x04,
		:dvi => 0x18,
		:bnc => 0x1E,
		:composite => 0x0C,
		:display_port => 0x25,
		:tv => 0x40,
		:dtv => 0x40,
		:atv => 0x30,
		:magic_info => 0x20
	}
	INPUT_LOOKUP = INPUTS.invert
	
	def switch_to(input, options = {})
		input = input.to_sym if input.class == String
		
		do_send(COMMANDS[:input], INPUTS[input], options)
	end
	
	
	#
	# Auto adjust
	#
	def auto_adjust
		do_send(COMMANDS[:auto_adjust])
	end
	
	
	def volume(val, options = {})
		val = 100 if val > 100
		val = 0 if val < 0
		
		do_send(COMMANDS[:volume], val, options)
	end
	

	#
	# LCD Response code
	#
	def received(data, command)
		#
		# Get start of text
		#
		data = data.split("\xAA")
		if data.length >= 2
			data = str_to_array(data[-1])	# valid response
		else
			return :ignore	# Invalid data (we shall ignore)
		end
		
		#
		# Check the response is valid
		#
		if not check_sum(data)
			return :failed
		end
		
		#
		# Check if the response was an error
		#
		if data[3] != 0x41
			return :failed
		end
		
		#
		# Extract status value
		#
		command = data[4]
		value = data[5]
		
		#logger.debug "Orion LCD, sent #{data}"
		
		case COMMAND_LOOKUP[command]
			when :power
				power = value == 1
				
				if !self[:power] && power
					self[:warming] = true
					schedule.in('6s') do				# Reactive the interface once the display is online
						self[:warming] = false	# allow access to the display
					end
				end
				
				self[:power] = power
				
			when :volume
				self[:volume] = value
				
			when :input
				self[:input] = INPUT_LOOKUP[value]
				
		end
		
		return :success # Command success
	end


	private
	
	
	def do_poll
		do_send(COMMANDS[:power], nil, :priority => 99)
		do_send(COMMANDS[:volume], nil, :priority => 99)
		do_send(COMMANDS[:input], nil, :priority => 99)
	end
	

	#
	# Builds the command and sends it
	#
	def do_send(command, data = nil, options = {})
		#
		# build the command
		#
		length = data.nil? ? 0 : 1
		command = "\xAA" << command << 0xFF << length
		command << data unless data.nil?
		
		#
		# Generate the checksum
		#
		check = 0
		data[1..-1].each do |byte|
			check += byte
		end
		check = check & 0xFF
		command << check
		
		send(command, options)
	end
	
	
	def check_sum(response)	# Assume already converted to bytes
		check = 0
		response[0..-2].each do |byte|
			check += byte
		end
		check = check & 0xFF
		
		return response[-1] == check
	end
end
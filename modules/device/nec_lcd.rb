class NecLcd < Control::Device

	def initialize *args
		super	# Must be called
		
		#
		# Setup constants
		#
		self[:volume_min] = 0
		self[:volume_max] = 100
		self[:brightness_min] = 0
		self[:brightness_max] = 100
		self[:contrast_min] = 0
		self[:contrast_max] = 100
		#self[:error] = []		TODO!!
	end
	
	def connected
		power_on_delay
		power_indicator
		video_input
		audio_input
		volume_status
		brightness_status
		contrast_status
		mute_status
	end
	

	def power(state)
		type = :command
		message = "C203D6"
		
		if [On, "on", :on].include?(state)
			message += "0001"	# Power On
			self[:power_target] = On
			logger.debug "-- NEC LCD, requested to power on"
		else
			message += "0004"	# Power Off
			self[:power_target] = Off
			logger.debug "-- NEC LCD, requested to power off"
		end
		
		send_checksum(type, message)
	end
	

	INPUTS = {
		:vga => 1,
		:rgbhv => 2,
		:dvi => 3,
		:hdmi_set => 4,	# Set only?
		:video1 => 5,
		:video2 => 6,
		:svideo => 7,
		
		:tv => 10,
		:dvd1 => 12,
		:option => 13,
		:dvd2 => 14,
		:display_port => 15,
		
		:hdmi => 17
	}
	def switch_to(input)
		input = input.to_sym if input.class == String
		self[:target_input] = input
		
		logger.debug "-- NEC LCD, requested to switch to: #{input}"
		
		type = :set_parameter
		message = OPERATION_CODE[:video_input]
		message += INPUTS[input].to_s(16).upcase.rjust(4, '0')	# Value of input as a hex string
		
		send_checksum(type, message)
	end
	
	AUDIO = {
		:audio1 => 1,
		:audio2 => 2,
		:audio3 => 3,
		:hdmi => 4,
		:tv => 6,
		:display_port => 7
	}
	def switch_audio(input)
		input = input.to_sym if input.class == String
		self[:target_audio] = input
		
		logger.debug "-- NEC LCD, requested to switch audio to: #{input}"
		
		type = :set_parameter
		message = OPERATION_CODE[:audio_input]
		message += AUDIO[input].to_s(16).upcase.rjust(4, '0')	# Value of input as a hex string
		
		send_checksum(type, message)
	end
	

	#
	# Volume Modification
	#
	def volume(val)		
		val = 100 if val > 100
		val = 0 if val < 0
		
		logger.debug "-- NEC LCD, requested to change volume to: #{val}"
		
		type = :set_parameter
		message = OPERATION_CODE[:volume_status]
		message += val.to_s(16).upcase.rjust(4, '0')	# Value of input as a hex string
		
		send_checksum(command)
	end
	
	def brightness(val)		
		val = 100 if val > 100
		val = 0 if val < 0
		
		logger.debug "-- NEC LCD, requested to change brightness to: #{val}"
		
		type = :set_parameter
		message = OPERATION_CODE[:brightness_status]
		message += val.to_s(16).upcase.rjust(4, '0')	# Value of input as a hex string
		
		send_checksum(command)
	end
	
	def contrast(val)		
		val = 100 if val > 100
		val = 0 if val < 0
		
		logger.debug "-- NEC LCD, requested to change contrast to: #{val}"
		
		type = :set_parameter
		message = OPERATION_CODE[:contrast_status]
		message += val.to_s(16).upcase.rjust(4, '0')	# Value of input as a hex string
		
		send_checksum(command)
	end
	
	def mute
		logger.debug "-- NEC LCD, requested to mute audio"
		
		type = :set_parameter
		message = OPERATION_CODE[:mute_status]
		message += "0001"	# Value of input as a hex string
		
		send_checksum(type, message)
	end
	
	def unmute
		logger.debug "-- NEC LCD, requested to unmute audio"
		
		type = :set_parameter
		message = OPERATION_CODE[:mute_status]
		message += "0000"	# Value of input as a hex string
		
		send_checksum(type, message)
	end
	

	def received(data)
		#
		# Check for valid response
		#
		if !check_checksum(data)
			logger.debug "-- NEC LCD, checksum failed for command: #{array_to_str(last_command)}"
			logger.info "-- NEC LCD, response was: #{array_to_str(data)}"
			return false
		end
		
		data = array_to_str(data)	# Convert bytes to a string
		
		case MSG_TYPE[data[4]]	# Check the MSG_TYPE (B, D or F)
			when :command_reply
				#
				# Power on and off
				#	8..9 == "00" means no error 
				#	10..15 == "C203D6" Means power comamnd
				if data[10..15] == "C203D6"
					if data[8..9] == "00"
						self[:power] = data[19] == '1'
						if self[:power]
							power_on_delay	# wait until the screen has turned on before sending commands
						end
						return true
					else
						logger.debug "-- NEC LCD, command failed: #{array_to_str(last_command)}"
						logger.info "-- NEC LCD, response was: #{data}"
						return false	# command failed
					end
				end
			when :get_parameter_reply, :set_parameter_reply
				if data[8..9] == "00"
					parse_response(data)
				else
					logger.debug "-- NEC LCD, get or set failed: #{array_to_str(last_command)}"
					logger.info "-- NEC LCD, response was: #{data}"
					return false
				end
		end
		
		return true # As monitor may inform us about other status events
	end


	private
	

	def parse_response(data)
	
		# 14..15 == type (we don't care)
		# 16..19 == Max (we don't care)
		value = data[20..23].to_i(16)

		case data[10..13]
			when "0060" #OPERATION_CODE[:video_input]
				self[:input] = INPUTS.invert[value]
				self[:target_input] = self[:input] if self[:target_input].nil?
				switch_to(self[:target_input]) unless self[:input] == self[:target_input]
				
			when "022E" #OPERATION_CODE[:audio_input]
				self[:audio] = AUDIO.invert[value]
				self[:target_audio] = self[:audio] if self[:target_audio].nil?
				switch_audio(self[:target_audio]) unless self[:audio] == self[:target_audio]
				
			when "0062" #OPERATION_CODE[:volume_status]
				self[:volume] = value
				
			when "0010" #OPERATION_CODE[:brightness_status]
				self[:brightness] = value
				
			when "0012" #OPERATION_CODE[:contrast_status]
				self[:contrast] = value
				
			when "008D" #OPERATION_CODE[:mute_status]
				self[:audio_mute] = value == 1
				
			when "02BE" #OPERATION_CODE[:power_indicator]
				self[:power] = value == 1
				
			when "02D8" #OPERATION_CODE[:power_on_delay]
				self[:warming_remaining] = value
				if value > 0
					self[:warming] = true
					sleep(1)
					power_on_delay
				else
					self[:warming] = false
				end
			else
				logger.debug "-- NEC LCD, unknown response: #{data[10..13]}"
				logger.debug "-- NEC LCD, for command: #{array_to_str(last_command)}"
				logger.info "-- NEC LCD, full response was: #{data}"
		end
	end
	

	MSG_TYPE = {
		:command => 'A',
		'B' => :command_reply,
		:get_parameter => 'C',
		'D' => :get_parameter_reply,
		:set_parameter => 'E',
		'F' => :set_parameter_reply
	}
	

	OPERATION_CODE = {
		:video_input => '0060',
		:audio_input => '022E',
		:volume_status => '0062',
		:mute_status => '008D',
		:power_indicator => '02BE',
		:power_on_delay => '02D8',
		:contrast_status => '0012',
		:brightness_status => '0010'
	}
	#
	# Automatically creates a callable function for each command
	#	http://blog.jayfields.com/2007/10/ruby-defining-class-methods.html
	#	http://blog.jayfields.com/2008/02/ruby-dynamically-define-method.html
	#
	OPERATION_CODE.each_key do |command|
		define_method command do
			type = :get_parameter
			message = OPERATION_CODE[command]
			send_checksum(type, message)
		end
	end


	def check_checksum(data)
		check = 0
		data[1..-3].each do |byte|	# Loop through the second to the third last element
			check = check ^ byte
		end
		return check == data[-2]	# Check the check sum equals the second last element
	end
	

	def send_checksum(type, command, options = {})
		#
		# Prepare command for sending
		#
		command = "".concat(0x02) + command.concat(0x03)
		command = "0*0#{MSG_TYPE[type]}#{command.length.to_s(16).upcase.rjust(2, '0')}#{command}"
		command = str_to_array(command)
		
		check = 0			# NEC SOH byte
		command.each do |byte|	# Loop through all elements
			check = check ^ byte
		end
		
		command << check		# Add checksum
		command << 0x0D			# delimiter required by NEC displays
		command.insert(0, 0x01)	# insert SOH byte
		
		send(command, options)
	end
end
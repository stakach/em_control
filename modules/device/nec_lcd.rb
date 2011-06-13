class NecLcd < Control::Device

	#
	# Called on module load complete
	#	Alternatively you can use initialize however will
	#	not have access to settings and this is called
	#	soon afterwards
	#
	def onLoad
		#
		# Setup constants
		#
		self[:volume_min] = 0
		self[:brightness_min] = 0
		self[:contrast_min] = 0
		#self[:error] = []		TODO!!
	end
	
	def connected
		power_on?
		do_poll
	
		@polling_timer = periodic_timer(30) do
			logger.debug "-- Polling Display"
			do_poll
		end
	end

	def disconnected
		#
		# Disconnected may be called without calling connected
		#	Hence the check if timer is nil here
		#
		@polling_timer.cancel unless @polling_timer.nil?
	end
	

	#
	# Power commands
	#
	def power(state)
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
		
		send_checksum(:command, message)
	end
	
	def power_on?
		type = :command
		message = "01D6"
		send_checksum(type, message, {:emit => :power})
	end
	

	#
	# Input selection
	#
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
		#self[:target_input] = input
		
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
		#self[:target_audio] = input
		
		logger.debug "-- NEC LCD, requested to switch audio to: #{input}"
		
		type = :set_parameter
		message = OPERATION_CODE[:audio_input]
		message += AUDIO[input].to_s(16).upcase.rjust(4, '0')	# Value of input as a hex string
		
		send_checksum(type, message)
	end
	
	
	#
	# Auto adjust
	#
	def auto_adjust
		message = "001E"	# Page + OP code
		message += "0001"	# Value of input as a hex string
		
		send_checksum(:set_parameter, message)
	end
	

	#
	# Value based set parameter
	#
	def brightness(val)
		val = 100 if val > 100
		val = 0 if val < 0

		message = OPERATION_CODE[:brightness_status]
		message += val.to_s(16).upcase.rjust(4, '0')	# Value of input as a hex string
		
		brightness_status
		send_checksum(:set_parameter, message)
		send_checksum(:command, '0C')	# Save the settings
	end
	
	def contrast(val)
		val = 100 if val > 100
		val = 0 if val < 0
		
		message = OPERATION_CODE[:contrast_status]
		message += val.to_s(16).upcase.rjust(4, '0')	# Value of input as a hex string
		
		contrast_status
		send_checksum(:set_parameter, message)
		send_checksum(:command, '0C')	# Save the settings
	end
	
	def volume(val)
		val = 100 if val > 100
		val = 0 if val < 0
		
		message = OPERATION_CODE[:volume_status]
		message += val.to_s(16).upcase.rjust(4, '0')	# Value of input as a hex string
		
		volume_status
		send_checksum(:set_parameter, message)
		send_checksum(:command, '0C')	# Save the settings
	end
	
	def mute
		logger.debug "-- NEC LCD, requested to mute audio"
		
		message = OPERATION_CODE[:mute_status]
		message += "0001"	# Value of input as a hex string
		
		send_checksum(:set_parameter, message)
	end
	
	def unmute
		logger.debug "-- NEC LCD, requested to unmute audio"

		message = OPERATION_CODE[:mute_status]
		message += "0000"	# Value of input as a hex string
		
		send_checksum(:set_parameter, message)
	end
	

	#
	# LCD Response code
	#
	def received(data)
		#
		# Check for valid response
		#
		if !check_checksum(data)
			logger.debug "-- NEC LCD, checksum failed for command: #{array_to_str(last_command)}"
			logger.debug "-- NEC LCD, response was: #{array_to_str(data)}"
			return false
		end
		
		data = array_to_str(data)	# Convert bytes to a string
		
		case MSG_TYPE[data[4]]	# Check the MSG_TYPE (B, D or F)
			when :command_reply
				#
				# Power on and off
				#	8..9 == "00" means no error 
				if data[10..15] == "C203D6"	# Means power comamnd
					if data[8..9] == "00"
						self[:power] = data[19] == '1'
						if self[:power]
							power_on_delay	# wait until the screen has turned on before sending commands
						end
					else
						logger.info "-- NEC LCD, command failed: #{array_to_str(last_command)}"
						logger.info "-- NEC LCD, response was: #{data}"
						return false	# command failed
					end
				elsif data[10..13] == "00D6"	# Power status response
					if data[10..11] == "00"
						self[:power] = data[23] == '1'		# Value == 1
						if self[:power_target].nil?
							self[:power_target] = self[:power]
						elsif self[:power_target] != self[:power]
							power(self[:power_target])
						end
					else
						logger.info "-- NEC LCD, command failed: #{array_to_str(last_command)}"
						logger.info "-- NEC LCD, response was: #{data}"
						return false	# command failed
					end
				
				end
				
			when :get_parameter_reply, :set_parameter_reply
				if data[8..9] == "00"
					parse_response(data)
				elsif data[8..9] == 'BE'	# Wait response
					sleep(2)
					send(last_command)
					logger.debug "-- NEC LCD, response was a wait command"
				else
					logger.info "-- NEC LCD, get or set failed: #{array_to_str(last_command)}"
					logger.info "-- NEC LCD, response was: #{data}"
					return false
				end
		end
		
		return true # As monitor may inform us about other status events
	end
	

	def do_poll
		power_on_delay
		video_input
		audio_input
		volume_status
		brightness_status
		contrast_status
		mute_status
	end


	private
	

	def parse_response(data)
	
		# 14..15 == type (we don't care)
		max = data[16..19].to_i(16)
		value = data[20..23].to_i(16)

		case OPERATION_CODE[data[10..13]]
			when :video_input
				self[:input] = INPUTS.invert[value]
				#self[:target_input] = self[:input] if self[:target_input].nil?
				#switch_to(self[:target_input]) unless self[:input] == self[:target_input]
				
			when :audio_input
				self[:audio] = AUDIO.invert[value]
				#self[:target_audio] = self[:audio] if self[:target_audio].nil?
				#switch_audio(self[:target_audio]) unless self[:audio] == self[:target_audio]
				
			when :volume_status
				self[:volume_max] = max
				self[:volume] = value
				
			when :brightness_status
				self[:brightness_max] = max
				self[:brightness] = value
				
			when :contrast_status
				self[:contrast_max] = max
				self[:contrast] = value
				
			when :mute_status
				self[:audio_mute] = value == 1				
				
			when :power_on_delay
				self[:warming_remaining] = value
				if value > 0
					self[:warming] = true
					sleep(2)
					power_on_delay
				else
					self[:warming] = false
				end
			when :auto_setup
				# auto_setup
				# nothing needed to do here
			else
				logger.info "-- NEC LCD, unknown response: #{data[10..13]}"
				logger.info "-- NEC LCD, for command: #{array_to_str(last_command)}"
				logger.info "-- NEC LCD, full response was: #{data}"
		end
	end
	

	#
	# Types of messages sent to and from the LCD
	#
	MSG_TYPE = {
		:command => 'A',
		'B' => :command_reply,
		:get_parameter => 'C',
		'D' => :get_parameter_reply,
		:set_parameter => 'E',
		'F' => :set_parameter_reply
	}
	

	OPERATION_CODE = {
		:video_input => '0060', '0060' => :video_input,
		:audio_input => '022E', '022E' => :audio_input,
		:volume_status => '0062', '0062' => :volume_status,
		:mute_status => '008D', '008D' => :mute_status,
		:power_on_delay => '02D8', '02D8' => :power_on_delay,
		:contrast_status => '0012', '0012' => :contrast_status,
		:brightness_status => '0010', '0010' => :brightness_status,
		:auto_setup => '001E', '001E' => :auto_setup
	}
	#
	# Automatically creates a callable function for each command
	#	http://blog.jayfields.com/2007/10/ruby-defining-class-methods.html
	#	http://blog.jayfields.com/2008/02/ruby-dynamically-define-method.html
	#
	OPERATION_CODE.each_key do |command|
		define_method command do |*args|
			if args[0].nil? 
				type = :get_parameter
			else
				type = args[0]
			end
			message = OPERATION_CODE[command]
			send_checksum(type, message, {:priority => 99})	# Status polling is a low priority
		end
	end


	def check_checksum(data)
		check = 0
		data[1..-3].each do |byte|	# Loop through the second to the third last element
			check = check ^ byte
		end
		return check == data[-2]	# Check the check sum equals the second last element
	end
	

	#
	# Builds the command and creates the checksum
	#
	def send_checksum(type, command, options = {})
		#
		# build header + command and convert to a byte array
		#
		command = "".concat(0x02) + command
		command = "0*0#{MSG_TYPE[type]}#{command.length.to_s(16).upcase.rjust(2, '0')}#{command}"
		command = str_to_array(command)
		
		#
		# build checksum
		#
		check = 0
		command.each do |byte|
			check = check ^ byte
		end
		
		command << check		# Add checksum
		command << 0x0D		# delimiter required by NEC displays
		command.insert(0, 0x01)	# insert SOH byte (not part of the checksum)

		send(command, options)
	end
end
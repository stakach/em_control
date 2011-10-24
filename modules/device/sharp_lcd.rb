# :title:All NEC Control Module
#
# Controls all LCD displays as of 1/07/2011
# Status information avaliable:
# -----------------------------
#
# (built in)
# connected
#
# (module defined)
# power
# warming
#
# volume
# volume_min == 0
# volume_max
#
# brightness
# brightness_min == 0
# brightness_max
#
# contrast
# contrast_min = 0
# contrast_max
# 
# audio_mute
# 
# input (video input)
# audio (audio input)
#
#
class NecLcd < Control::Device

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
		self[:volume_max] = 31
		self[:brightness_min] = 0
		self[:brightness_max] = 31
		self[:contrast_min] = 0
		self[:contrast_max] = 60	# multiply by two when VGA selected
		#self[:error] = []		TODO!!
	end
	
	def connected
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
	
	def response_delimiter
		[0x0D, 0x0A]	# Used to interpret the end of a message
	end
	

	#
	# Power commands
	#
	def power(state)
		if [On, "on", :on].include?(state)
			#self[:power_target] = On
			if !self[:power]
				do_send('POWR   1')
				self[:warming] = true
				self[:power] = On
				logger.debug "-- Sharp LCD, requested to power on"
			end
		else
			#self[:power_target] = Off
			if self[:power]
				do_send('POWR   0')
				
				self[:power] = Off
				logger.debug "-- Sharp LCD, requested to power off"
			end
		end
		
		mute_status(0)
		volume_status(0)
	end
	
	def power_on?
		do_send('POWR????', {:emit => :power})
	end
	
	
	#
	# Resets the brightness and contrast settings
	#
	def reset
		do_send('ARST   2')
	end
	

	#
	# Input selection
	#
	INPUTS = {
		:dvi => 'INPS   1',
		:hdmi => 'INPS   9',
		:vga => 'INPS   2',
		:component => 'INPS   3'
	}
	def switch_to(input)
		input = input.to_sym if input.class == String
		
		self[:target_input] = input
		do_send(INPUTS[input])
		brightness_status(10)		# higher status than polling commands - lower than input switching
		contrast_status(10)

		logger.debug "-- Sharp LCD, requested to switch to: #{input}"
	end
	
	AUDIO = {
		:audio1 => 'ASDP   2',
		:audio2 => 'ASDP   3',
		:dvi => 'ASDP   1',
		:hdmi => 'ASHP   0',
		:vga => 'ASAP   1',
		:component => 'ASCA   1'
	}
	def switch_audio(input)
		input = input.to_sym if input.class == String
		self[:target_audio] = input
		
		do_send(AUDIO[input])
		mute_status(10)		# higher status than polling commands - lower than input switching
		volume_status(10)
		
		logger.debug "-- Sharp LCD, requested to switch audio to: #{input}"
	end
	
	
	#
	# Auto adjust
	#
	def auto_adjust
		do_send('AADJ   1')
	end
	

	#
	# Value based set parameter
	#
	def brightness(val)
		val = 31 if val > 31
		val = 0 if val < 0
		
		message = "VLMP"
		message += val.to_s.rjust(4, ' ')
		
		do_send(message)
	end
	
	def contrast(val)
		val = 60 if val > 60
		val = 0 if val < 0
		
		if self[:input] == :vga
			val = val * 2			# See sharp Manual
		end
		
		message = "CONT"
		message += val.to_s.rjust(4, ' ')
		
		do_send(message)
	end
	
	def volume(val)
		val = 31 if val > 31
		val = 0 if val < 0
		
		message = "VOLM"
		message += val.to_s.rjust(4, ' ')
		
		do_send(message)
		
		self[:audio_mute] = false	# audio is unmuted when the volume is set (TODO:: check this)
	end
	
	def mute
		do_send('MUTE   1')
		
		logger.debug "-- Sharp LCD, requested to mute audio"
	end
	
	def unmute
		do_send('MUTE   0')
		
		logger.debug "-- Sharp LCD, requested to unmute audio"
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
						power_on_delay(0)	# wait until the screen has turned on before sending commands (0 == high priority)
					else
						logger.info "-- NEC LCD, command failed: #{array_to_str(last_command)}"
						logger.info "-- NEC LCD, response was: #{data}"
						return false	# command failed
					end
				elsif data[10..13] == "00D6"	# Power status response
					if data[10..11] == "00"
						self[:power] = data[23] == '1'		# On == 1, Off == 4
						#if self[:power_target].nil?
						#	self[:power_target] = self[:power]
						#elsif self[:power_target] != self[:power]
						#	power(self[:power_target])
						#end
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
					send(last_command)	# checksum already added
					logger.debug "-- NEC LCD, response was a wait command"
				else
					logger.info "-- NEC LCD, get or set failed: #{array_to_str(last_command)}"
					logger.info "-- NEC LCD, response was: #{data}"
					return false
				end
		end
		
		return true # Command success
	end
	

	def do_poll
		power_on?	# The only high priority status query
		power_on_delay
		video_input
		audio_input
		mute_status
		volume_status
		brightness_status
		contrast_status
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
				if not self[:audio_mute]
					self[:volume] = value
				end
				
			when :brightness_status
				self[:brightness_max] = max
				self[:brightness] = value
				
			when :contrast_status
				self[:contrast_max] = max
				self[:contrast] = value
				
			when :mute_status
				self[:audio_mute] = value == 1
				if(value == 1)
					self[:volume] = 0
				else
					volume_status(0)	# high priority
				end
				
			when :power_on_delay
				if value > 0
					self[:warming] = true
					sleep(value)		# Prevent any commands being sent until the power on delay is complete
					power_on_delay
				else
					one_shot(7) do		# Reactive the interface once the display is online
						self[:warming] = false	# allow access to the display
					end
				end
			when :auto_setup
				# auto_setup
				# nothing needed to do here
				sleep(3)		
			else
				logger.info "-- NEC LCD, unknown response: #{data[10..13]}"
				logger.info "-- NEC LCD, for command: #{array_to_str(last_command)}"
				logger.info "-- NEC LCD, full response was: #{data}"
		end
	end
	

	OPERATION_CODE = {
		:video_input => 'INPS????',
		:audio_input => '',
		:volume_status => 'VOLM????',
		:mute_status => 'MUTE????',
		:power_on_delay => '',
		:contrast_status => 'CONT????',
		:brightness_status => 'VLMP????',
		:auto_setup => ''
	}
	#
	# Automatically creates a callable function for each command
	#	http://blog.jayfields.com/2007/10/ruby-defining-class-methods.html
	#	http://blog.jayfields.com/2008/02/ruby-dynamically-define-method.html
	#
	OPERATION_CODE.each_key do |command|
		define_method command do |*args|
			priority = 99
			if args.length > 0
				priority = args[0]
			end
			do_send(OPERATION_CODE[command], {:priority => priority})	# Status polling is a low priority
		end
	end
	

	#
	# Builds the command and creates the checksum
	#
	def do_send(command, options = {})
		command << 0x0D << 0x0A
		
		send(command, options)
	end
end
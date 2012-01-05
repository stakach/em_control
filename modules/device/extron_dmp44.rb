# :title:Extron DSP 44
#
# Status information avaliable:
# -----------------------------
#
# (built in)
# connected
#
# (module defined)
#
#
#
#

class ExtronDmp44 < Control::Device

	def on_load
		#
		# Setup constants
		#
		self[:output_volume_max] = 2168
		self[:output_volume_min] = 1048
		self[:mic_gain_max] = 2298
		self[:mic_gain_min] = 1698
		
		base.default_send_options = {
			:retry_on_disconnect => false		# Don't retry last command sent
		}
		base.config = {
			:clear_queue_on_disconnect => true	# Clear the queue as we may need to send login
		}
	end

	def connected
		device_ready
		@polling_timer = periodic_timer(120) do
			logger.debug "-- Extron Maintaining Connection"
			send('Q', :priority => 99)	# Low priority poll to maintain connection
		end
	end
	
	def disconnected
		#
		# Disconnected may be called without calling connected
		#	Hence the check if timer is nil here
		#
		@polling_timer.cancel unless @polling_timer.nil?
	end
	
	
	def call_preset(number)
		if number < 0 || number > 32
			number = 0	# Current configuration
		end
		send("#{number}.")	# No Carriage return for presents
		# Response: Rpr#{number}
	end
	
	#
	# Input control
	#
	def adjust_gain(input, value)	# \e == 0x1B == ESC key
		input -= 1
		do_send("\eG3000#{input}*#{value}AU")
		# Response: DsG3000#{input}*#{value}
	end

	def adjust_gain_relative(input, value)	# \e == 0x1B == ESC key
		input -= 1
		current = do_send("\eG3000#{input}AU", :emit => "mic#{input + 1}_gain")
		do_send("\eG3000#{input}*#{current + (value * 10)}AU")
		
		# Response: DsG3000#{input}*#{value}
	end
	
	def mute_input(input)
		input -= 1
		do_send("\eM3000#{input}*1AU")
		# Response: DsM3000#{input}*1
	end
	
	def unmute_input(input)
		input -= 1
		do_send("\eM3000#{input}*0AU")
		# Response: DsM3000#{input}*0
	end
	
	
	#
	# Group control
	#
	def mute_group(group)
		do_send("\eD#{group}*1GRPM")
		# Response:  GrpmD#{group}*+00001
	end
	
	def unmute_group(group)
		do_send("\eD#{group}*0GRPM")
		# Response:  GrpmD#{group}*+00000
	end
	
	def volume(group, value)	# \e == 0x1B == ESC key
		do_send("\eD#{group}*#{value * 10}*GRPM")
		# Response: GrpmD#{group}*#{value}*GRPM
	end

	def volume_relative(group, value)	# \e == 0x1B == ESC key

		if value < 0
			value = -value
			do_send("\eD#{group}*#{value * 10}-GRPM")
		else
			do_send("\eD#{group}*#{value * 10}+GRPM")
		end
		# Response: GrpmD#{group}*#{value}*GRPM
	end
	
	
	def response_delimiter
		[0x0D, 0x0A]	# Used to interpret the end of a message
	end
	
	#
	# Sends copyright information
	# Then sends password prompt
	#
	def received(data, command)
		logger.debug "Extron DSP 44 sent #{data}"
		
		if command.nil? && data =~ /Copyright/i
			device_ready
		else
			case data[0..2].to_sym
			when :Grp	# Mute or Volume
				data = data.split('*')
				if data[1][0] == '+'	# mute
					self["ouput#{data[0][5..-1].to_i}_mute"] = data[1][-1] == '1'	# 1 == true
				else
					self["ouput#{data[0][5..-1].to_i}_volume"] = data[1].to_i
				end
			when :DsG	# Input gain
				self["input#{data[7].to_i + 1}_gain"] = data[9..-1].to_i
			when :DsM	# Input Mute
				self["input#{data[7].to_i + 1}_mute"] = data[-1] == '1'	# 1 == true
			when :Rpr	# Preset called
				logger.debug "Extron DSP called preset #{data[3..-1]}"
			else
				if data == 'E22'	# Busy! We should retry this one
					sleep(1)
					return :failed
				elsif data[0] == 'E'
					logger.info "Extron Error #{ERRORS[data[1..2].to_i]}"
					logger.info "- for command #{command[:data]}" unless command.nil?
				end
			end
		end
		
		return :success
	end
	
	
	private
	
	
	ERRORS = {
		10 => 'Invalid command',
		11 => 'Invalid preset',
		12 => 'Invalid port number',
		13 => 'Invalid parameter (number is out of range)',
		14 => 'Not valid for this configuration',
		17 => 'System timed out',
		23 => 'Checksum error (for file uploads)',
		24 => 'Privilege violation',
		25 => 'Device is not present',
		26 => 'Maximum connections exceeded',
		27 => 'Invalid event number',
		28 => 'Bad filename or file not found'
	}
	
	
	def device_ready
		do_send("\e3CV")	# Verbose mode and tagged responses
	end


	

	def do_send(data, options = {})
		send(data << 0x0D, options)
	end
end
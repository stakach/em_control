# :title:Extron SW
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

class ExtronSw < Control::Device

	def on_load
		base.default_send_options = {
			:retry_on_disconnect => false		# Don't retry last command sent
		}
		base.config = {
			:clear_queue_on_disconnect => true	# Clear the queue as we may need to send login
		}
	end

	def connected
		@polling_timer = schedule.every('2m') do
			logger.debug "-- Extron Maintaining Connection"
			send('Q', :priority => 99)	# Low priority poll to maintain connection
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
	
	#
	# Output control
	#
	def switch_to(input)
		send("#{input}!")
	end

	def mute
		send("1B")
	end

	def unmute
		send("0B")
	end
	
	
	
	def response_delimiter
		[0x0D, 0x0A]	# Used to interpret the end of a message
	end
	
	#
	# Sends copyright information
	# Then sends password prompt
	#
	def received(data, command)
		logger.debug "Extron SW sent #{data}"
		
		if command.present?
			case data[0..1].to_sym
			when :In	# Input selected
				self[:output1] = data[2].to_i
			when :Vm	# Video mute
				self["output1_mute"] = data[-1] == '1'	# 1 == true
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
		1 => ' Invalid input channel number (out of range)',
		6 => 'Invalid input selection during auto-input switching',
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

	

	def do_send(data, options = {})
		send(data << 0x0D, options)
	end
end
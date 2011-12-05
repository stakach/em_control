# :title:JVC Display Control Module
#
# Status information avaliable:
# -----------------------------
#
# (built in)
# connected
#
# (module defined)
# power
# 
# audio_mute
# 
# input (video input)
#
#
class JvcMonitor < Control::Device
	#
	# Called on module load complete
	#	Alternatively you can use initialize however will
	#	not have access to settings and this is called
	#	soon afterwards
	#
	def on_load		
		base.default_send_options = {
			:clear_queue_on_disconnect => true,	# Clear the queue as we need to send login
			:retry_on_disconnect => false		# Don't retry last command sent
		}
	end
	
	#def on_update
	#	logger.debug "-- JVC LCD: !!UPDATED!!"
	#end
	
	def connected
		do_send('CN1')	# Connection command - initiate comms
	
		@polling_timer = periodic_timer(60) do
			logger.debug "Polling JVC"
			do_send('CN1')	# Connection command
		end
	end

	def disconnected
		@polling_timer.cancel unless @polling_timer.nil?
		@polling_timer = nil
	end
	
	def response_delimiter
		0x0D
	end
	

	#
	# Power commands
	#
	def power(state)
		if [On, "on", :on].include?(state)
			do_send('PW1', {:command => :power_on, :timeout => 8, :wait => false})
			
			logger.debug "-- JVC LCD, requested to power on"
		else
			do_send('PW0', :command => :power_off)

			logger.debug "-- JVC LCD, requested to power off"
		end
	end
	
	def power_on?
		self[:power]
	end
	

	#
	# Input selection
	#
	INPUTS = {
		:sdi => 'INA',
		:sdi1 => 'INA',
		:sdi2 => 'INB',
		:dvi => 'INC',
		:video => 'INE',
		:video1 => 'INE',
		:video2 => 'INF'
	}
	def switch_to(input)
		input = input.to_sym if input.class == String
		
		do_send(INPUTS[input], {:command => :input, :requested => input, :timeout => 5})

		logger.debug "-- JVC LCD, requested to switch to: #{input}"
	end
	
	def mute
		do_send('AMUTE01', :command => :mute)
		
		logger.debug "-- JVC LCD, requested to mute video"
	end
	
	def unmute
		do_send('AMUTE00', :command => :unmute)
		
		logger.debug "-- JVC LCD, requested to unmute video"
	end
	

	#
	# LCD Response code
	#
	def received(data, command)		# Data is default recieved as a string
		
		logger.debug "-- JVC LCD, recieved: #{data}"
		if command.nil?
			return :success
		end
		
		if data =~ /OK/
			case command[:command]
			when :mute
				self[:mute] = true
			when :unmute
				self[:mute] = false
			when :power_on
				self[:power] = On
			when :power_off
				self[:power] = Off
			when :input
				self[:input] = command[:requested]
			end
			
			return :success
		else
			return :failed
		end
	end


	private
	

	#
	# Builds the command and creates the checksum
	#
	def do_send(command, options = {})
		command = "!00B#{command}\r"
		
		send(command, options)
	end
end
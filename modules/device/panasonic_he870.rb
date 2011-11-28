class PanasonicHe870 < Control::Device

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
	end
	
	def connected

		do_poll
	
		@polling_timer = periodic_timer(30) do
			logger.debug "Polling Camera"
			do_poll
		end
	end

	def disconnected
		#
		# Disconnected may be called without calling connected
		#	Hence the check if timer is nil here
		#
		@polling_timer.cancel unless @polling_timer.nil?
		@polling_timer = nil
	end
	
	def response_delimiter
		/\r|\x03/
	end
	

	#
	# Power commands
	#
	def power(state)
		command = "O"
		
		if [On, "on", :on].include?(state)
			do_send(command, 0x01, :delay => 6)
			logger.debug "Camera, requested to power on"
		else
			do_send(command, 0x00)
			logger.debug "Camera, requested to power off"
		end
	end

	def power?
		do_send('O', '', :emit => :power)
	end
	

	#
	# Preset selection
	#
	def preset(input)
		input = input - 1

		if self[:power] == Off
			power On
		end

		do_send("R", input.to_s.rjust(2, '0'), :delay => 1)		
		logger.debug "Camera, requested to switch to: #{input}"
	end


	def up
		
	end

	def down
		
	end

	def left
		
	end

	def right
		
	end

	def zoom_in
		
	end

	def zoom_out
		
	end

	def focus_up
		
	end

	def focus_down
		
	end
	

	#
	# LCD Response code
	#
	def received(data, command)

		#logger.debug "Camera, sent #{data}"

		case data[0]
			when 'p'
				if data[1] =~ /1|n|2/
					self[:power] = On
				else
					self[:power] = Off
				end
			when 's'
				self[:preset] = data[1..-1].to_i + 1
		end
		
		return :success # Command success
	end
	

	def do_poll
		logger.debug "Camera, polling"
		power_status
	end


	private
	

	OPERATION_CODE = {
		:power_status => 'O'
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
			message = OPERATION_CODE[command]
			do_send(message, '', {:priority => priority})	# Status polling is a low priority
		end
	end
	

	#
	# Builds the command and sends it
	#
	def do_send(command, data, options = {})
		send("##{command}#{data}\r", options)
	end
end
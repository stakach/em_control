# :title:Extron IP Control Processor
#
# Status information avaliable:
# -----------------------------
#
# (built in)
# connected
#
# (module defined)
# IO#{port}_mode
# IO#{port} == status
# relay#{port} == status
# power#{port} == status
# 
#
# (Settings)
# password
#

class ExtronIpcp505 < Control::Device

	def on_load
		#
		# Setup constants
		#
		base.default_send_options = {
			:retry_on_disconnect => false		# Don't retry last command sent
		}
		base.config = {
			:clear_queue_on_disconnect => true	# Clear the queue as we may need to send login
		}
		@poll_lock = Mutex.new
	end

	def connected
	end
	
	def disconnected
		#
		# Disconnected may be called without calling connected
		#	Hence the check if timer is nil here
		#
		@poll_lock.synchronize {
			@polling_timer.cancel unless @polling_timer.nil?
		}
	end
	
	
	
	
	#
	# IR Ports 0 -> 7
	# Mode 0 == play once, 1 == play continuously, 2 == stop
	#
	def send_ir(port, file, function, mode = 0)
		port = 8 + port
		do_send("\e#{port.to_s.rjust(2, '0')},#{file},#{function},#{mode}IR")
		# Response: Irs port,file,function,mode
	end
	
	IR_INFO = {
		:all => 0,
		:manufacturer => 129,
		:model => 130,
		:class => 131,
		:remote => 132,
		:creation_date => 133,
		:comments => 134,
		:file_name => 137
	}
	def ir_info(file, info)
		if info.class == Symbol
			info = IR_INFO[info]
		end
		
		do_send("\e#{file},#{info}IR") #, {:command => :ir_info, :requested => info})
		# Response: descriptive text
	end
	
	
	
	
	
	#
	# IO Ports
	#
	IO_MODE = {
		:digital_in => 0,
		:digital_out => 1,
		:digital_in_5VDC => 2,
		:digital_out_5VDC => 3,
		:analog_in => 4,
		:analog_in_5VDC => 5,
		:digital_in_adjusted => 6,
		:digital_in_adjusted_5VDC => 7
	}
	def set_io_mode(port, mode, upper = nil, lower = nil)
		if mode.class == Symbol
			mode = IO_MODE[info]
		end
		
		if mode >= 6
			send("#{port.to_s.rjust(2, '0')}*#{mode}*#{upper}*#{lower}[")	# No Carriage return for IO commands
		else
			send("#{port.to_s.rjust(2, '0')}*#{mode}[")
		end
		# Response: Cpn_port Iom_mode[,upper,lower]
	end
	
	def get_io_mode(port)
		send("#{port.to_s.rjust(2, '0')}[") #, {:command => :io_mode, :requested => port})
		# Response: mode[,upper,lower]
	end
	
	def pulse_io(port, time = 500)	# Time in ms
		time = (time / 20) & 0xFFFF		# 1 == 20ms, 2 == 40ms where 0xFFFF == maximum
		
		send("#{port.to_s.rjust(2, '0')}*3*#{time}]")
		# Response: Cpn_port Sio_portstatus 0 == off, 1== on, 0-4095 (analog)
	end
	
	def toggle_io(port)
		send("#{port.to_s.rjust(2, '0')}*2]")
		# Response: Cpn_port Sio_portstatus 0 == off, 1== on, 0-4095 (analog)
	end
	
	def set_io(port, state)
		state = state ? 1 : 0
		send("#{port.to_s.rjust(2, '0')}*#{state}]")
		# Response: Cpn_port Sio_portstatus 0 == off, 1== on, 0-4095 (analog)
	end
	
	def get_io_state(port)
		send("#{port.to_s.rjust(2, '0')}]") #, {:command => :io_state, :requested => port})
	end
	
	
	
	
	#
	# Relay Ports
	#
	def pulse_relay(port, time = 500)	# Time in ms
		time = (time / 20) & 0xFFFF		# 1 == 20ms, 2 == 40ms where 0xFFFF == maximum
		
		send("#{port.to_s.rjust(2, '0')}*3*#{time}O")
		# Response: Cpn_port Rly_portstatus 0 == off, 1== on
	end
	
	def set_relay(port, state)
		state = state ? 1 : 0
		send("#{port.to_s.rjust(2, '0')}*#{state}O")
		# Response: Cpn_port Rly_portstatus 0 == off, 1== on
	end
	
	def toggle_relay(port)
		send("#{port.to_s.rjust(2, '0')}*2O")
		# Response: Cpn_port Rly_portstatus 0 == off, 1== on
	end
	
	def get_relay_state(port)
		send("#{port.to_s.rjust(2, '0')}O") #, {:command => :relay_state, :requested => port})
	end
	
	
	
	
	#
	# Switched Power
	# => Port == 1..4
	#
	def set_power(port, state)
		state = state ? 1 : 0
		
		do_send("\eP#{port}*#{state}DCPP")
		# Response: DcppP_port*portstatus 0 == off, 1== on
	end
	
	def get_power_state(port)
		send("\eP#{port}DCPP") #, {:command => :power_state, :requested => port})
	end
	
	
	
	
	#
	# Sends copyright information
	# Then sends password prompt
	#
	def received(data, command)
		logger.debug "Extron IPCP sent #{data}"
		
		if command.nil? && data =~ /Copyright/i
			pass = setting(:password)
			if pass.nil?
				device_ready
			else
				do_send(pass)		# Password set
			end
		elsif data =~ /Login/i
			device_ready
		else
			case data[0..2].to_sym
			when :Irs	# IR Sent
			when :Cpn	# IO or Relay
				port = data[3..-1].to_i
				
				data = data.split(' ')[1]
				case data[0..2]
				when 'Iom'	# IO mode
					data = data[3..-1].split(',')
					self["IO#{port}_mode"] = data[0].to_i
					if data.length > 1
						self["IO#{port}_upper"] = data[1].to_i
						self["IO#{port}_lower"] = data[2].to_i
					end
				when 'Sio'
					self["IO#{port}"] = data[3..-1].to_i
					
				when 'Rly'						# Relay
					self["relay#{port}"] = data[3..-1].to_i == 1
					
				end
			when :Dcp	# Power
				data = data.split('*')
				port = data[0][5..-1].to_i
				self["power#{port}"] = data[1] == '1'
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
		12 => 'Invalid port number',
		13 => 'Invalid value or parameter',
		14 => 'Invalid for this configuration',
		17 => 'System timed out',
		24 => 'Privilege violation',
		25 => 'Device is not present (invalid plane/slot)',
		26 => 'Maximum connections exceeded',
		27 => 'Invalid event number',
		28 => 'Bad filename or file not found',
		31 => 'Attempt to break port pass-through when not set'
	}
	
	
	def device_ready
		do_send("\e3CV")	# Verbose mode and tagged responses
		@poll_lock.synchronize {
			@polling_timer = periodic_timer(120) do
				logger.debug "-- Extron Maintaining Connection"
				send('Q', :priority => 99)	# Low priority poll to maintain connection
			end
		}
	end

	def do_send(data, options = {})
		send(data << 0x0D, options)
	end
end
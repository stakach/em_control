class CustomLifter < Control::Device
	
	def on_load
		#
		# Setup constants
		#
		base.default_send_options = {
			:force_disconnect => true,
			:timeout => 360,
			:max_waits => 6,
			#:retries => 0,
			:delay_on_recieve => 4
		}
		
		base.config = {
			:flush_buffer_on_disconnect => true	# Clear the queue as we may need to send login
		}

		@fail_mutex = Mutex.new
		@fail_count = 0

		self[:position_max] = 13200
		self[:position_min] = 0

		@polling_timer = periodic_timer(90) do
			logger.debug "Polling Lifter"

			#
			# Get position here
			#
		end
	end
	
	
	
	def connected
		
	end

	def disconnected
		
	end

	
	#
	# Preset selection
	#
	def preset(number)
		send("GET /goto_preset?preset=#{number} HTTP/1.1\r\n\r\n", {:command => :preset, :requested => number})
	end
	
	
	def save_preset(number)
		send("GET /save_preset?preset=#{number} HTTP/1.1\r\n\r\n", {:command => :preset, :requested => number})
	end



	def up
		pos = self[:position] + 100
		if pos > self[:position_max]
			pos = self[:position_max]
		end
		goto(pos)
	end

	def down
		pos = self[:position] - 100
		if pos < 0
			pos = 0
		end
		goto(pos)
	end
	
	def goto(position)
		position = self[:position_max] if position > self[:position_max]
		send("GET /goto_pos?pos=#{position} HTTP/1.1\r\n\r\n", {:command => :position, :requested => position})
		#logger.debug "Lifter requested: GET /goto_pos?pos=#{position} HTTP/1.1\r\n"
	end

	def reset
		send("GET /reset HTTP/1.1\r\n\r\n", {:command => :position, :requested => 0})
	end


	def response_delimiter
		"\n"
	end
	
	
	
	def received(data, command)
		logger.debug "Lifter sent: #{data.inspect}"

		if data =~ /ok!|fail!/i

			if command.nil?
				logger.error "Lifter command order mismatch!"
				return :success
			end

			if data =~ /fail!/i
				@fail_mutex.synchronize {
					@fail_count += 1
					if @fail_count <= 3
						send(command[:data], :delay_on_recieve => 10)
					else
						self[:error] = data
					end
				}
			else
				@fail_mutex.synchronize {
					@fail_count = 0
				}
				self[:error] = nil

				if command[:command] == :position
					self[:position] = command[:requested]
				elsif command[:command] == :preset
					self[:preset] = command[:requested]
				end
			end
			return :success
		else
			return :ignore
		end
	end
end


#in motion
#upper lower limit


#
# Will reside in user defined file
#
class NecProj < Control::Device
	def connected
		send('connection made')
		
		@close = 0 if @close.nil?
		if @close < 2
			@close += 1
			EM.schedule proc {
					base.close_connection(true)
			}
			return
		end
		
		var_const_test = On
		
		command1
		command3		
		command1
		command3
		command1
		command3
		command1
		
		command2
		command2

		command1
		command1
		
		#EM.add_timer 5, proc { EM.stop_event_loop }
	end

	def disconnected
		p 'disconnected...'
	end


	def received(data)
		data = Control::Utilities.array_to_str(data)
		
		p data
		
		if data =~ /fail/i
			p "-> #{last_command}"
			if last_command =~ /criticalish/i
				send('recovery ping')	# pri-queue ensures that this is run before the next standard item
				send('criticalish ping')
			end
			return false
		end
		
		return true # Return true if command success, nil if not complete, false if fail
	end
	
	
	def command1
		send('test ping')
	end
	
	
	def command2
		send('critical ping')
	end
	
	def command3
		send('criticalish ping')
	end
end

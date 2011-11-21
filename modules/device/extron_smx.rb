# :title:Extron Digital Matrix Switchers
#
# Status information avaliable:
# -----------------------------
#
# (built in)
# connected
#
# (module defined)
# video1 => input (video)
# video2
# video3
# video1_muted => true
#
# audio1 => input
# audio1_muted => true
# 
#
# (Settings)
# password
#

class ExtronSmx < Control::Device

	def on_load
		#
		# Setup constants
		#
		base.default_send_options = {
			:clear_queue_on_disconnect => true,	# Clear the queue as we need to send login
			:retry_on_disconnect => false,		# Don't retry last command sent
			:wait => false
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
	# No need to wait as commands can be chained
	#
	def switch(map, plane = 0)
		map.each do |input, output|
			send("#{plane}*#{input}*#{output}!")
		end
	end
	
	def switch_video(map, plane = 0)
		map.each do |input, output|
			send("#{plane}*#{input}*#{output}%")
		end
	end
	
	def switch_audio(map, plane = 0)
		map.each do |input, output|
			send("#{plane}*#{input}*#{output}$")
		end
	end
	
	def mute_video(outputs, plane = 0)
		outputs = [outputs] if outputs.class == Fixnum
		outputs.each do |output|
			send("#{plane}*#{output}*1B")
		end
	end
	
	def unmute_video(outputs, plane = 0)
		outputs = [outputs] if outputs.class == Fixnum
		outputs.each do |output|
			send("#{plane}*#{output}*0B")
		end
	end
	
	def mute_audio(outputs, plane = 0)
		outputs = [outputs] if outputs.class == Fixnum
		outputs.each do |output|
			send("#{plane}*#{output}*1Z")
		end
	end
	
	def unmute_audio(outputs, plane = 0)
		outputs = [outputs] if outputs.class == Fixnum
		outputs.each do |output|
			send("#{plane}*#{output}*0Z")
		end
	end
	
	def set_preset(number, plane = nil)
		if plane.nil?
			send("#{number},")
		else
			send("#{plane}*#{number}*0,")
		end
	end
	
	def recall_preset(number, plane = nil)
		if plane.nil?
			send("#{number}.")
		else
			send("#{plane}*#{number}*0.")
		end
	end
	
	
	#
	# Sends copyright information
	# Then sends password prompt
	#
	def received(data, command)
		logger.debug "Extron SMX sent #{data}"
		
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
			plane = data.to_i.to_s
			data = data[plane.length..-1]
			
			case data[0..1].to_sym
			when :Am	# Audio mute
				data = data[3..-1].split('*')
				self["plane#{plane}_audio#{data[0].to_i}_muted"] = data[1] == '1'
			when :Vm	# Video mute
				data = data[3..-1].split('*')
				self["plane#{plane}_video#{data[0].to_i}_muted"] = data[1] == '1'
			when :In	# Input to all outputs
				#
				# We are ignoring these as we are not getting the device information currently
				#
			when :Ou	# Output x to input y
				data = data[3..-1].split(' ')
				output = data[0].to_i
				input = data[1][2..-1].to_i
				if data[2] =~ /(All|RGB|Vid)/
					self["plane#{plane}_video#{output}"] = input
				end
				if data[2] =~ /(All|Aud)/
					self["plane#{plane}_audio#{output}"] = input
				end
			else
				if data == 'E22'	# Busy! We should retry this one
					sleep(1)
					return :failed
				end
			end
		end
		
		return :success
	end
	
	
	private
	
	
	def device_ready
		do_send("\e3CV", :wait => true)	# Verbose mode and tagged responses
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
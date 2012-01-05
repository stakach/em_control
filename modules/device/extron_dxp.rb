# :title:Extron Digital Matrix Switchers
#
# Status information avaliable:
# -----------------------------
#
# (built in)
# connected
#
# (module defined)
# video_inputs
# video_outputs
# audio_inputs
# audio_outputs
#
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

class ExtronDxp < Control::Device

	def on_load
		#
		# Setup constants
		#
		base.default_send_options = {
			:retry_on_disconnect => false,		# Don't retry last command sent
			:wait => false
		}
		base.config = {
			:clear_queue_on_disconnect => true	# Clear the queue as we may need to send login
		}
	end

	def connected
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
	

	def direct(string)
		send(string, :wait => false)
	end
	
	
	#
	# No need to wait as commands can be chained
	#
	def switch(map)
		map.each do |input, outputs|
			input = input.to_s if input.class == Symbol
			input = input.to_i if input.class == String

			outputs = [outputs] unless outputs.class == Array
			outputs.each do |output|
				send("#{input}*#{output}!")
			end
		end
	end
	
	def switch_video(map)
		map.each do |input, outputs|
			input = input.to_s if input.class == Symbol
			input = input.to_i if input.class == String

			outputs = [outputs] unless outputs.class == Array
			outputs.each do |output|
				send("#{input}*#{output}%")
			end
		end
	end
	
	def switch_audio(map)
		map.each do |input, outputs|
			input = input.to_s if input.class == Symbol
			input = input.to_i if input.class == String

			outputs = [outputs] unless outputs.class == Array
			outputs.each do |output|
				send("#{input}*#{output}$")
			end
		end
	end
	
	def mute_video(outputs)
		outputs = [outputs] if outputs.class == Fixnum
		outputs.each do |output|
			send("#{output}*1B")
		end
	end
	
	def unmute_video(outputs)
		outputs = [outputs] if outputs.class == Fixnum
		outputs.each do |output|
			send("#{output}*0B")
		end
	end
	
	def mute_audio(outputs)
		outputs = [outputs] if outputs.class == Fixnum
		outputs.each do |output|
			send("#{output}*1Z")
		end
	end
	
	def unmute_audio(outputs)
		outputs = [outputs] if outputs.class == Fixnum
		outputs.each do |output|
			send("#{output}*0Z")
		end
	end
	
	def set_preset(number)
		send("#{number},")
	end
	
	def recall_preset(number)
		send("#{number}.")
	end


	#def response_delimiter
	#	[0x0D, 0x0A]	# Used to interpret the end of a message
	#end
	
	
	#
	# Sends copyright information
	# Then sends password prompt
	#
	def received(data, command)
		logger.debug "Extron Matrix sent #{data}"
		
		if command.nil? && data =~ /Copyright/i
			pass = setting(:password)
			if pass.nil?
				device_ready
			else
				do_send(pass)		# Password set
			end
		elsif data =~ /Login/i
			device_ready
		elsif command[:command] == :information
			data = data.split(' ')
			video = data[0][1..-1].split('X')
			self[:video_inputs] = video[0].to_i
			self[:video_outputs] = video[1].to_i
			
			audio = data[1][1..-1].split('X')
			self[:audio_inputs] = audio[0].to_i
			self[:audio_outputs] = audio[1].to_i
		else
			case data[0..1].to_sym
			when :Am	# Audio mute
				data = data[3..-1].split('*')
				self["audio#{data[0].to_i}_muted"] = data[1] == '1'
			when :Vm	# Video mute
				data = data[3..-1].split('*')
				self["video#{data[0].to_i}_muted"] = data[1] == '1'
			when :In	# Input to all outputs
				data = data[2..-1].split(' ')
				input = data[0].to_i
				if data[1] =~ /(All|RGB|Vid)/
					for i in 1..video_outputs
						self["video#{i}"] = input
					end
				end
				if data[1] =~ /(All|Aud)/
					for i in 1..audio_outputs
						self["audio#{i}"] = input
					end
				end
			when :Ou	# Output x to input y
				data = data[3..-1].split(' ')
				output = data[0].to_i
				input = data[1][2..-1].to_i
				if data[2] =~ /(All|RGB|Vid)/
					self["video#{output}"] = input
				end
				if data[2] =~ /(All|Aud)/
					self["audio#{output}"] = input
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
		send("I", :wait => true, :command => :information)
		do_send("\e3CV", :wait => true)	# Verbose mode and tagged responses
	end

	def do_send(data, options = {})
		send(data << 0x0D, options)
	end
end
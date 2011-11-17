# :title:Extron Digital Matrix Processor
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
# Volume outputs
# 60000 == volume 1
# 60003 == volume 4
#
# Pre-mix gain inputs
# 40100 == Mic1
# 40105 == Mic6
#

class ExtronDmp64 < Control::Device

	def on_load
		#
		# Setup constants
		#
		self[:output_volume_max] = 2168
		self[:output_volume_min] = 1048
		self[:mic_gain_max] = 2298
		self[:mic_gain_min] = 1698
	end

	def connected
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
	def adjust_gain(mic, value)	# \e == 0x1B == ESC key
		do_send("\eG4010#{mic}*#{value}AU")
		# Response: DsG4010#{mic}*#{value}
	end
	
	def mute_mic(mic)
		do_send("\eM4010#{mic}*1AU")
		# Response: DsM4010#{mic}*1
	end
	
	def unmute_mic(mic)
		do_send("\eM4010#{mic}*0AU")
		# Response: DsM4010#{mic}*0
	end
	
	
	#
	# Output control
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
		do_send("\eD#{group}*#{value}*GRPM")
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
		logger.debug "Extron DSP sent #{data}"
		
		if command.nil? && data =~ /(copyright|password)/i
			do_send(setting(:password))
		else
			case data[0..2].to_sym
			when :Grp	# Mute or Volume
				data = data.split('*')
				if data[1][0] == '+'	# mute
					self["ouput#{data[0][5..-1].to_i}_mute"] = data[1][-1] == '1'	# 1 == true
				else
					self["ouput#{data[0][5..-1].to_i}_volume"] = data[1].to_i
				end
			when :DsG	# Mic gain
				self["mic#{data[7]}_gain"] = data[9..-1].to_i
			when :DsM	# Mic Mute
				self["mic#{data[7]}_mute"] = data[-1] == '1'	# 1 == true
			when :Rpr	# Preset called
				logger.debug "Extron DSP called preset #{data[3..-1]}"
			end
		end
		
		return :success
	end
	
	
	private


	def do_send(data, options = {})
		send(data << 0x0D, options)
	end
end
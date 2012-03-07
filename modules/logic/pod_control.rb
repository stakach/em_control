#
# (Settings)
#	* in-house-pc (input name)
#	* audio1 (in-house-pc audio input name)
#	* laptop1 (input name)
#	* laptop2 (input name)
#	* audio2 (laptop1 and 2 audio input name)
#	* collaboration_page (address of web page to load for collaboration)
# 	* help1, help2, help3
#
# (module defined)
# input
#
class PodControl < Control::Logic


	def on_load
		#
		# Setup constants
		#
		self[:laptop1] = setting(:laptop1)
		self[:laptop2] = setting(:laptop2)
		register(:Display, :input)	# expects display_input_change
		register(:Display, :power)	# expects display_power_change
		
		self[:share_display] = false
		
		update_help
		schedule.every('1h') do
			update_help
		end
		schedule.cron('30 6 * * *') do 	# Every day at 6:30am
			refresh
		end
		schedule.cron('30 7 * * 1-5') do 	# Every day (except weekends) at 7:30am - turn on pods
			system[:Display].power_on? do |power|
				if power == Off
					select('in-house-pc')
				end
			end
		end
		schedule.cron('30 22 * * *') do 	# Every day at 10:30pm - turn off pods
			system[:Display].power(Off)
		end
	end
	
	
	def on_unload
		
	end
	
	
	def on_update
		self[:laptop1] = setting(:laptop1)
		self[:laptop2] = setting(:laptop2)
		self[:share_display] = false
	end


	def select(input)
		#
		# Check the display is on.
		#	If not then power it on.
		#
		system[:Display].power_on? do |power|
			if power == Off
				system[:Display].power(On)
			end
			
			#
			# Switch to the correct video source
			#	Based on the settings (input == 'in-house-pc' or 'laptop1' or 'laptop2')
			#
			system[:Display].switch_to(setting(input))
			self[:input] = input
			
			#
			# Switch to the correct audio source
			#
			if(input == 'in-house-pc')
				system[:Display].switch_audio(:audio1)
			else
				system[:Display].switch_audio(:audio2)
			end
		end
	end
	
	
	#
	# Reload the interface
	#
	def refresh
		self[:display_refresh] = Time.now.to_i
	end
	
	
	def show_desktop
		system[:Computer].launch_application('desktop')
	end
	

	def start_collaborating
		system[:Computer].launch_application(setting(:collaboration_page))
	end
	
	#
	# This is because if the in house pc is off or unplugged
	#	The screen may change the input.
	#
	def display_input_changed(status)
		if system[:Display][:power]
			logger.debug "-- Pod input changed: #{status}"
			case status.to_s
				when setting('in-house-pc')
					self[:input] = 'in-house-pc'
					if self[:set_default_pc]
						self[:set_default_pc] = false
						default_display_config
					end
				when setting('laptop1')
					self[:input] = :laptop1
					if self[:set_default_laptop1]
						self[:set_default_laptop1] = false
						default_display_config
					end
				when setting('laptop2')
					self[:input] = :laptop2
					if self[:set_default_laptop2]
						self[:set_default_laptop2] = false
						default_display_config
					end
				when setting('sharing_input')
					self[:input] = 'sharing_input'
					do_share(true) unless self[:share_display]
				else
					select('in-house-pc')
			end
		end
	end
	
	
	def display_power_changed(on)
		logger.debug "Pod Control: received power change status"
		if !on	# revert to default values when display is next turned on
			self[:set_default_laptop1] = true
			self[:set_default_laptop2] = true
			self[:set_default_pc] = true
		else
			default_display_config
		end
	end
	
	
	def do_share(value)
		self[:sharing_avaliable] = true
		if value == true && self[:share_display] == false
			if self[:input].nil? || self[:input] == 'sharing_input'
				self[:old_input] = 'in-house-pc'
			else
				self[:old_input] = self[:input]
			end
			self[:share_display] = true
			select('sharing_input')
			system[:Display].mute
		elsif value == false && self[:share_display] == true
			system[:Display].unmute
			self[:share_display] = false
			select(self[:old_input] || 'in-house-pc')
		end
	end
	
	def enable_sharing(value)
		if self[:share_display]
			do_share(false)
		end
		self[:sharing_avaliable] = value
	end
	
	
	protected
	
	
	def default_display_config
		logger.debug "Pod Control: setting default display values"
		system[:Display].brightness(system[:Display][:brightness_max] / 2) unless system[:Display][:brightness_max].nil?
		system[:Display].contrast(system[:Display][:contrast_max] / 2) unless system[:Display][:contrast_max].nil?
	end
	
	
	def update_help
		self[:help1] = setting('help1')
		self[:help2] = setting('help2')
		self[:help3] = setting('help3')
		self[:name] = system.controller.name
		self[:laptop1_text] = setting(:laptop1_text)
	end


end

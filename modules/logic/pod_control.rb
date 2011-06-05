class PodControl < Control::Logic


	def select(input)
		if !system[:Display].power_on?
			system[:Display].power(On)
		end
		system[:Display].switch_to(input.downcase)
		system[:Display].do_poll
	end


end

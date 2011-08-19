require 'digest/sha1'	# For one time key

class TrustedDevice < ActiveRecord::Base
	
	#
	# Generates a one-time key that will allow this device to login without interaction
	#
	def generate_key
		one_time_key = Digest::SHA1.hexdigest "#{Time.now.to_f.to_s}#{id}"
	end
	
end

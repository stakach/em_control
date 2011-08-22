require 'digest/sha1'	# For one time key

#
# This is a list of devices that are trusted
# => A one time key is used to authenticate and re-generated for the next logon
#
class TrustedDevice < ActiveRecord::Base
	belongs_to	:user
	belongs_to	:controller
	
	#
	# Generates a one-time key that will allow this device to login without interaction
	#
	def generate_key
		last_authenticated = Time.now
		one_time_key = Digest::SHA1.hexdigest "#{last_authenticated.to_f.to_s}#{id}"
		save
	end
	
	
	#
	# Attempts to login using a one time key and generates a new one if it is accepted
	#
	def self.try_to_login(key)
		info = {}
		entry = TrustedDevice.where("one_time_key = ?", key).first
		if entry.nil?
			return nil
		else
			if !entry.expires.nil? && (entry.expires <=> Time.now) > 0	# We are past the expired time
				entry.destroy
				return nil
			end
			info[:login] = entry.user_id
			info[:mail] = entry.trusted_by
			entry.generate_key				# Key accepted, generate a new one
			return info
		end
	end
	
	
	protected
	
	
	validates_presence_of :user, :trusted_by, :controller, :description
end

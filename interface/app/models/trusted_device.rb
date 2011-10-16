require 'digest/sha1'	# For one time key

#
# This is a list of devices that are trusted
#	A one time key is used to authenticate and re-generated for the next logon
#
class TrustedDevice < ActiveRecord::Base
	belongs_to	:user
	belongs_to	:control_system
	
	
	before_create :generate_keys
	
	
	#
	# Generates a one-time key that will allow this device to login without interaction
	#
	def generate_key
		self[:last_authenticated] = Time.now
		self[:next_key] = Digest::SHA1.hexdigest "#{Time.now.to_f.to_s}#{id}"
		save!
	end
	
	def accept_key
		self[:one_time_key] = self[:next_key]
		save!
	end
	
	#
	# Attempts to login using a one time key and generates a new one if it is accepted
	#
	def self.try_to_login(key, gen = false)
		entry = TrustedDevice.where("one_time_key = ? or next_key = ?", key, key).first
		if entry.nil?
			return nil
		else
			if !entry.expires.nil? && (entry.expires <=> Time.now) > 0	# We are past the expired time
				entry.destroy
				return nil
			end
			if entry.one_time_key != entry.next_key && entry.next_key == key	# so the accept failed?
				entry.one_time_key = entry.next_key # Perform an implicit accept
				entry.save							# Prevents the same key being used again
			end
			
			entry.generate_key if gen		# Key accepted, generate a new one
			return entry
		end
	end
	
	
	protected
	
	
	def generate_keys
		self[:last_authenticated] = Time.now
		self[:one_time_key] = Digest::SHA1.hexdigest "#{Time.now.to_f.to_s}#not so strong"
		self[:next_key] = Digest::SHA1.hexdigest "#{self[:last_authenticated].to_f.to_s}different"
	end
	
	
	validates_presence_of :user, :control_system, :reason
end

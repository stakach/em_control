class User < ActiveRecord::Base
	
	belongs_to	:auth_source
	has_many	:trusted_devices,	:dependent => :destroy
	has_many	:user_zones,		:dependent => :destroy
	has_many	:zones,				:through => :user_zones
	
	
	SECURITY = {
		:active => 0b1	# User enabled (view system + modules. Not settings)
		
		:instance_settings =>		0b10,			# User defined settings can be viewed and modified
		:instance_configuration =>	0b100,			# IP, UDP, TLS and Port can be modified and instances can be started, stopped, added and removed
		
		:module_settings =>			0b1000,			# Default user defined settings can be modified
		:module_configuration =>	0b10000,		# Adding, removing (All instances must be removed first) modules
		:module_upgrading =>		0b100000,		# Loading the new module as the default (if updated by someone else)
		
		:instance_debugging =>		0b1000000		# Is debugging alowed to be activated by this user (negative effects on a production system)
	}
	
	#
	# Bit mask accessors:
	#
	# Automatically creates a callable function for each command
	#	http://blog.jayfields.com/2007/10/ruby-defining-class-methods.html
	#	http://blog.jayfields.com/2008/02/ruby-dynamically-define-method.html
	#
	SECURITY.each_key do |setting|
		setting_getter = "#{setting}?".to_sym
		setting_setter = "#{setting}=".to_sym
		
		define_method setting_getter do
			self.privilege_map & SECURITY[setting] > 0
		end
		
		define_method setting_setter do |value|
			if [true, 1, '1', 'true'].include?(value)
				self.privilege_map |= SECURITY[setting]
			else
				self.privilege_map &= ~SECURITY[setting]
			end
		end
	end
	
	
	def self.try_to_login(login, password)
		# Make sure no one can sign in with an empty password
		return nil if password.to_s.empty?
		user = User.where("LOWER(identifier) LIKE ?", '%' + login.downcase + '%').first
		attrs = nil
		if user
			# user is already in local database
			return nil if !user.active?
			attrs = user.auth_source.authenticate(login, password)
			return nil unless attrs
			user.touch
			attrs.merge!(:login => user.id)
		else
			# user is generic, try to authenticate with available sources
			attrs = AuthSource.authenticate(login, password)
			return nil unless attrs
			
			query = ""
			members = []
			attrs[:member_of].each do |member|
				if !member.strip.empty?		# ensure there is a membership - empty strings are bad
					if query.empty?
						query += "identifier = ? OR identifier LIKE ?"
					else
						query += " OR identifier = ? OR identifier LIKE ?"
					end
					members << member << (member + ',%')	# the comma here avoids security risks
				end
			end
			user = User.where(query, *members).first unless query.empty?
			
			if user && user.active?
				attrs.merge!(:login => user.id)
			else
				return nil
			end
		end
		
		return attrs
	rescue => text
		return nil
	end
	
	
	protected
	
	
	validates_presence_of :identifier, :auth_source
end

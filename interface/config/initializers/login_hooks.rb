

#
# Mixes into the user model
#
Login.user_mixin do
	has_many	:trusted_devices,	:dependent => :destroy
	has_many	:zones,				:through => :groups
	has_many	:control_systems, 	:through => :zones
	
	
	SECURITY = {
		:active => 0b1,	# User enabled (view system + modules. Not settings)
		
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
end


Login.group_mixin do
	has_many	:user_zones,		:dependent => :destroy
	has_many	:zones,				:through => :user_zones
end


#
# For performing a redirect where login is successful.
#
Login.redirection do
	redirect_to '/interfaces/dashboard'
end


Login.title = "Cloud Control"

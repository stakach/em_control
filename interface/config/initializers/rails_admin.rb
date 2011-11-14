RailsAdmin.config do |config|

  config.current_user_method { current_rake db:migrate } #auto-generated
	
	
	config.included_models = ['User', 'Group', 'AuthSource', 'Zone', 'TrustedDevice', 'Dependency', 'Setting', 'ControlSystem', 'ControllerLogic', 'ControllerDevice', 'Server']
	config.label_methods << :identifier << :hostname
	
	
	config.authenticate_with do
		raise 'SecurityTransgression' unless User.find(session[:user]).system_admin
	end
	config.current_user_method do
		User.find(session[:user])
	end
	config.authorize_with do
		raise 'SecurityTransgression' unless User.find(session[:user]).system_admin
	end
	
	config.model User do
		weight -1
		
		object_label_method do
			:user_label_method
		end
		
		
		list do
			field :auth_source
			field :identifier do
				label 'Username'
			end
			field :firstname
			field :lastname
			field :email
			field :login_count
			field :updated_at do
				label 'Last login'
			end
		end
		
		edit do
			
			group :authentication do
				field :auth_source do
					label 'Authentication Source'
					help 'For LDAP sources users can be automatically managed using groups'
				end
				
				field :identifier do
					label 'Username'
				end
				field :password do
					help 'Required to create a user. If not using local authenication, set a dummy password.'
				end
				field :password_confirmation do
					help 'Required if password is set'
				end
			end
			
			group :user_details do
				field :firstname
				field :lastname
				field :email
				
				field :description
				field :notes
			end
			
			group :user_permissions do
				field :system_admin
				field :groups
			end
		end
	end
	
	
	def user_label_method
		"#{self.firstname} #{self.lastname}"
	end
	
	
	config.model Group do
		weight 0
		
		list do
			field :identifier do
					label 'Group'
			end
			field :description
			field :notes
			field :auth_source do
				label 'Group Authority'
			end
			field :auth_only do
				label 'Authentication Only'
			end
		end
		
		edit do
		
			group :group_details do
				field :identifier do
					label 'Group Name'
				end
				
				field :description
				field :notes
				
				field :auth_source do
					label 'Related Auth Source'
					help 'For linking to existing LDAP groups'
				end
				
				field :auth_only do
					label 'Authentication Only'
					help 'For a linked LDAP group/user that does not define relevant structure'
				end
			end
			
			group :group_members do
				field :users
				field :zones
			end
		
		end
	end
	
	config.model AuthSource do
		weight 1
		
		label 'Authentication Source'
		object_label_method do
			:auth_label_method
		end	
		
		list do
			sort_by :ordinal
			
			field :type
			field :name
			field :host
			field :port
			field :base_dn do
				label 'Base DN'
			end
			field :tls do
				label 'Secured?'
			end
		end
		
		
		edit do
			
			group :authentication_source_details do
				field :auth_type, :enum do
					enum do
						['AuthSourceLocal', 'AuthSourceLdap']
					end
					help 'Required.'
				end
				
				field :name do
					help 'Required. Note: Users may have to type this in to log in.'
				end
				
				field :ordinal do
					help 'Optional. The lowest ordinal defines the default authentication source.'
				end
			end
			
			group :ldap_connection do
				field :host
				field :port
				field :account do
					help 'The role based account for querying the LDAP server.'
				end
				field :encrypted_password do
					label 'Password'
					help 'The password for the role based account.'
				end
				field :account do
					help 'The role based account for querying the LDAP server.'
				end
				field :base_dn do
					label 'Base DN'
					help 'Object that stores the users. CN=Users,DC=organisation,DC=com,DC=au'
				end
				field :tls do
					label 'Transport Security?'
					help 'Does the server require an encrypted connection'
				end
			end
			
			group :ldap_details do
				field :attr_login do
					label 'Login Attribute'
					help 'Commonly: sAMAccountName'
				end
				field :attr_firstname do
					label 'Firstname Attribute'
					help 'Commonly: givenName'
				end
				field :attr_lastname do
					label 'Lastname Attribute'
					help 'Commonly: sN'
				end
				field :attr_mail do
					label 'Email Attribute'
					help 'Commonly: mail'
				end
				field :attr_member do
					label 'Group Membership Attribute'
					help 'Commonly: memberOf'
				end
				
				field :groups
			end
			
			field :users
		end
	end
	
	def auth_label_method
		"#{self.name} authentication"
	end
	
	
	#
	# Control Specific
	#
	config.model Dependency do
		weight 10
		
		object_label_method do
			:dep_label_method
		end	
		
		list do
			field :id
			field :actual_name
			field :module_name
			field :classname
			field :filename
			field :description
		end
		
		edit do
			field :id
			field :actual_name
			field :module_name
			field :classname
			field :filename
			field :description
			field :default_port
		end
	end
	
	def dep_label_method
		"#{self.actual_name}"
	end
	
	
	config.model Zone do
		weight 11
		
		field :name
		field :description
		
		field :groups
		field :control_systems
	end	
	
	
	config.model ControlSystem do
		weight 12
		
		list do
			field :id
			field :name
			field :active
			field :description
			
			field :zones
		end
		
		edit do
			field :name
			field :description
			field :active
			
			field :zones
		end
	end
	
	
	config.model ControllerDevice do
		weight 13
		
		object_label_method do
			:dev_label_method
		end	
		
		list do
			field :control_system
			field :dependency
			field :custom_name
			field :ip
			field :port
			field :tls
			field :udp
		end
		
		group :device_configuration do
			field :dependency
			field :ip
			field :port
			field :tls
			field :udp
		end
		
		group :device_location do
			field :control_system
			field :custom_name
			field :priority
		end
	end
	
	def dev_label_method
		"#{self.dependency.actual_name} instance"
	end
	
	
	config.model ControllerLogic do
		weight 14
		
		object_label_method do
			:dev_label_method
		end	
		
		field :control_system
		field :dependency
		field :custom_name
		field :priority
	end
	
	config.model Setting do
		weight 15
		
		field :object
		
		field :name
		field :description
		field :encrypt_setting do
			help 'Only valid for text values.'
		end
		
		field :value_type, :enum do
			enum do
				[['Text Value', 0], ['Integer Value', 1], ['Float Value', 2], ['DateTime Value', 3]]
			end
			help 'Required.'
		end
		field :text_value
		field :integer_value
		field :float_value
		field :datetime_value
	end
	
	
	config.model TrustedDevice do
		weight 16
		
		object_label_method do
			:trust_label_method
		end	
		
		list do
			field :reason
			field :user
			field :control_system
			field :last_authenticated
			field :created_at
			field :expires
			field :notes
		end
		
		edit do
			field :reason
			field :expires
			field :notes
		end
	end
	
	def trust_label_method
		"Trusting #{self.reason}"
	end
	
	
	config.model Server do
		weight 20
		
		field :hostname
		field :online
		field :notes
	end
end
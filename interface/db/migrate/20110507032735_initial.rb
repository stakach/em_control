class Initial < ActiveRecord::Migration
	def self.up
		
		#
		# These represent individual systems
		#
		create_table :controllers do |t|
			t.string	:name,		:allow_null => false
			t.text		:description
			t.boolean	:active,	:default => true,	:allow_null => false
			
			t.timestamps
		end
		
		#
		# Describe modules that can be loaded and exist on the system
		#
		create_table :dependencies do |t|
			t.references	:dependency
			
			t.string		:classname,		:allow_null => false
			t.string		:filename,		:allow_null => false
			
			t.string		:module_name	# Type name (Projector)
			t.string		:actual_name	# Real name (All NEC Projectors)
			t.text			:description
			
			t.datetime		:version_loaded
			
			t.timestamps
		end
		
		#
		# Device and Logic instances
		# => Priority provides load order (high priorities load first)
		#
		create_table :controller_devices do |t|
			t.references	:controller,	:allow_null => false
			t.references	:dependency,	:allow_null => false

			t.string	:ip,	:allow_null => false
			t.integer	:port,:allow_null => false
			
			t.boolean	:tls,	:default => false,	:allow_null => false
			t.boolean	:udp,	:default => false,	:allow_null => false
			
			t.integer	:priority,	:default => 0
			
			t.timestamps
		end
		
		create_table :controller_logics do |t|
			t.references	:controller,	:allow_null => false
			t.references	:dependency,	:allow_null => false
			
			t.integer		:priority,	:default => 0
			
			t.timestamps
		end
		
		#
		# Settings relating to Dependencies, Devices instances, Interfaces and Interface Instances
		#
		create_table :settings do |t|
			t.references :object, :polymorphic => true		

			t.string	:name,			:allow_null => false
			t.text		:description
			
			t.integer	:value_type,	:allow_null => false
			
			t.float		:float_value
			t.integer	:integer_value	# doubles as boolean (type -1)
			t.text		:text_value
			t.datetime	:datetime_value
			
			t.timestamps
		end
		
		#
		# Describes the interfaces avaliable
		#
		create_table :guis do |t|
			t.string	:name,	:allow_null => false
			t.text		:description
			t.integer	:security_level
			
			t.datetime	:version	# Cache update indicator
			
			# Location information here for
			# access if the device is local
			# May also require a password if security level is set
			
			t.timestamps
		end
		
		#
		# Authentication sources and users
		# 
		create_table :auth_sources do |t|
			t.string	:type,	:allow_null => false
			t.string	:name,	:allow_null => false
			t.string	:host
			t.integer	:port
			t.string	:account
			t.string	:account_password
			t.string	:base_dn
			t.string	:attr_login
			t.string	:attr_firstname
			t.string	:attr_lastname
			t.string	:attr_mail
			t.string	:attr_member
			t.boolean	:tls
		end
	
		create_table :users do |t|
			t.references :auth_source,	:allow_null => false
			
			t.string	:identifier,	:allow_null => false
			t.text		:description
			
			t.integer	:security_level,:default => 0
			
			t.timestamps
		end
		
		#
		# Trusted devices
		# => System 0 cannot trust any interface as does not have an explicit controller id
		#
		create_table :trusted_devices do |t|
			t.references	:user,			:allow_null => false
			t.references	:controller,	:allow_null => false
			
			t.string	:description,		:allow_null => false
			t.text		:notes
			
			t.string	:one_time_key
			t.datetime	:expires			# not currently used
			t.datetime	:last_authenticated	# Cache update indicator
			
			t.timestamps
		end
	end

	def self.down
	end
end

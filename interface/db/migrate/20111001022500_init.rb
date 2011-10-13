class Init < ActiveRecord::Migration
	def change
		#
		# These represent individual systems
		#
		create_table :control_systems do |t|
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
			t.references	:control_system,:allow_null => false
			t.references	:dependency,	:allow_null => false

			t.string	:ip,	:allow_null => false
			t.integer	:port,:allow_null => false
			
			t.boolean	:tls,	:default => false,	:allow_null => false
			t.boolean	:udp,	:default => false,	:allow_null => false
			
			t.integer	:priority,	:default => 0
			
			t.string	:custom_name	# projector_left
			
			t.timestamps
		end
		
		create_table :controller_logics do |t|
			t.references	:control_system,:allow_null => false
			t.references	:dependency,	:allow_null => false
			
			t.integer		:priority,	:default => 0
			
			t.string		:custom_name
			
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
		#create_table :guis do |t|
		#	t.string	:name,	:allow_null => false
		#	t.text		:description
			
		#	t.datetime	:version		# Cache update indicator
		#	t.text		:render_path	# Path of file to render
			
			# Location information here for
			# access if the device is local
			
		#	t.timestamps
		#end
		
		#
		# Zones can be used to classify the various control systems
		# => General Type (meeting room, seminar room)
		# => Floor, Building, Campus
		# This allows fine grained access control for users
		#
		create_table :zones do |t|
			t.string	:name,	:allow_null => false
			t.text		:description
			
			t.timestamps
		end
		
		create_table :user_zones do |t|
			t.references :group
			t.references :zone
			
			t.integer	:privilege_map	# if not null overrides user default privilege map (user zones OR'ed)
			
			t.timestamps
		end
		
		create_table :controller_zones do |t|
			t.references :control_system
			t.references :zone
			
			t.timestamps
		end
		
		#
		# Trusted devices
		# => System 0 cannot trust any interface as does not have an explicit controller id
		#
		create_table :trusted_devices do |t|
			t.references	:user,			:allow_null => false
			t.references	:control_system,:allow_null => false
			
			t.string	:trusted_by,		:allow_null => false
			t.string	:description,		:allow_null => false
			t.text		:notes
			
			t.string	:one_time_key
			t.datetime	:expires			# Expire devices (staff member leaving etc)
			t.datetime	:last_authenticated	# Cache update indicator
			
			t.timestamps
		end
	end
end

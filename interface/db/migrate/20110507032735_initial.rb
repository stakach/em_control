class Initial < ActiveRecord::Migration
	def self.up
		create_table :controllers do |t|
			t.string	:name,	:allow_null => false
			t.text	:description
			t.boolean	:active,	:default => true,	:allow_null => false
		end
		
		create_table :dependencies do |t|
			t.references	:dependency
			
			t.string		:classname,		:allow_null => false
			t.string		:filename,		:allow_null => false
			
			t.string		:module_name	# Type name (Projector)
			t.string		:actual_name	# Real name (All NEC Projectors)
			t.text		:description
		end
		
		create_table :controller_devices do |t|
			t.references	:controller,	:allow_null => false
			t.references	:dependency,	:allow_null => false

			t.string	:ip,	:allow_null => false
			t.integer	:port,:allow_null => false
			
			t.boolean	:tls,	:default => false,	:allow_null => false
			t.boolean	:udp,	:default => false,	:allow_null => false
			
			t.integer	:priority,	:default => 0
		end
		
		create_table :controller_logics do |t|
			t.references	:controller,	:allow_null => false
			t.references	:dependency,	:allow_null => false
		end
		
		create_table :settings do |t|
			t.references :object, :polymorphic => true		

			t.string	:name,		:allow_null => false
			t.text	:description
			
			t.integer	:value_type,	:allow_null => false
			
			t.float	:float_value
			t.integer	:integer_value	# doubles as boolean (type -1)
			t.text	:text_value
			t.datetime	:datetime_value
		end
	end

	def self.down
	end
end

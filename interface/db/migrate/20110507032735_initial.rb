class Initial < ActiveRecord::Migration
	def self.up
		create_table :schemes do |t|
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
		
		create_table :scheme_devices do |t|
			t.references	:scheme,		:allow_null => false
			t.references	:dependency,	:allow_null => false

			t.string	:ip,	:allow_null => false
			t.integer	:port,:allow_null => false
			
			t.boolean	:tls,	:default => false,	:allow_null => false
			t.boolean	:udp,	:default => false,	:allow_null => false
			
			t.text	:cert,				:allow_null => false	# cert file or text whatever
			t.string	:username
			t.string	:password
			
			t.integer		:priority,	:default => 0
		end

		create_table :scheme_logics do |t|
			t.references	:dependency,	:allow_null => false
			t.references	:scheme,		:allow_null => false
		end
	end

	def self.down
	end
end

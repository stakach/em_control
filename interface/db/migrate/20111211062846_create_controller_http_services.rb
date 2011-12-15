class CreateControllerHttpServices < ActiveRecord::Migration
	def change
		create_table :controller_http_services do |t|
			
			t.references	:control_system,:allow_null => false
			t.references	:dependency,	:allow_null => false

			t.string	:uri,	:allow_null => false
			
			t.integer	:priority,	:default => 0,	:allow_null => false
			t.string	:custom_name	# projector_left
			
			t.timestamps
		end
		
		add_column		:dependencies, :default_uri, :string
	end
end

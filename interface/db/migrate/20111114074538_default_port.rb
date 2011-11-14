class DefaultPort < ActiveRecord::Migration
	def up
  		add_column		:dependencies, :default_port, :integer
	end

	def down
		remove_column	:dependencies, :default_port
	end
end

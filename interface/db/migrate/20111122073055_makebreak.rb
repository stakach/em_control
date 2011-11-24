class Makebreak < ActiveRecord::Migration
	def up
  		add_column		:controller_devices, :makebreak, :boolean, :default => false,	:allow_null => false
	end

	def down
		remove_column	:controller_devices, :makebreak
	end
end

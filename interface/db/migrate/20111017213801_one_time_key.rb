class OneTimeKey < ActiveRecord::Migration
	def up
		rename_column	:trusted_devices, :description, :reason
	end

	def down
		rename_column	:trusted_devices, :reason, :description
	end
end

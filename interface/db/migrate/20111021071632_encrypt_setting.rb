class EncryptSetting < ActiveRecord::Migration
	def up
		add_column		:settings, :encrypt_setting, :boolean, :default => false
	end

	def down
		remove_column	:settings, :encrypt_setting
	end
end

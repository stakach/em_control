class AddingGroups < ActiveRecord::Migration
	def up
		create_table :groups do |t|
			t.references	:auth_source	# Optional (LDAP)
			t.boolean		:auth_only,	:allow_null => false, :default => false
			
			t.string	:identifier,	:allow_null => false
			t.string	:description
			
			t.text		:notes
		end
		
		
		create_table :user_groups do |t|
			t.references	:group
			t.references	:user
			
			t.boolean		:group_admin,	:allow_null => false, :default => false
			t.boolean		:forced,		:allow_null => false, :default => false	# prevents user being removed from group through automated syncing
			t.boolean		:revoke_access,	:allow_null => false, :default => false # disables access otherwise enabled by automated syncing
		end
		
		
		#add_column		:users, :username, :string	# use identifier field
		add_column		:users, :firstname, :string
		add_column		:users, :lastname, :string
		add_column		:users, :email, :string
		add_column		:users, :password_digest, :string
		add_column		:users, :login_count, :integer,	:allow_null => false,	:default => 0
		
		
		#
		# Encrypt passwords (previously only encoded)
		#
		add_column		:auth_sources, :ordinal, :integer,	:allow_null => false, :default => 100
		add_column		:auth_sources, :encrypted_password, :string
		AuthSource.reset_column_information
		AuthSourceLdap.reset_column_information
		AuthSourceLdap.all do |auth|
			auth.encrypted_password = auth.account_password
			auth.save!
		end
		remove_column :auth_sources, :account_password
	end

	def down
	end
end

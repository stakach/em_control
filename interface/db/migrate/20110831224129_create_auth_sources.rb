class CreateAuthSources < ActiveRecord::Migration
	def change
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
	end
end
	
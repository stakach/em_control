# redMine - project management software
# Copyright (C) 2006  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

require 'net/ldap'
require 'iconv'
require 'base64'

class AuthSourceLdap < AuthSource
	validates_presence_of :host, :port, :attr_login, :name
	validates_length_of :host, :encrypted_password, :maximum => 255, :allow_nil => true
	validates_length_of :account, :base_dn, :maximum => 255, :allow_nil => true
	validates_length_of :attr_login, :attr_firstname, :attr_lastname, :attr_mail, :maximum => 255, :allow_nil => true
	validates_numericality_of :port, :only_integer => true
	
	before_validation :strip_ldap_attributes
	after_initialize :set_port
	
	
	#attr_encrypted :password, :key => 'aca secret key:dcJD9eSRqYwxxPHK4g6ASIyiDsM=', :algorithm => 'aes-256-ecb'
	
	
	def set_port
		self.port = 389 if self.port == 0
	end
	
	def authenticate(login, pass)
		return nil if login.blank? || pass.blank?
		
		#
		# Query the LDAP for the user information if it exists
		#
		attrs = get_user_dn(login)
		
		if attrs && attrs[:dn] && authenticate_dn(attrs[:dn], pass)	# Confirm the users credentials are correct
			logger.debug "Authentication successful for '#{login}'" if logger && logger.debug?
			user = nil
			
			#
			# Check user is in any of the valid groups
			#	A user can be a group in itself too if a matching group exists
			#
			auth_groups = self.groups.select('identifier').map {|group| group.identifier}
			users_groups = attrs[:member_of].map {|group| group.strip}
			users_groups << login
			
			#
			# Check for common ground
			#
			common = auth_groups & users_groups
			if common.length > 0
				user = User.where('identifier = ? AND auth_source_id = ?', login, self.id).first
				if user.nil?
					user = User.new
					user.identifier = login
					user.auth_source_id = self.id
					user.password = 'LDAP'
					user.password_confirmation = 'LDAP'
					user.save!
				end
				
				#
				# Remove user from groups they are no longer apart of (LDAP is king)
				#	This does not call callbacks as it is not required for the relation
				#
				user.user_groups.where('user_groups.forced = ? AND user_groups.id IN (SELECT groups.id FROM groups WHERE groups.auth_source_id = ? AND groups.identifier NOT IN (?))', false, self.id, common).delete_all
				
				#
				# Add any groups that do not have existing relationships and exist in the database
				#
				user.groups << Group.select('id').where('groups.auth_source_id = ? AND groups.identifier IN (?) AND NOT EXISTS (SELECT * FROM user_groups WHERE user_groups.user_id = ? AND user_groups.group_id = groups.id)', self.id, common, user.id)
				#Group.select('id').where('auth_source_id = ? AND identifier IN (?) AND NOT EXISTS (SELECT * FROM user_groups WHERE user_groups.user_id = ? AND user_groups.group_id = groups.id)', self.id, common, user.id).each do |group|
				#	user.user_groups << UserGroup.new({:group_id => group.id})
				#end
				
				user.firstname = attrs[:firstname] unless attrs[:firstname].blank?
				user.lastname = attrs[:lastname] unless attrs[:lastname].blank?
				user.email = attrs[:mail] unless attrs[:mail].blank?
				user.login_count += 1
				user.save!
				
				
				return user
			end
		end
		
		return nil
	rescue  Net::LDAP::LdapError => text
		raise "LdapError: " + text
	end
	
	# test the connection to the LDAP
	def test_connection
		ldap_con = initialize_ldap_con(self.account, self.encrypted_password)
		ldap_con.open do |ldap|
		end
	rescue  Net::LDAP::LdapError => text
		raise "LdapError: " + text
	end
	
	def auth_method_name
		"LDAP"
	end
	
	#
	# Encode the LDAP password so it is not clear text in the database
	#	TODO:: Depreciate for next version (db field removed)
	#
	def account_password
		if self[:account_password].blank?
			return ""
		end
	
		Base64.decode64(self[:account_password])
	end
	
	
	
	private
	
	def strip_ldap_attributes
		[:attr_login, :attr_firstname, :attr_lastname, :attr_mail].each do |attr|
			write_attribute(attr, read_attribute(attr).strip) unless read_attribute(attr).nil?
		end
	end
	
	def initialize_ldap_con(ldap_user, ldap_password)
		options = { :host => self.host,
			:port => self.port,
			:encryption => (self.tls ? :simple_tls : nil)
		}
		options.merge!(:auth => { :method => :simple, :username => ldap_user, :password => ldap_password }) unless ldap_user.blank? && ldap_password.blank?
		Net::LDAP.new options
	end
	
	def get_user_attributes_from_ldap_entry(entry)
		{
			:dn => entry.dn,
			:firstname => AuthSourceLdap.get_attr(entry, self.attr_firstname),
			:lastname => AuthSourceLdap.get_attr(entry, self.attr_lastname),
			:mail => AuthSourceLdap.get_attr(entry, self.attr_mail),
			:auth_source_id => self.id
		}
	end
	
	# Return the attributes needed for the LDAP search.  It will only
	# include the user attributes if on-the-fly registration is enabled
	def search_attributes
		['dn', self.attr_firstname, self.attr_lastname, self.attr_mail, self.attr_member]
	end
	
	# Check if a DN (user record) authenticates with the password
	def authenticate_dn(dn, password)
		if dn.present? && password.present?
			initialize_ldap_con(dn, password).bind
		end
	end
	
	# Get the user's dn and any attributes for them, given their login
	def get_user_dn(login)
		ldap_con = initialize_ldap_con(self.account, self.encrypted_password)
		login_filter = Net::LDAP::Filter.eq( self.attr_login, login ) 
		object_filter = Net::LDAP::Filter.eq( "objectClass", "*" ) 
		attrs = {}
		
		ldap_con.search( :base => self.base_dn, 
			:filter => object_filter & login_filter, 
			:attributes=> search_attributes) do |entry|
			
			attrs = get_user_attributes_from_ldap_entry(entry)
			attrs.merge!(:member_of => entry[self.attr_member].map {|e| /CN=([^,]+?)[,$]/i.match(e).captures.first })
			
			logger.debug "DN found for #{login}: #{attrs[:dn]}" if logger && logger.debug?
		end
		
		
		attrs
	end
	
	def self.get_attr(entry, attr_name)
		if !attr_name.blank?
			entry[attr_name].is_a?(Array) ? entry[attr_name].first : entry[attr_name]
		end
	end
end


require 'base64'
require 'encryptor'

class AuthSource < ActiveRecord::Base
	has_many :users, :dependent => :destroy
	has_many :groups, :dependent => :destroy
	
	
	validates_presence_of :name
	validates_uniqueness_of :name
	
	
	after_initialize	:decrypt_password
	before_save			:encrypt_password
	
	
	
	AUTH_TYPES = [["LDAP Authentication", AuthSourceLdap],["Local Database", AuthSourceLocal]]
	
	
	def self.search(search_terms = nil)
		result = AuthSource.scoped
		
		if(!search_terms.nil? && search_terms != "")
			search = '%' + search_terms.chomp.gsub(' ', '%').downcase + '%'
			result = result.where('LOWER(name) LIKE ? OR LOWER(type) LIKE ? OR LOWER(host) LIKE ?', search, search, search)
		end
		
		return result
	end
	
	
	def authenticate(login, password)
	end
	
	def test_connection
	end
	
	def auth_method_name
		"Abstract"
	end
	
	
	protected
	
	
	def decrypt_password
		if self[:encrypted_password].blank?
			self[:encrypted_password] = ""
		else
			self[:encrypted_password] = Encryptor.decrypt(Base64.decode64(self[:encrypted_password]), {:key => 'dcJD9eSRqYwxxPHK4g6ASIyiDsM=', :algorithm => 'aes-256-cbc'})
		end
		
		self[:auth_type] = self[:type]
	end
	
	def encrypt_password
		if self[:encrypted_password].blank?
			self[:encrypted_password] = ""
		else
			self[:encrypted_password] = Base64.encode64(Encryptor.encrypt(self[:encrypted_password], {:key => 'dcJD9eSRqYwxxPHK4g6ASIyiDsM=', :algorithm => 'aes-256-cbc'}))
		end
		
		self[:type] = self[:auth_type]
	end
end

class AuthSource < ActiveRecord::Base
	has_many :users, :dependent => :destroy
	
	
	validates_presence_of :name
	validates_uniqueness_of :name
	
	
	AUTH_TYPES = [["LDAP Authentication", AuthSourceLdap]]
	
	
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
	
	# Try to authenticate a user not yet registered against available sources
	def self.authenticate(login, password)
		AuthSource.all.each do |source|
			begin
				logger.debug "Authenticating '#{login}' against '#{source.title}'" if logger && logger.debug?
				attrs = source.authenticate(login, password)
			rescue => e
				logger.error "Error during authentication: #{e.message}"
				attrs = nil
			end
			return attrs if attrs
		end
		return nil
	end
end

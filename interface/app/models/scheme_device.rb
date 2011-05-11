class SchemeDevice < ActiveRecord::Base

	belongs_to	:scheme
	belongs_to	:dependency

end

class SchemeLogic < ActiveRecord::Base

	belongs_to	:dependency
	belongs_to	:scheme

end

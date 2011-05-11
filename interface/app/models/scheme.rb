class Scheme < ActiveRecord::Base

	has_many :devices,	:class_name => "SchemeDevice",	:dependent => :destroy
	has_many :logics,		:class_name => "SchemeLogic",		:dependent => :destroy

end

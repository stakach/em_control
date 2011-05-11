class Dependency < ActiveRecord::Base

	has_many :scheme_devices,	:dependent => :destroy
	has_many :scheme_logics,	:dependent => :destroy
	
	scope :for_scheme, lambda {|scheme|
		includes(:scheme_devices, :scheme_logics)
		.where("(scheme_devices.dependency_id = dependencies.id AND scheme_devices.scheme_id = ?) OR (scheme_logics.dependency_id = dependencies.id AND scheme_logics.scheme_id = ?)", scheme.id, scheme.id)
	}

end

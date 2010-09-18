class JobApplication < ActiveRecord::Base
  unloadable

  # associations
  belongs_to :applicant
  belongs_to :job

  has_many :job_application_referrals
  has_many :job_application_custom_fields
  has_many :job_application_materials

  # TODO incorporate reject_if code
  accepts_nested_attributes_for :job_application_referrals, :allow_destroy => true
  accepts_nested_attributes_for :job_application_custom_fields, :allow_destroy => true
  accepts_nested_attributes_for :job_application_materials, :allow_destroy => true
 
  # validation
  # TODO implement validations

  # constants
  # TODO convert these values into variables that can be set from a settings page within Redmine
  SUBMISSION_STATUS = ['Unsubmitted','Submitted']
  ACCEPTANCE_STATUS = ['Accepted', 'Declined', 'Pending']
end

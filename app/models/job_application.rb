class JobApplication < ActiveRecord::Base
  unloadable

  # associations
  belongs_to :applicant
  belongs_to :job

  has_many :job_application_referrals
  #has_many :job_application_custom_fields
  has_many :job_application_materials
  
  acts_as_customizable
  acts_as_attachable :delete_permission => :manage_documents
  
  acts_as_activity_provider :find_options => {:select => "#{JobApplication.table_name}.*", 
                                              :joins => "LEFT JOIN #{Applicant.table_name} ON #{Applicant.table_name}.id=#{JobApplication.table_name}.applicant_id"}

  # TODO incorporate reject_if code
  accepts_nested_attributes_for :job_application_referrals, :allow_destroy => true
  #accepts_nested_attributes_for :job_application_custom_fields, :allow_destroy => true
  accepts_nested_attributes_for :job_application_materials, :reject_if => proc { |attributes| attributes['document'].blank? }, :allow_destroy => true

  # constants
  # TODO convert these values into variables that can be set from a settings page within Redmine
  SUBMISSION_STATUS = ['Submitted', 'Withdrew Application', "Not Submitted"].insert(0, "")
  OFFER_STATUS = ['Offer made, response pending', 'Offer made and accepted', 'Offer made and declined', 'No offer will be made, letter not yet sent', 'No offer, letter sent ', 'Withdrew application, letter not necessary'].insert(0, "")
  REVIEW_STATUS = ['Reviewed - promising, reserved', 'Reviewed - promising, deferred', 'Reviewed - deferred', 'Reviewed - generally unqualified'].insert(0, "")
  
  def validate
     
  end
  
  def available_custom_fields
    self.job.all_job_app_custom_fields || []
  end 
  
end

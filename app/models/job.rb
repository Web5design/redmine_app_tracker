class Job < ActiveRecord::Base
  # associations
  belongs_to :apptracker
  # FIXME Should job_applications to a job be destroyed if a job is deleted?
  has_many :job_applications
  has_many :applicants, :through => :job_applications
  #has_many :job_custom_fields, :dependent => :destroy
  has_many :job_attachments, :dependent => :destroy
#  has_and_belongs_to_many :job_custom_fields,
#                          :class_name => 'JobCustomField',
#                          :order => "#{CustomField.table_name}.position",
#                          :join_table => "#{table_name_prefix}custom_fields_jobs#{table_name_suffix}",
#                          :association_foreign_key => 'custom_field_id'

  has_and_belongs_to_many :job_application_custom_fields,
                          :class_name => 'JobApplicationCustomField',
                          :order => "#{CustomField.table_name}.position",
                          :join_table => "#{table_name_prefix}custom_fields_job_applications#{table_name_suffix}",
                          :association_foreign_key => 'custom_field_id'
  
  acts_as_customizable
  acts_as_attachable :delete_permission => :manage_documents
 
  # TODO if necessary, modify :reject_if code for more advanaced error checking
  #accepts_nested_attributes_for :job_custom_fields, :allow_destroy => true
  
  accepts_nested_attributes_for :job_application_custom_fields, :allow_destroy => true
  accepts_nested_attributes_for :job_attachments, :reject_if => proc { |attributes| attributes['document'].blank? }, :allow_destroy => true

  # validation
  validates_presence_of :category, :status, :title, :description, :attachment_count, :application_material_count, :referrer_count
  # validates_uniqueness_of :title
  
  # constants
  # TODO convert these values into variables that can be set from a settings page within Redmine
  # The first entry of the JOB_STATUS array is reserved for allowing anonymous to see a job's details
  JOB_STATUS = ["Active", "Inactive", "Filled"]
  JOB_CATEGORIES = ["Internship", "Fellowship", "Program", "Staff"]

end

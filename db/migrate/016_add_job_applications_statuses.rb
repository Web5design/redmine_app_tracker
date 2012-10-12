class AddJobApplicationsStatuses < ActiveRecord::Migration
  def self.up
    add_column :job_applications, :offer_status, :string
    add_column :job_applications, :review_status, :string
    remove_column :job_applications, :acceptance_status
  end

  def self.down
    remove_column :job_applications, :offer_status
    remove_column :job_applications, :review_status
    add_column :job_applications, :acceptance_status, :string
  end
end
class AddJobApplicationReferralsAffiliation < ActiveRecord::Migration
  def self.up
    add_column :job_application_referrals, :affiliation, :string
    add_column :job_application_referrals, :relationship, :string
  end

  def self.down
    remove_column :job_application_referrals, :affiliation
    remove_column :job_application_referrals, :relationship
  end
end
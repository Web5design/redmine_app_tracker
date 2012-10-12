class Notification < Mailer
  
  def application_submitted(job_application)
    # Send the email to the applicant
    @message = job_application.job.application_followup_message
    recipients Applicant.find_by_id(job_application.applicant_id).email
    subject "Application Submitted"
    body :user => Applicant.find_by_id(job_application.applicant_id),
         :url => url_for(:controller => 'job_application', :action => 'show', :id => job_application.id, :apptracker_id => job_application.apptracker_id)
    content_type "text/html"     
  end
  
  def application_updated(job_application)
    # Send the email to the applicant
    recipients Applicant.find_by_id(job_application.applicant_id).email
    subject "Berkman Center Application Updated"
    body :user => Applicant.find_by_id(job_application.applicant_id),
         :url => url_for(:controller => 'job_application', :action => 'show', :id => job_application.id, :apptracker_id => job_application.apptracker_id)
    content_type "text/html"
  end
  
  def request_referral(job_application, email, job_application_referral)
    @job_application = job_application
    @job_application_referral = job_application_referral
    # Send email to referrer
    recipients email
    subject "Link to upload a letter of recommendation in support of a Berkman Center fellowship application"
    body :user => Applicant.find_by_id(job_application.applicant_id),
         :url => url_for(:controller => 'job_application_referral', :action => 'show', :id => job_application_referral.id, :job_app_id => job_application.id, :apptracker_id => job_application.apptracker_id)
    content_type "text/html"     
  end
  
  def referral_complete(job_application, referrer_email)
    @job_application = job_application
    # Send the email to the applicant
    recipients Applicant.find_by_id(job_application.applicant_id).email
    subject "A letter of recommendation has been submitted on your behalf"
    body :user => Applicant.find_by_id(job_application.applicant_id),
         :url => url_for(:controller => 'job_application', :action => 'show', :id => job_application.id, :apptracker_id => job_application.apptracker_id)
    content_type "text/html"     
  end
  
  def referral_complete_to_ref(job_application, referrer_email)
    @job_application = job_application
    # Send the email to the referrer
    recipients referrer_email
    subject "Your letter of recommendation has been successfully submitted"
    body :user => Applicant.find_by_id(job_application.applicant_id),
         :url => url_for(:controller => 'job_application', :action => 'show', :id => job_application.id, :apptracker_id => job_application.apptracker_id)
    content_type "text/html"     
  end
  
end
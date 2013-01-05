# TODO implement this controller
class JobApplicationReferralsController < ApplicationController
  unloadable
  
  helper :attachments
  include AttachmentsHelper


  def index
    @apptracker = Apptracker.find(params[:apptracker_id])
    if(User.current.admin?)
      if(params[:view_scope] == 'job' || (params[:applicant_id].nil? && params[:apptracker_id].nil?))
        # if viewing all job applications for a particular job
        @job_application_referrals = Job.find(params[:job_id]).job_application.job_application_referrals
      elsif(params[:view_scope] == 'applicant' || (params[:job_id].nil? && params[:apptracker_id].nil?))
        # if viewing all job referrals for a particular user/applicant
        @job_application_referrals = Applicant.find(params[:applicant_id]).job_application.job_application_referrals
      else
        # if viewing all job applications for an apptracker
        @jobs = Apptracker.find(params[:apptracker_id]).jobs
        @job_application_referral = Array.new
        @jobs.each do |job|
          job.job_applications.each do |ja|
            @job_application_referral << ja.job_application_referrals
          end
        end
      end
      @job_application_referral.flatten!

    elsif(User.current.logged?)
      @applicant = Applicant.find_by_email(User.current.mail)
      @job_application_referral = Array.new
      
      if params[:job_application_id].nil?
        @job_applications = @applicant.job_applications
        @job_applications.each do |ja|
          @job_application_referral << ja.job_application_referrals.find(:all, :include => [:attachments])
        end
        @job_application_referral.flatten!
      else
        @job_application_referral = JobApplication.find(params[:job_application_id]).job_application_referrals.find(:all, :include => [:attachments])
      end
    end
  end

  def show
  end

  def new
    @job_application = JobApplication.find(params[:id])
    @applicant = @job_application.applicant_id
    @apptracker = Apptracker.find(@job_application.apptracker_id)
    @job = Job.find(@job_application.job_id)
    @job_application_referral = @job_application.job_application_referrals.build()
  end

  def create
    @job_application = JobApplication.find(params[:job_application_referral][:job_application_id])
    
    @job_application_referral = @job_application.job_application_referrals.build(params[:job_application_referral])
    @job_application_referral.save
    
    # Send email to referrer to request referral
    Notification.deliver_request_referral(@job_application, @job_application_referral.email, @job_application_referral)
    
    if @job_application.job_application_referrals.length < @job_application.job.referrer_count.to_i
      redirect_to(new_referral_job_applications_url(:job_application => @job_application.id, :apptracker_id => @job_application.apptracker_id), :notice => "Please fill in another referral.")
    else  
      redirect_to(job_applications_url(:apptracker_id => @job_application.apptracker_id, :applicant_id => @job_application.applicant_id), :notice => %Q[<p>Your reference requests have been submitted. If you are ready to add in application information and upload your application materials, click <a href='#{url_for(edit_job_application_url(@job_application.id, :apptracker_id => @job_application.apptracker_id))}'>here</a> or the 'Edit Application' link below.</p><p>Do not worry if you are not yet ready to finish other parts of the application - you have until the application deadline to do so.</p><p>When you are ready to submit your other application materials, visit the <a href="https://cyber.law.harvard.edu/apply/jobs/7?apptracker_id=3">fellowship listing page</a>, log back into the Application Tracker, and click on the 'Apply to this job' link at the top of the page.</p>])
    end 
  end

  def edit
    @job_application_referral = JobApplicationReferral.find(params[:id])
    @job_application = JobApplication.find(params[:job_app_id])
    @applicant = @job_application.applicant_id
    @apptracker = Apptracker.find(@job_application.apptracker_id)
    @job = Job.find(@job_application.job_id)
  end

  def update
    @job_application = JobApplication.find(params[:job_application_referral][:job_application_id])
    params[:job_application_referral][:referral_text] = params[:attachments]["1"][:description]
    @job_application_referral = JobApplicationReferral.find(params[:id])
    
    #@job_application_referral = @job_application.job_application_referrals.build(params[:job_application_referral])
    @job_application_referral.update_attributes(params[:job_application_referral])
    
    attachments = Attachment.attach_files(@job_application_referral, params[:attachments])
    render_attachment_warning_if_needed(@job_application_referral)

    unless attachments[:files].empty? && @job_application_referral.attachments.empty?
      # Send email to applicant and referrer that referral has been submitted
      Notification.deliver_referral_complete(@job_application, @job_application_referral.email)
      Notification.deliver_referral_complete_to_ref(@job_application, @job_application_referral.email)
    
      redirect_to :controller => 'jobs', :action => 'index', :apptracker_id => @job_application.apptracker_id, :notice => "Referral has been submitted."
    else
      flash[:error] = "Please upload a referral."
      redirect_to :back
      
      #format.html { render :action => "edit" }
    end    
  end

  def destroy
    @job_application_referral = JobApplicationReferral.find(params[:id])
    @job_application = JobApplication.find(@job_application_referral.job_application_id)
    @applicant = Applicant.find(@job_application.applicant_id)
	  unless User.current.admin? || @applicant.email == User.current.mail
	    flash[:error] = "You are not authorized to view this section."
		  redirect_to('/') and return
	  end
    @apptracker = Apptracker.find(@job_application.apptracker_id)
    
    # destroy the job_application_referral, and indicate a message to the user upon success/failure
    @job_application_referral.destroy ? flash[:notice] = "#{@applicant.first_name} #{@applicant.last_name}\'s referral has been deleted." : flash[:error] = "Error: #{@applicant.first_name} #{@applicant.last_name}\'s referral could not be deleted."
    
    respond_to do |format|
      format.html { redirect_to(job_application_url(@job_application, :apptracker_id => @apptracker.id)) }
    end
    
  end

  def request_referral
    @job_application = JobApplication.find(params[:id])
    @emails = params[:email].split(',')
    #Send Notification to Referrer
    @emails.each do |email|
      Notification.deliver_request_referral(@job_application, email)
    end
    
    redirect_to(job_applications_url(:apptracker_id => @job_application.apptracker_id, :applicant_id => @job_application.applicant_id), :notice => "Referral request has been sent.")
  end
  
  def resend_referral
    @job_application = JobApplication.find(params[:job_application])
    @job_application_referral = JobApplicationReferral.find(params[:job_application_referral])
    Notification.deliver_request_referral(@job_application, @job_application_referral.email, @job_application_referral)
    redirect_to(job_application_referrals_url(:job_id => @job_application.job.id, :job_application_id => @job_application.id, :apptracker_id => @job_application.apptracker_id), :notice => "Referral request has been sent.")
  end  
end

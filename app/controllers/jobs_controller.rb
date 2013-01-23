require 'rubygems'
require 'zip/zipfilesystem'
require 'csv'
require 'tempfile'

class JobsController < ApplicationController
  unloadable
  before_filter :require_admin, :except => [:index, :show, :register, :filter, :filter_by_status, :export_to_csv, :zip_some, :zip_all, :zip_filtered, :zip_filtered_single, :export_filtered_to_csv]
  
  helper :attachments
  include AttachmentsHelper
  helper :custom_fields
  include CustomFieldsHelper
  helper :sort
  include SortHelper
  
  default_search_scope :jobs

  # GET /jobs
  # GET jobs_url
  def index
    sort_init 'submission_date', 'desc'
    sort_update %w(title category short_desc status submission_date)
    
    # secure the parent apptracker id and find its jobs
    @apptracker = Apptracker.find(params[:apptracker_id])
    if(User.current.admin? || User.current.member_of?(@apptracker.project))
      @jobs = @apptracker.jobs.find(:all, :order => sort_clause)
    else
      @jobs = @apptracker.jobs.find(:all, :conditions => ["status = ? and submission_date > ?", Job::JOB_STATUS[0], DateTime.now], :order => sort_clause)
    end
  end
  
  # GET /jobs/1
  # GET job_url(:id => 1)
  def show
    @job = Job.find(params[:id])
    @apptracker = @job.apptracker
    @admin_view = params[:admin_view]
    
    session[:auth_source_registration] = nil
    @user = User.new(:language => Setting.default_language)
    
    sort_init 'created_at', 'desc'
    sort_update 'last_name' => "#{Applicant.table_name}.last_name",
                'id' => "#{JobApplication.table_name}.id",
                'review_status' => "#{JobApplication.table_name}.review_status",
                'offer_status' => "#{JobApplication.table_name}.offer_status",
                'created_at' => "#{JobApplication.table_name}.created_at"
    #sort_update %w(id submission_status, acceptance_status, created_at)
    
    @job_count = @job.job_applications.count
    @per_page = 10
    @job_pages = Paginator.new self, @job_count, @per_page, params[:page]
    
    @job_applications = @job.job_applications.find(:all, :order => sort_clause, :limit => @job_pages.items_per_page, :offset => @job_pages.current.offset)
    
    @job_attachments = @job.job_attachments.build
    job_attachments = @job.job_attachments.find :first, :include => [:attachments]
    @job_attachment = job_attachments
    
    respond_to do |format|
      format.html #show.html.erb
    end
  end

  # GET /jobs/new
  # Get new_job_url
  def new
    # secure the parent apptracker id and create a new job
    @apptracker = Apptracker.find(params[:apptracker_id])
    
    if(params[:job_id].nil?)
      @job = @apptracker.jobs.new
    else
      @job = @apptracker.jobs.find(params[:job_id])
    end
    respond_to do |format|
        format.html # new.html.erb
    end
  end
  
  # POST /jobs
  # POST jobs_url
  def create
    # create a job in its parent apptracker
    @apptracker = Apptracker.find(params[:job][:apptracker_id])
    @job = @apptracker.jobs.new(params[:job])    
    unless params[:application_material_types].nil?
      @job.application_material_types = params[:application_material_types].join(",") + "," + params[:other_app_materials]
    else
      @job.application_material_types = params[:other_app_materials]  
    end  
    
    respond_to do |format|
      if(@job.save)
        
        #if job saved then create the job attachments
        #@job_attachments = params[:job][:job_attachments_attributes]["0"]
        job_file = Hash.new
        job_file["job_id"] = @job.id
        job_file["name"] = @job.title
        job_file["filename"] = @job.title
        job_file["notes"] = @job.title
        @job_attachment = @job.job_attachments.build(job_file)
        @job_attachment.save
        attachments = Attachment.attach_files(@job_attachment, params[:attachments])
        render_attachment_warning_if_needed(@job_attachment)
        
        flash[:notice] = l(:notice_successful_create)
        
        # no errors, redirect to second part of form
        format.html { redirect_to(jobs_url(:apptracker_id => @apptracker.id)) }
      else
        # validation prevented save; redirect back to new.html.erb with error messages
        format.html { render :action => "new" }
      end
    end
  end

  # GET /jobs/1/edit
  # GET edit_job_url(:id => 1)
  def edit
    # secure the parent apptracker id and find the job to edit
    @apptracker = Apptracker.find(params[:apptracker_id])
    @job = @apptracker.jobs.find(params[:id])
    @job_attachment = @job.job_attachments.find :first, :include => [:attachments]

    @custom_field = begin
      "JobApplicationCustomField".to_s.constantize.new(params[:custom_field])
    rescue
    end
    
    @job_application_custom_fields = JobApplicationCustomField.find(:all, :order => "#{CustomField.table_name}.position")
    
  end

  # PUT /jobs/1
  # PUT job_url(:id => 1)
  def update
    # find the job within its parent apptracker
    @apptracker = Apptracker.find(params[:job][:apptracker_id])
    @job = @apptracker.jobs.find(params[:id])
    # update the job's attributes, and indicate a message to the user opon success/failure
    respond_to do |format|
      if(@job.update_attributes(params[:job]))
        unless params[:application_material_types].nil?
          @job.application_material_types = params[:application_material_types].join(",") + "," + params[:other_app_materials]
        else
          @job.application_material_types = params[:other_app_materials]  
        end
        @job.save
        # no errors, redirect with success message
        @job_attachment = JobAttachment.find(:first, :conditions => {:job_id => @job.id})
        job_file = Hash.new
        job_file["job_id"] = @job.id
        job_file["name"] = @job.title
        job_file["filename"] = @job.title
        job_file["notes"] = @job.title
        @job_attachment.update_attributes(job_file)
        attachments = Attachment.attach_files(@job_attachment, params[:attachments])
        render_attachment_warning_if_needed(@job_attachment)
        
        format.html { redirect_to(edit_job_url(@job, :apptracker_id => @apptracker.id), :notice => "\'#{@job.title}\' has been updated.") }
      else
        # validation prevented update; redirect to edit form with error messages
        @job_attachment = @job.job_attachments.find :first, :include => [:attachments]
        @custom_field = begin
          "JobApplicationCustomField".to_s.constantize.new(params[:custom_field])
        rescue
        end
        @job_application_custom_fields = JobApplicationCustomField.find(:all, :order => "#{CustomField.table_name}.position")
        format.html { render :action => "edit"}
      end
    end
  end

  # DELETE /jobs/1
  # DELETE job_url(:id => 1)
  def destroy
    # create a job in its parent apptracker
    @apptracker = Apptracker.find(params[:apptracker_id])
    @job = @apptracker.jobs.find(params[:id])

    # destroy the job, and indicate a message to the user upon success/failure
    @job.destroy ? flash[:notice] = "\'#{@job.title}\' has been deleted." : flash[:error] = "Error: \'#{@job.title}\' could not be deleted."
    
    respond_to do |format|
      format.html { redirect_to(jobs_url(:apptracker_id => @apptracker.id)) }
    end
  end
  
  def create_custom_field
    custom_field = CustomField.new(params[:custom_field])
    custom_field.type = params[:type]
    custom_field = begin
      if params[:type].to_s.match(/.+CustomField$/)
        params[:type].to_s.constantize.new(params[:custom_field])
      end
    rescue
    end
    job = Job.find_by_id params[:id]
    
    if custom_field.save
      flash[:notice] = l(:notice_successful_create)
      call_hook(:controller_custom_fields_new_after_save, :params => params, :custom_field => custom_field)
      cf_ids = job.all_job_app_custom_fields.collect {|cfield| cfield.id }
      cf_ids << custom_field.id
      cf = {"job_application_custom_field_ids" => cf_ids}
      job.attributes = cf
      job.save
    else
      flash[:notice] = "Custom field could not be added."
    end
    
    redirect_to :action => "edit", :id => job, :apptracker_id => job.apptracker_id
  end

  # Removes a CustomField from an Job.
  #
  # @return Nothing.
  def remove_custom_field
    job = Job.find_by_id params[:id]
    custom_field = JobApplicationCustomField.find_by_id params[:existing_custom_field]
    job.job_application_custom_fields.delete custom_field
    job.save
    redirect_to :action => "edit", :id => job, :apptracker_id => job.apptracker_id
  end
  
  def zip_all
    @job = Job.find(params[:job])
    unless User.current.admin? || @job.is_manager?
      flash[:error] = "You are not authorized to view this section."
  		redirect_to('/') and return
  	end
    @material_types = @job.application_material_types.split(',')
    @file_name = @job.title.gsub(/[^a-zA-Z\d]/, '-')
    @zip_file_path = "#{RAILS_ROOT}/tmp/#{@file_name}-all-materials.zip"
    @ja_materials = Array.new
    @ja_referrals = Array.new
    filepaths = Array.new
    counter = 1
    material_id_hash = Hash.new
    
    @applicants = @job.applicants
    @applications = JobApplication.find(:all, :conditions => {:job_id => @job.id})
    
    @applications.each do |app|
      @ja_materials << JobApplicationMaterial.find(:first, :conditions => {:job_application_id => app.id})
      unless @ja_referrals.nil?
        @ja_referrals << JobApplicationReferral.find(:all, :conditions => {:job_application_id => app.id})
      end  
    end  
    
    unless @ja_referrals.nil?
      if @material_types.include?("Proposed Work")
        @material_types.insert(@material_types.index("Proposed Work") + 1, "Referral")
      elsif @material_types.include?("Cover Letter")
        @material_types.insert(@material_types.index("Cover Letter") + 1, "Referral")
      elsif @material_types.include?("Resume or CV")
        @material_types.insert(@material_types.index("Resume or CV") + 1, "Referral")
      else 
        @material_types.insert(@material_types.index("Resume or CV") + 1, "Referral")
      end  
    end
      
    @material_types.each do |material|
      material_id_hash[material] = "%03d" % counter.to_s + "_" + material.gsub(/ /, '_')
      counter = counter + 1
    end

    Zip::ZipFile.open(@zip_file_path, Zip::ZipFile::CREATE) do |zipfile|
      @applicants.each do |applicant|
        if zipfile.find_entry("#{applicant.last_name}_#{applicant.first_name}_#{applicant.id}")
          zipfile.remove("#{applicant.last_name}_#{applicant.first_name}_#{applicant.id}")
        end
        zipfile.mkdir("#{applicant.last_name}_#{applicant.first_name}_#{applicant.id}")  
      end  
      
      unless @ja_materials.nil?
        @ja_materials.each do |jam|
          unless jam.nil? || jam.attachments.nil?
            jam.attachments.each do |jama|
              ext_name = File.extname("#{RAILS_ROOT}/files/" + jama.disk_filename)
              new_file_name = "#{Applicant.find(JobApplication.find(jam.job_application_id).applicant_id).last_name}_#{Applicant.find(JobApplication.find(jam.job_application_id).applicant_id).first_name}_#{material_id_hash[jama.description]}_#{jam.job_application_id}#{ext_name}"
              orig_file_path = "#{RAILS_ROOT}/files/" + jama.disk_filename
              if File.exists?(orig_file_path)
                orig_file_name = File.basename(orig_file_path)
                if zipfile.find_entry(new_file_name)
                  zipfile.remove(new_file_name)
                end
                zipfile.get_output_stream("#{Applicant.find(JobApplication.find(jam.job_application_id).applicant_id).last_name}_#{Applicant.find(JobApplication.find(jam.job_application_id).applicant_id).first_name}_#{Applicant.find(JobApplication.find(jam.job_application_id).applicant_id).id}/" + new_file_name) do |f|
                  input = File.open(orig_file_path)
                  data_to_copy = input.read()
                  f.write(data_to_copy)
                end
              else
                puts "Warning: file #{orig_file_path} does not exist"
              end
            end  
          end    
        end
      end   
    
      unless @ja_referrals.nil?
        @ja_referrals.each do |jar|
          jar.each do |ref|
            ref.attachments.each do |jara|
              ext_name = File.extname("#{RAILS_ROOT}/files/" + jara.disk_filename)
              new_file_name = "#{Applicant.find(JobApplication.find(ref.job_application_id).applicant_id).last_name}_#{Applicant.find(JobApplication.find(ref.job_application_id).applicant_id).first_name}_Referral_#{ref.attachments.index(jara)+1}_#{ref.job_application_id}#{ext_name}"
              
              orig_file_path = "#{RAILS_ROOT}/files/" + jara.disk_filename
              if File.exists?(orig_file_path)
                orig_file_name = File.basename(orig_file_path)
                if zipfile.find_entry(new_file_name)
                  zipfile.remove(new_file_name)
                end
                zipfile.get_output_stream("#{Applicant.find(JobApplication.find(ref.job_application_id).applicant_id).last_name}_#{Applicant.find(JobApplication.find(ref.job_application_id).applicant_id).first_name}_#{Applicant.find(JobApplication.find(ref.job_application_id).applicant_id).id}/" + new_file_name) do |f|
                  input = File.open(orig_file_path)
                  data_to_copy = input.read()
                  f.write(data_to_copy)
                end
              else
                puts "Warning: file #{orig_file_path} does not exist"
              end
            end  
          end    
        end
      end
      
    end
    
    begin
      send_file @zip_file_path, :type => 'application/zip', :disposition => 'attachment', :stream => false
      File.delete(@zip_file_path)
    rescue  
      if File.file?(@zip_file_path)
        File.delete(@zip_file_path)
      end  
      puts "Error sending file"
    end
    
  end
  
  def zip_some
    if params[:commit] == "Bulk Change Status"
      unless params[:applicants_to_zip].nil?
        applications = Array.new
        params[:applicants_to_zip].each do |ja|
          applications << JobApplication.find(ja)
        end
        applications.each do |app|
          if !params[:submission_status].blank?
            app.submission_status = params[:submission_status]
          end  
          if !params[:review_status].blank?
            app.review_status = params[:review_status]
          end  
          if !params[:offer_status].blank?
            app.offer_status = params[:offer_status]
          end 
          app.save!     
        end
        flash[:notice] = "Applications successfully updated!"
        redirect_to :back
      else
        flash[:notice] = "You did not select any applications."
        redirect_to :back  
      end
    else 
      @job = Job.find(params[:job])
      unless User.current.admin? || @job.is_manager?
        flash[:error] = "You are not authorized to view this section."
    		redirect_to('/') and return
    	end
      @material_types = params[:application_material_types]
      @file_name = @job.title.gsub(/[^a-zA-Z\d]/, '-')
      @zip_file_path = "#{RAILS_ROOT}/tmp/#{@file_name}-materials.zip"
      filepaths = Array.new
      counter = 1
      material_id_hash = Hash.new
      @ja_materials = Array.new
      if params[:applicant_referral]
        @ja_referrals = Array.new
      end
      applicants = Array.new
      unless params[:applicants_to_zip].nil?
        params[:applicants_to_zip].each do |ja|
          applicants << JobApplication.find(ja).applicant.id
        end
      end
      @applications = JobApplication.find(:all, :conditions => ["job_id = ? and applicant_id in (?)", @job.id, applicants])
    
      @applications.each do |app|
        @ja_materials << JobApplicationMaterial.find(:first, :conditions => {:job_application_id => app.id})
        unless @ja_referrals.nil?
          @ja_referrals << JobApplicationReferral.find(:all, :conditions => {:job_application_id => app.id})
        end  
      end  
    
      unless @ja_referrals.nil?
        if @material_types.include?("Proposed Work")
          @material_types.insert(@material_types.index("Proposed Work") + 1, "Referral")
        elsif @material_types.include?("Cover Letter")
          @material_types.insert(@material_types.index("Cover Letter") + 1, "Referral")
        elsif @material_types.include?("Resume or CV")
          @material_types.insert(@material_types.index("Resume or CV") + 1, "Referral")
        else 
          @material_types.insert(@material_types.index("Resume or CV") + 1, "Referral")
        end  
      end
      
      @material_types.each do |material|
        material_id_hash[material] = "%03d" % counter.to_s + "_" + material.gsub(/ /, '_')
        counter = counter + 1
      end
    
      Zip::ZipFile.open(@zip_file_path, Zip::ZipFile::CREATE) do |zipfile|
        unless @ja_materials.nil?
          @ja_materials.each do |jam|
            unless jam.nil? || jam.attachments.nil?
              jam.attachments.each do |jama|
                @material_types.each do |mt|
                  if mt == jama.description
                    ext_name = File.extname("#{RAILS_ROOT}/files/" + jama.disk_filename)
                    new_file_name = "#{Applicant.find(JobApplication.find(jam.job_application_id).applicant_id).last_name}_#{Applicant.find(JobApplication.find(jam.job_application_id).applicant_id).first_name}_#{material_id_hash[jama.description]}_#{jam.job_application_id}#{ext_name}"
                    orig_file_path = "#{RAILS_ROOT}/files/" + jama.disk_filename
                    if File.exists?(orig_file_path)
                      orig_file_name = File.basename(orig_file_path)
                      if zipfile.find_entry(new_file_name)
                        zipfile.remove(new_file_name)
                      end
                      zipfile.get_output_stream(new_file_name) do |f|
                        input = File.open(orig_file_path)
                        data_to_copy = input.read()
                        f.write(data_to_copy)
                      end
                    else
                      puts "Warning: file #{file_path} does not exist"
                    end
                  end  
                end  
              end
            end    
          end 
        end  

        unless @ja_referrals.nil?
          @ja_referrals.each do |jar|
            jar.each do |ref|
              ref.attachments.each do |jara|
                ext_name = File.extname("#{RAILS_ROOT}/files/" + jara.disk_filename)
                new_file_name = "#{Applicant.find(JobApplication.find(ref.job_application_id).applicant_id).last_name}_#{Applicant.find(JobApplication.find(ref.job_application_id).applicant_id).first_name}_Referral_#{ref.attachments.index(jara)+1}_#{ref.job_application_id}#{ext_name}"
              
                orig_file_path = "#{RAILS_ROOT}/files/" + jara.disk_filename
                if File.exists?(orig_file_path)
                  orig_file_name = File.basename(orig_file_path)
                  if zipfile.find_entry(new_file_name)
                    zipfile.remove(new_file_name)
                  end
                  zipfile.get_output_stream(new_file_name) do |f|
                    input = File.open(orig_file_path)
                    data_to_copy = input.read()
                    f.write(data_to_copy)
                  end
                else
                  puts "Warning: file #{file_path} does not exist"
                end
              end  
            end    
          end
        end
      end
    
      begin
        send_file @zip_file_path, :type => 'application/zip', :disposition => 'attachment', :stream => false
        File.delete(@zip_file_path)
      rescue  
        if File.file?(@zip_file_path)
          File.delete(@zip_file_path)
        end  
        puts "Error sending file"
      end
    end  
  end  
  
  
  
  def register
    redirect_to(home_url) && return unless Setting.self_registration? || session[:auth_source_registration]
    if request.post?
      @user = User.new(params[:user])
      @user.admin = false
      @user.register
      
      @user.login = params[:user][:login]
      @user.password, @user.password_confirmation = params[:password], params[:password_confirmation]
      # Automatic activation
      @user.activate
      @user.last_login_on = Time.now
      if @user.save
        self.logged_user = @user
        flash[:notice] = "Your account has been created. You are now logged in."
      else
        flash[:error] = ""
        @user.errors.full_messages.each do |msg|
          flash[:error] += " " + msg
        end 
      end
      redirect_to :back
    else
      redirect_to(home_url)    
    end  
  end
  
  
  def export_to_csv
    @job = Job.find(params[:job_id])
    unless User.current.admin? || @job.is_manager?
      flash[:error] = "You are not authorized to view this section."
  		redirect_to('/') and return
  	end
    @applicants = @job.applicants
    @job_applications = @job.job_applications
    @file_name = @job.title.gsub(/ /, '-').gsub(/,/, '-')
    
    @job_application_custom_fields = @job.all_job_app_custom_fields
    @applicant_fields = Applicant.column_names - ["id", "created_at", "updated_at"]
    @referral_fields = JobApplicationReferral.column_names - ["id", "job_application_id", "created_at", "updated_at"]
    @custom = []
    unless @job_application_custom_fields.empty?
  		@job_application_custom_fields.each do |custom_field|
  		  @custom << custom_field.name
  		end
  	end
  	@referral_fields_cols = (@referral_fields.collect {|x| "Referral " + x } + ["Referral Doc"]) * @job.referrer_count.to_i
  	@statuses = ["submission_status","review_status","offer_status"]
  	
  	unless @job.application_material_types.nil? || @job.application_material_types.empty?
		  @materials = @job.application_material_types.split(',')  
		end
  	@columns = @applicant_fields.collect {|x| "Applicant " + x } + @custom + @referral_fields_cols + @statuses + @materials + ["Additional Materials"]
    
    csv_string = FasterCSV.generate do |csv| 
      # header row 
      csv << @columns

      # data rows 
      @job_applications.each do |ja|
        row = []
        @applicant_fields.each do |af|
          row << ja.applicant.send(af)
        end
        @custom.each do |c| 
          if ja.submission_status == "Not Submitted"
    		    row << "" 
    			else
            ja.custom_values.each do |cv|
              if cv.custom_field.name == c
                if show_value(cv).blank?
      		        row << ""  
      				  else
      				    row << show_value(cv)
      				  end
              end  
            end
          end  
        end
        referrals = ja.job_application_referrals.find :all, :include => [:attachments]
        if referrals.empty?
    		  @referral_fields_cols.each do |rfc|
    			  row << ""
        	end
    		else
          referrals.each do |r|
            material = Attachment.find(:all, :conditions => {:container_id => r.id, :container_type => "JobApplicationReferral"})
            @referral_fields.each do |rf|  
              row << r.send(rf)
            end 
            unless material.nil? || material.empty?
              material.each do |m|
  			        row << url_for(:controller => 'attachments', :action => 'show', :id => m.id)
  			      end
  			    else
  			      row << ""
  			    end    
          end
        end
  		  if referrals.length < @job.referrer_count.to_i
  		    leftover =  @job.referrer_count.to_i - referrals.length
    	    i = 0
  			  until i == leftover  do
  			    @referral_fields.each do |rf|
  		        row << ""
            end
  		      row << ""
  			    i += 1
  			  end  
        end  
        @statuses.each do |s|
          row << ja.send(s)
        end
        @job_application_materials = ja.job_application_materials.find :all, :include => [:attachments]
        unless @job_application_materials.nil? || @job_application_materials.blank?
    	    @materials.each do |amt|
    			  @job_application_materials.each do |jam|
      			  material = Attachment.find(:all, :conditions => {:container_id => jam.id, :description => amt})
      			  unless material.nil? || material.empty?
      			    material.each do |m|
      			      row << url_for(:controller => 'attachments', :action => 'show', :id => m.id)
      			    end 
      			  else
      			    row << ""
      			  end   
    		    end
    			end
    			@job_application_materials.each do |jam|
    			  material = Attachment.find(:all, :conditions => ["container_id = ? and description LIKE 'Additional:%'", jam.id])
    			  additional = ""
    			  unless material.nil? || material.empty?
    			    material.each do |m|
    			      additional += url_for(:controller => 'attachments', :action => 'show', :id => m.id) + ", "
    			    end
    			    row << additional
    			  else
    			    row << ""
    			  end
    			end
    		end
        csv << row
      end 
    end 

    # send it to the browser
    send_data csv_string, 
            :type => 'text/html; charset=iso-8859-1; header=present', 
            :disposition => "attachment; filename=#{@file_name}-applicants.csv"
  end
  
  def filter
    p "JOB ID"
    p params[:job_id]
    @job = Job.find(params[:job_id])
    @apptracker = Apptracker.find(params[:apptracker_id])
    unless User.current.admin? || @job.is_manager?
      flash[:error] = "You are not authorized to view this section."
  		redirect_to('/') and return
  	end
  	
  	@job_application = JobApplication.new(:job => @job)
    @job_application_custom_fields = @job.all_job_app_custom_fields
    @applicant_fields = Applicant.column_names - ["id", "created_at", "updated_at"]
    @referral_fields = JobApplicationReferral.column_names - ["id", "job_application_id", "created_at", "updated_at"]
    @custom = []
    unless @job_application_custom_fields.empty?
  		@job_application_custom_fields.each do |custom_field|
  		  @custom << custom_field.name
  		end
  	end
  	@referral_fields_cols = (@referral_fields.collect {|x| "Referral " + x } + ["Referral Doc"]) * @job.referrer_count.to_i
  	@statuses = ["submission_status","review_status","offer_status"]
  	@columns = @applicant_fields.collect {|x| "Applicant " + x } + @custom + @referral_fields_cols + @statuses
    @job_applications = []
    @applicants = []
    
    unless params[:filter].nil?
      @custom_fields = params[:filter][:custom_field_values]
      @custom_values = []
      # how many custom fields are we searching on
      value_count = 0
      @custom_fields.each_key do |field_id|
        unless @custom_fields[field_id].nil? || @custom_fields[field_id].empty?
          value_count = value_count + 1
          @custom_values += CustomValue.find(:all, :conditions => ["custom_field_id = ? and value ILIKE ?", field_id, "%#{@custom_fields[field_id]}%"])
        end  
      end
      job_app_ids = @custom_values.collect {|x| x.customized_id}
      
      # kick out job ids that do not fulfill all custom fields being searched on
      counts = Hash.new(0)
      job_app_ids.each { |app_id| counts[app_id] += 1 }
      job_app_ids.uniq!
      counts.each_key do |app_id|
        if counts[app_id] != value_count
          job_app_ids.delete(app_id)
        end  
      end 
      @job_applications = JobApplication.find(:all, :conditions => ["job_id = ? and id in (?)", params[:job_id], job_app_ids])
    end  
    unless params[:submission_status].blank?
  	  @job_applications << JobApplication.find(:all, :conditions => {:job_id => params[:job_id], :submission_status => params[:submission_status]})
  	end
  	unless params[:review_status].blank?
  	  @job_applications << JobApplication.find(:all, :conditions => {:job_id => params[:job_id], :review_status => params[:review_status]})
  	end 
  	unless params[:offer_status].blank?
  	  @job_applications << JobApplication.find(:all, :conditions => {:job_id => params[:job_id], :offer_status => params[:offer_status]})
  	end 
  	@applicant_fields.each do |af|
  	  unless params["#{af}"].blank?
  	    @applicants = Applicant.find(:all, :conditions => ["#{af} ILIKE ?", "%#{params["#{af}"]}%"])
  	    @applicants.each do |a|
  	      @job_applications << JobApplication.find(:all, :conditions => {:job_id => params[:job_id], :applicant_id => a.id})
  	    end  
  	  end  
  	end  
  	@job_applications.flatten!
  	@job_applications.uniq! 
  end
  
  def zip_filtered
    @job = Job.find(params[:job_id])
    unless User.current.admin? || @job.is_manager?
      flash[:error] = "You are not authorized to view this section."
  		redirect_to('/') and return
  	end
  	
  	@job_applications = JobApplication.find(:all, :conditions => ["id in (?)", params[:job_applications]])
  	
    # create zip file of filtered results
    @material_types = @job.application_material_types.split(',')
    @file_name = @job.title.gsub(/[^a-zA-Z\d]/, '-')
    @zip_file_path = "#{RAILS_ROOT}/tmp/#{@file_name}-filtered-materials.zip"
    @ja_materials = Array.new
    @ja_referrals = Array.new
    filepaths = Array.new
    counter = 1
    material_id_hash = Hash.new
    
    applicant_ids = @job_applications.collect {|ja| ja.applicant_id }
    @applicants = Applicant.find(:all, :conditions => ["id in (?)", applicant_ids])
    @applications = JobApplication.find(:all, :conditions => {:job_id => @job.id})

    @job_applications.each do |app|
      @ja_materials << JobApplicationMaterial.find(:first, :conditions => {:job_application_id => app.id})
      unless @ja_referrals.nil?
        @ja_referrals << JobApplicationReferral.find(:all, :conditions => {:job_application_id => app.id})
      end  
    end  

    unless @ja_referrals.nil?
      if @material_types.include?("Proposed Work")
        @material_types.insert(@material_types.index("Proposed Work") + 1, "Referral")
      elsif @material_types.include?("Cover Letter")
        @material_types.insert(@material_types.index("Cover Letter") + 1, "Referral")
      elsif @material_types.include?("Resume or CV")
        @material_types.insert(@material_types.index("Resume or CV") + 1, "Referral")
      else 
        @material_types.insert(@material_types.index("Resume or CV") + 1, "Referral")
      end  
    end

    @material_types.each do |material|
      material_id_hash[material] = "%03d" % counter.to_s + "_" + material.gsub(/ /, '_')
      counter = counter + 1
    end

    Zip::ZipFile.open(@zip_file_path, Zip::ZipFile::CREATE) do |zipfile|
      @applicants.each do |applicant|
        if zipfile.find_entry("#{applicant.last_name}_#{applicant.first_name}_#{applicant.id}")
          zipfile.remove("#{applicant.last_name}_#{applicant.first_name}_#{applicant.id}")
        end
        zipfile.mkdir("#{applicant.last_name}_#{applicant.first_name}_#{applicant.id}")  
      end  

      unless @ja_materials.nil?
        @ja_materials.each do |jam|
          unless jam.nil? || jam.attachments.nil?
            jam.attachments.each do |jama|
              ext_name = File.extname("#{RAILS_ROOT}/files/" + jama.disk_filename)
              new_file_name = "#{Applicant.find(JobApplication.find(jam.job_application_id).applicant_id).last_name}_#{Applicant.find(JobApplication.find(jam.job_application_id).applicant_id).first_name}_#{material_id_hash[jama.description]}_#{jam.job_application_id}#{ext_name}"
              orig_file_path = "#{RAILS_ROOT}/files/" + jama.disk_filename
              if File.exists?(orig_file_path)
                orig_file_name = File.basename(orig_file_path)
                if zipfile.find_entry(new_file_name)
                  zipfile.remove(new_file_name)
                end
                zipfile.get_output_stream("#{Applicant.find(JobApplication.find(jam.job_application_id).applicant_id).last_name}_#{Applicant.find(JobApplication.find(jam.job_application_id).applicant_id).first_name}_#{Applicant.find(JobApplication.find(jam.job_application_id).applicant_id).id}/" + new_file_name) do |f|
                  input = File.open(orig_file_path)
                  data_to_copy = input.read()
                  f.write(data_to_copy)
                end
              else
                puts "Warning: file #{orig_file_path} does not exist"
              end
            end  
          end    
        end
      end   

      unless @ja_referrals.nil?
        @ja_referrals.each do |jar|
          jar.each do |ref|
            ref.attachments.each do |jara|
              ext_name = File.extname("#{RAILS_ROOT}/files/" + jara.disk_filename)
              new_file_name = "#{Applicant.find(JobApplication.find(ref.job_application_id).applicant_id).last_name}_#{Applicant.find(JobApplication.find(ref.job_application_id).applicant_id).first_name}_Referral_#{ref.attachments.index(jara)+1}_#{ref.job_application_id}#{ext_name}"

              orig_file_path = "#{RAILS_ROOT}/files/" + jara.disk_filename
              if File.exists?(orig_file_path)
                orig_file_name = File.basename(orig_file_path)
                if zipfile.find_entry(new_file_name)
                  zipfile.remove(new_file_name)
                end
                zipfile.get_output_stream("#{Applicant.find(JobApplication.find(ref.job_application_id).applicant_id).last_name}_#{Applicant.find(JobApplication.find(ref.job_application_id).applicant_id).first_name}_#{Applicant.find(JobApplication.find(ref.job_application_id).applicant_id).id}/" + new_file_name) do |f|
                  input = File.open(orig_file_path)
                  data_to_copy = input.read()
                  f.write(data_to_copy)
                end
              else
                puts "Warning: file #{orig_file_path} does not exist"
              end
            end  
          end    
        end
      end

    end

    begin
      send_file @zip_file_path, :type => 'application/zip', :disposition => 'attachment', :stream => false
      File.delete(@zip_file_path)
    rescue  
      if File.file?(@zip_file_path)
        File.delete(@zip_file_path)
      end  
      puts "Error sending file"
    end
  end 
  
  def zip_filtered_single
    @job = Job.find(params[:job_id])
    unless User.current.admin? || @job.is_manager?
      flash[:error] = "You are not authorized to view this section."
  		redirect_to('/') and return
  	end
  	
  	@job_applications = JobApplication.find(:all, :conditions => ["id in (?)", params[:job_applications]])
  	
    # create zip file of filtered results
    @material_types = @job.application_material_types.split(',')
    @file_name = @job.title.gsub(/[^a-zA-Z\d]/, '-')
    @zip_file_path = "#{RAILS_ROOT}/tmp/#{@file_name}-filtered-materials.zip"
    @ja_materials = Array.new
    @ja_referrals = Array.new
    filepaths = Array.new
    counter = 1
    material_id_hash = Hash.new

    @applications = JobApplication.find(:all, :conditions => {:job_id => @job.id})

    @job_applications.each do |app|
      @ja_materials << JobApplicationMaterial.find(:first, :conditions => {:job_application_id => app.id})
      unless @ja_referrals.nil?
        @ja_referrals << JobApplicationReferral.find(:all, :conditions => {:job_application_id => app.id})
      end  
    end  

    unless @ja_referrals.nil?
      if @material_types.include?("Proposed Work")
        @material_types.insert(@material_types.index("Proposed Work") + 1, "Referral")
      elsif @material_types.include?("Cover Letter")
        @material_types.insert(@material_types.index("Cover Letter") + 1, "Referral")
      elsif @material_types.include?("Resume or CV")
        @material_types.insert(@material_types.index("Resume or CV") + 1, "Referral")
      else 
        @material_types.insert(@material_types.index("Resume or CV") + 1, "Referral")
      end  
    end

    @material_types.each do |material|
      material_id_hash[material] = "%03d" % counter.to_s + "_" + material.gsub(/ /, '_')
      counter = counter + 1
    end

    Zip::ZipFile.open(@zip_file_path, Zip::ZipFile::CREATE) do |zipfile|

      unless @ja_materials.nil?
        @ja_materials.each do |jam|
          unless jam.nil? || jam.attachments.nil?
          jam.attachments.each do |jama|
            ext_name = File.extname("#{RAILS_ROOT}/files/" + jama.disk_filename)
            new_file_name = "#{Applicant.find(JobApplication.find(jam.job_application_id).applicant_id).last_name}_#{Applicant.find(JobApplication.find(jam.job_application_id).applicant_id).first_name}_#{material_id_hash[jama.description]}_#{jam.job_application_id}#{ext_name}"
            orig_file_path = "#{RAILS_ROOT}/files/" + jama.disk_filename
            if File.exists?(orig_file_path)
              orig_file_name = File.basename(orig_file_path)
              if zipfile.find_entry(new_file_name)
                zipfile.remove(new_file_name)
              end
              zipfile.get_output_stream(new_file_name) do |f|
                input = File.open(orig_file_path)
                data_to_copy = input.read()
                f.write(data_to_copy)
              end
            else
              puts "Warning: file #{orig_file_path} does not exist"
            end
          end
          end    
        end
      end   

      unless @ja_referrals.nil?
        @ja_referrals.each do |jar|
          jar.each do |ref|
            ref.attachments.each do |jara|
              ext_name = File.extname("#{RAILS_ROOT}/files/" + jara.disk_filename)
              new_file_name = "#{Applicant.find(JobApplication.find(ref.job_application_id).applicant_id).last_name}_#{Applicant.find(JobApplication.find(ref.job_application_id).applicant_id).first_name}_Referral_#{ref.attachments.index(jara)+1}_#{ref.job_application_id}#{ext_name}"

              orig_file_path = "#{RAILS_ROOT}/files/" + jara.disk_filename
              if File.exists?(orig_file_path)
                orig_file_name = File.basename(orig_file_path)
                if zipfile.find_entry(new_file_name)
                  zipfile.remove(new_file_name)
                end
                zipfile.get_output_stream(new_file_name) do |f|
                  input = File.open(orig_file_path)
                  data_to_copy = input.read()
                  f.write(data_to_copy)
                end
              else
                puts "Warning: file #{orig_file_path} does not exist"
              end
            end  
          end    
        end
      end

    end
    begin
      send_file @zip_file_path, :type => 'application/zip', :disposition => 'attachment', :stream => false
      File.delete(@zip_file_path)
    rescue  
      if File.file?(@zip_file_path)
        File.delete(@zip_file_path)
      end  
      puts "Error sending file"
    end  
  end 
  
  def export_filtered_to_csv
    @job = Job.find(params[:job_id])
    unless User.current.admin? || @job.is_manager?
      flash[:error] = "You are not authorized to view this section."
  		redirect_to('/') and return
  	end
  	@job_applications = JobApplication.find(:all, :conditions => ["id in (?)", params[:job_app_ids]])
  	
    @file_name = @job.title.gsub(/ /, '-').gsub(/,/, '-')
    
    @job_application_custom_fields = @job.all_job_app_custom_fields
    @applicant_fields = Applicant.column_names - ["id", "created_at", "updated_at"]
    @referral_fields = JobApplicationReferral.column_names - ["id", "job_application_id", "created_at", "updated_at"]
    @custom = []
    unless @job_application_custom_fields.empty?
  		@job_application_custom_fields.each do |custom_field|
  		  @custom << custom_field.name
  		end
  	end
  	@referral_fields_cols = (@referral_fields.collect {|x| "Referral " + x } + ["Referral Doc"]) * @job.referrer_count.to_i
  	@statuses = ["submission_status","review_status","offer_status"]
  	unless @job.application_material_types.nil? || @job.application_material_types.empty?
		  @materials = @job.application_material_types.split(',')  
		end
  	@columns = @applicant_fields.collect {|x| "Applicant " + x } + @custom + @referral_fields_cols + @statuses + @materials + ["Additional Materials"]
    
    csv_string = FasterCSV.generate do |csv| 
      # header row 
      csv << @columns

      # data rows 
      @job_applications.each do |ja|
        row = []
        @applicant_fields.each do |af|
          row << ja.applicant.send(af)
        end
        @custom.each do |c| 
          if ja.submission_status == "Not Submitted"
    		    row << "" 
    			else
            ja.custom_values.each do |cv|
              if cv.custom_field.name == c
                if show_value(cv).blank?
      		        row << ""  
      				  else
      				    row << show_value(cv)
      				  end
              end  
            end
          end  
        end
        referrals = ja.job_application_referrals.find :all, :include => [:attachments]
        if referrals.empty?
    		  @referral_fields_cols.each do |rfc|
    			  row << ""
        	end
    		else
          referrals.each do |r|
            material = Attachment.find(:all, :conditions => {:container_id => r.id, :container_type => "JobApplicationReferral"})
            @referral_fields.each do |rf|  
              row << r.send(rf)
            end 
            unless material.nil? || material.empty?
              material.each do |m|
  			        row << url_for(:controller => 'attachments', :action => 'show', :id => m.id)
  			      end
  			    else
  			      row << ""
  			    end    
          end
        end
  		  if referrals.length < @job.referrer_count.to_i
  		    leftover =  @job.referrer_count.to_i - referrals.length
    	    i = 0
  			  until i == leftover  do
  			    @referral_fields.each do |rf|
  		        row << ""
            end
  		      row << ""
  			    i += 1
  			  end  
        end
        @statuses.each do |s|
          row << ja.send(s)
        end
        @job_application_materials = ja.job_application_materials.find :all, :include => [:attachments]
        unless @job_application_materials.nil? || @job_application_materials.blank?
    	    @materials.each do |amt|
    			  @job_application_materials.each do |jam|
      			  material = Attachment.find(:all, :conditions => {:container_id => jam.id, :description => amt})
      			  unless material.nil? || material.empty?
      			    material.each do |m|
      			      row << url_for(:controller => 'attachments', :action => 'show', :id => m.id)
      			    end 
      			  else
      			    row << ""
      			  end   
    		    end
    			end
    			@job_application_materials.each do |jam|
    			  material = Attachment.find(:all, :conditions => ["container_id = ? and description LIKE 'Additional:%'", jam.id])
    			  additional = ""
    			  unless material.nil? || material.empty?
    			    material.each do |m|
    			      additional += url_for(:controller => 'attachments', :action => 'show', :id => m.id) + ", "
    			    end
    			    row << additional
    			  else
    			    row << ""
    			  end
    			end
    		end
        csv << row
      end 
    end 

    # send it to the browser
    send_data csv_string, 
            :type => 'text/html; charset=iso-8859-1; header=present', 
            :disposition => "attachment; filename=#{@file_name}-applicant-status.csv"
  end 
  
  def filter_bulk_status
    if params[:commit] == "Bulk Change Status"
      @job = Job.find(params[:job_id].to_i)
      @apptracker_id = @job.apptracker.id
      unless params[:applicants_to_zip].nil?
        applications = Array.new
        params[:applicants_to_zip].each do |ja|
          applications << JobApplication.find(ja)
        end
        applications.each do |app|
          if !params[:submission_status].blank?
            app.submission_status = params[:submission_status]
          end  
          if !params[:review_status].blank?
            app.review_status = params[:review_status]
          end  
          if !params[:offer_status].blank?
            app.offer_status = params[:offer_status]
          end 
          app.save!     
        end
        flash[:notice] = "Applications successfully updated!"
        redirect_to(filter_jobs_path(:job_id => @job.id, :apptracker_id => @apptracker_id))
      else
        flash[:notice] = "You did not select any applications."
        redirect_to(filter_jobs_path(:job_id => @job.id, :apptracker_id => @apptracker_id))
      end
    end
  end   
end

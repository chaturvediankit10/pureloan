require 'open-uri'
require "google_drive"
require 'roo'
require 'roo-xls'

# Please follow https://github.com/gimite/google-drive-ruby/blob/master/doc/authorization.md
namespace :sheet_operation do
  desc "export sheet and import sheet"
  #setup drive access
  drive          = GoogleDrive::Session.from_config("config.json")
  directory      = drive.folder_by_id("1i9QZ93LHuFnqOft_-GBmjHuIlGRGPNGl")
  current_date   = Date.today.strftime("%Y%m%d")
  folder_exist   = false
  today_download = current_date + " download"
  today_uploaded = current_date + " uploaded"
  is_downloaded  = $redis.get(today_download)
  is_uploaded    = $redis.get(today_uploaded)
  # check folder exists or not
  directory.subcollections.each do |folder|
    folder_exist = true if folder.title.eql?(current_date)
  end

  # current date folder will be create once on a day
  unless folder_exist
    folder = directory.create_subcollection(current_date)
  else
    folder = directory.subcollections.select{|f| f.title.eql?(current_date)}.first
  end

  task :export_sheet => :environment do
    unless is_downloaded.present?
      # make new folder for remote files
      directory_name = "remote_files"
      Dir.mkdir(directory_name) unless File.exists?(directory_name)
      # get all sheet links
      sheet_links = Bank::SHEET_LINKS
      # traverse each link one by one and download file inside folder
      sheet_links.each do |link|
				# if link == "https://www.loansifter.com/DownloadFile.aspx?RateSheetID=8570"
        open(link) do |remote_file|
          file_name = remote_file.meta["content-disposition"].gsub("attachment;filename=", "")
          # unless File.exists?(Rails.root.join('remote_files', file_name))
            File.open("remote_files/" + file_name, "wb") do |local_file|
              # save file
              local_file.write(remote_file.read)
              # file name
              filename = local_file.to_path.split("/")[-1]
              # call rake task to upload data on database
              Rake::Task["sheet_operation:import_sheet_data"].invoke(filename)
            end
          # end
        end
        # end
      end

      # set validation to download files from remote
      $redis.set(today_download, "done")
      # call rake task to upload sheets on google drive
      # Rake::Task["sheet_operation:upload_on_drive"].invoke
    end
  end

  task :upload_on_drive => :environment do
    unless is_uploaded.present?
      # get all files of specified folder
      folder_files = Dir.entries("remote_files")
      folder_files.each do  |file|
        if file.split(".").last.present?
          # collect file from folder and upload on drive
          folder.upload_from_file("remote_files/#{file}", file, convert: false)
        end
      end

      $redis.set(today_uploaded, "done")
    end
  end

  task :import_sheet_data, [:filename] => :environment do |task, args|
	  # begin
	    # collect file
	    file   = File.join(Rails.root.join('remote_files', args[:filename]))
	    # open file
	    xlsx   = Roo::Spreadsheet.open(neeraj)
	    # change file name in camel case
	    class_name = args[:filename].split(".").first.camelize + "Controller"
	    #  get sheets names of file
	    sheets = xlsx.sheets
	    sheets.each do |sheet|
				# get sheet from data
	      ControllerMethodCallingService.new(class_name, sheet).invoke_method
	    end
	  # rescue Exception => e
	  # 	log = ErrorLog.new(details: e.backtrace[0])
	  # end
  end

  # ErrorLog.new(details: e.backtrace_locations[0]
end
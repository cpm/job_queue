#!/usr/bin/env ruby

require 'rubygems'
require File.dirname(__FILE__) + '/../config/environment'
require 'daemons'

#Dir.glob( File.dirname(__FILE__) + '/../lib/job_queue/*'   ).each {|file| require file; }
#Dir.glob( File.dirname(__FILE__) + '/../lib/job_workers/*' ).each {|file| require file }

puts "Loaded environment, port:#{JobQueue::Config.port}"
Daemons.run_proc('job_queued.rb') do
  JobQueue::JobServer.new.listen(JobQueue::Config.port)
end

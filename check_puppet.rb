#!/usr/bin/ruby1.8

# A simple nagios check that should be run as root
# perhaps under the mcollective NRPE plugin and
# can check when the last run was done of puppet.
# It can also check fail counts and skip machines
# that are not enabled
#
# The script will use the puppet last_run-summar.yaml
# file to determine when last Puppet ran else the age
# of the statefile.

require 'optparse'
require 'yaml'

lockfile = "/var/lib/puppet/state/puppetdlock"
statefile = "/var/lib/puppet/state/state.yaml"
summaryfile = "/var/lib/puppet/state/last_run_summary.yaml"
enabled = true
running = false
lastrun_failed = false
lastrun = 0
failcount = 0
warn = 0
crit = 0
enabled_only = false
failures = false

opt = OptionParser.new

opt.on("--critical [CRIT]", "-c", Integer, "Critical threshold, time or failed resources") do |f|
    crit = f.to_i
end

opt.on("--warn [WARN]", "-w", Integer, "Warning thresold, time of failed resources") do |f|
    warn = f.to_i
end

opt.on("--check-failures", "-f", "Check for failed resources instead of time since run") do |f|
    failures = true
end

opt.on("--only-enabled", "-e", "Only alert if Puppet is enabled") do |f|
    enabled_only = true
end

opt.on("--lock-file [FILE]", "-l", "Location of the lock file, default #{lockfile}") do |f|
    lockfile = f
end

opt.on("--state-file [FILE]", "-t", "Location of the state file, default #{statefile}") do |f|
    statefile = f
end

opt.on("--summary-file [FILE]", "-s", "Location of the summary file, default #{summaryfile}") do |f|
    summaryfile = f
end

opt.parse!

if warn == 0 || crit == 0
    puts "Please specify a warning and critical level"
    exit 3
end

if File.exists?(lockfile)
    if File::Stat.new(lockfile).zero?
       enabled = false
    else
       running = true
    end
end

lastrun = File.stat(statefile).mtime.to_i if File.exists?(statefile)

if File.exists?(summaryfile)
    begin
        summary = YAML.load_file(summaryfile)
        lastrun = summary["time"]["last_run"]

        # machines that outright failed to run like on missing dependencies
        # are treated as huge failures.  The yaml file will be valid but
        # it wont have anything but last_run in it
        unless summary.include?("events")
            failcount = 99
        else
            # and unless there are failures, the events hash just wont have the failure count
            eventsfail = summary["events"]["failure"] || 0
            resourcesfail = summary["resources"]["failed"] || 0
            failcount = eventsfail + resourcesfail
        end
    rescue
        failcount = 0
        summary = nil
    end
end

time_since_last_run = Time.now.to_i - lastrun

unless failures
    if enabled_only && enabled == false
        puts "OK: Puppet is currently disabled, not alerting.  Last run #{time_since_last_run} seconds ago with #{failcount} failures"
        exit 0
    end

    if time_since_last_run >= crit
        puts "CRITICAL: Puppet last ran #{time_since_last_run} seconds ago, expected < #{crit}"
        exit 2

    elsif time_since_last_run >= warn
        puts "WARNING: Puppet last ran #{time_since_last_run} seconds ago, expected < #{warn}"
        exit 1

    else
        if enabled
            puts "OK: Puppet is currently enabled, last run #{time_since_last_run} seconds ago with #{failcount} failures"
        else
            puts "OK: Puppet is currently disabled, last run #{time_since_last_run} seconds ago with #{failcount} failures"
        end

        exit 0
    end
else
    if enabled_only && enabled == false
        puts "OK: Puppet is currently disabled, not alerting.  Last run #{time_since_last_run} seconds ago with #{failcount} failures"
        exit 0
    end

    if failcount >= crit
        puts "CRITICAL: Puppet last ran had #{failcount} failures, expected < #{crit}"
        exit 2

    elsif failcount >= warn
        puts "WARNING: Puppet last ran had #{failcount} failures, expected < #{warn}"
        exit 1

    else
        if enabled
            puts "OK: Puppet is currently enabled, last run #{time_since_last_run} seconds ago with #{failcount} failures"
        else
            puts "OK: Puppet is currently disabled, last run #{time_since_last_run} seconds ago with #{failcount} failures"
        end

        exit 0
    end
end

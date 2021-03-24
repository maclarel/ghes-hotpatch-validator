# Grab and validate command line arg for version
def validate_args(arg)
    ( puts "Please provide a version, e.g. ghe-check-hotpatch.sh 2.17.15"; exit ) if ARGV.length < 1 || ARGV.length > 1 || arg < 3
    @PATCH_VERSION = ARGV[0]
end

# Parse the log looking for errors, warn if any are found
def check_log_for_errors(log)
    errors_in_log = Array.new
    hotpatch_log=File.open(log).read
    hotpatch_log.each_line do |line|
        errors_in_log.push(line) if line.match?("ERROR")
    end
    errors_in_log.length.zero? ? (puts "No errors detected in the hotpatch log.") : (puts "WARNING: #{errors_in_log.length} errors detected during hotpatching."; @FAILURE_STATUS=1)
end

# Verify that hotpatching completed
def hotpatch_completion_check(log)
    hotpatch_log=File.open(log).to_a
    hotpatch_log.last.match("is now patched") ? (puts "Logs showing that upgrade completed. Last line: #{hotpatch_log.last}") : (puts "ERROR: Upgrade did not fully complete!"; exit)
end

# TO DO:
# cluster.conf sanity check/mode selection
# log existence sanity check
# API Version comparison
# Docker image tag comparison (3.x)
# Symlink check (2.x)
# Running hash check (2.x)

# Do stuff
validate_args(ARGV[0].to_f)
check_log_for_errors("test/hotpatch.log")
hotpatch_completion_check("test/hotpatch.log")

# Give a final report on status of the upgrade
@FAILURE_STATUS.nil? ? (puts "Ugprade to #{@PATCH_VERSION} appears to have completed successfully!") : (puts "WARNING: Upgrade to #{@PATCH_VERSION} appears to have completed successfully, however the log output should be reviewed.")
require 'benchmark'
require 'reportgenerator_reportinator'
require 'gcovr_reportinator'

directory(GCOV_BUILD_OUTPUT_PATH)
directory(GCOV_RESULTS_PATH)
directory(GCOV_ARTIFACTS_PATH)
directory(GCOV_DEPENDENCIES_PATH)

CLEAN.include(File.join(GCOV_BUILD_OUTPUT_PATH, '*'))
CLEAN.include(File.join(GCOV_RESULTS_PATH, '*'))
CLEAN.include(File.join(GCOV_ARTIFACTS_PATH, '*'))
CLEAN.include(File.join(GCOV_DEPENDENCIES_PATH, '*'))

CLOBBER.include(File.join(GCOV_BUILD_PATH, '**/*'))

rule(/#{GCOV_BUILD_OUTPUT_PATH}\/#{'.+\\' + EXTENSION_OBJECT}$/ => [
       proc do |task_name|
         @ceedling[:file_finder].find_compilation_input_file(task_name)
       end
     ]) do |object|

  if File.basename(object.source) =~ /^(#{PROJECT_TEST_FILE_PREFIX}|#{CMOCK_MOCK_PREFIX})|(#{VENDORS_FILES.map{|source| '\b' + source + '\b'}.join('|')})/
    @ceedling[:generator].generate_object_file(
      TOOLS_GCOV_COMPILER,
      OPERATION_COMPILE_SYM,
      GCOV_SYM,
      object.source,
      object.name,
      @ceedling[:file_path_utils].form_test_build_list_filepath(object.name)
    )
  else
    @ceedling[GCOV_SYM].generate_coverage_object_file(object.source, object.name)
  end
end

rule(/#{GCOV_BUILD_OUTPUT_PATH}\/#{'.+\\' + EXTENSION_EXECUTABLE}$/) do |bin_file|
  lib_args = @ceedling[:test_invoker].convert_libraries_to_arguments()

  @ceedling[:generator].generate_executable_file(
    TOOLS_GCOV_LINKER,
    GCOV_SYM,
    bin_file.prerequisites,
    bin_file.name,
    lib_args,
    @ceedling[:file_path_utils].form_test_build_map_filepath(bin_file.name)
  )
end

rule(/#{GCOV_RESULTS_PATH}\/#{'.+\\' + EXTENSION_TESTPASS}$/ => [
       proc do |task_name|
         @ceedling[:file_path_utils].form_test_executable_filepath(task_name)
       end
     ]) do |test_result|
  @ceedling[:generator].generate_test_results(TOOLS_GCOV_FIXTURE, GCOV_SYM, test_result.source, test_result.name)
end

rule(/#{GCOV_DEPENDENCIES_PATH}\/#{'.+\\' + EXTENSION_DEPENDENCIES}$/ => [
       proc do |task_name|
         @ceedling[:file_finder].find_compilation_input_file(task_name)
       end
     ]) do |dep|
  @ceedling[:generator].generate_dependencies_file(
    TOOLS_TEST_DEPENDENCIES_GENERATOR,
    GCOV_SYM,
    dep.source,
    File.join(GCOV_BUILD_OUTPUT_PATH, File.basename(dep.source).ext(EXTENSION_OBJECT)),
    dep.name
  )
end

task directories: [GCOV_BUILD_OUTPUT_PATH, GCOV_RESULTS_PATH, GCOV_DEPENDENCIES_PATH, GCOV_ARTIFACTS_PATH]

namespace GCOV_SYM do
  task source_coverage: COLLECTION_ALL_SOURCE.pathmap("#{GCOV_BUILD_OUTPUT_PATH}/%n#{@ceedling[:configurator].extension_object}")

  desc 'Run code coverage for all tests'
  task all: [:directories] do
    @ceedling[:configurator].replace_flattened_config(@ceedling[GCOV_SYM].config)
    @ceedling[:test_invoker].setup_and_invoke(COLLECTION_ALL_TESTS, GCOV_SYM)
    @ceedling[:configurator].restore_config
  end

  desc 'Run single test w/ coverage ([*] real test or source file name, no path).'
  task :* do
    message = "\nOops! '#{GCOV_ROOT_NAME}:*' isn't a real task. " \
              "Use a real test or source file name (no path) in place of the wildcard.\n" \
              "Example: rake #{GCOV_ROOT_NAME}:foo.c\n\n"

    @ceedling[:streaminator].stdout_puts(message)
  end

  desc 'Run tests by matching regular expression pattern.'
  task :pattern, [:regex] => [:directories] do |_t, args|
    matches = []

    COLLECTION_ALL_TESTS.each do |test|
      matches << test if test =~ /#{args.regex}/
    end

    if !matches.empty?
      @ceedling[:configurator].replace_flattened_config(@ceedling[GCOV_SYM].config)
      @ceedling[:test_invoker].setup_and_invoke(matches, GCOV_SYM, force_run: false)
      @ceedling[:configurator].restore_config
    else
      @ceedling[:streaminator].stdout_puts("\nFound no tests matching pattern /#{args.regex}/.")
    end
  end

  desc 'Run tests whose test path contains [dir] or [dir] substring.'
  task :path, [:dir] => [:directories] do |_t, args|
    matches = []

    COLLECTION_ALL_TESTS.each do |test|
      matches << test if File.dirname(test).include?(args.dir.tr('\\', '/'))
    end

    if !matches.empty?
      @ceedling[:configurator].replace_flattened_config(@ceedling[GCOV_SYM].config)
      @ceedling[:test_invoker].setup_and_invoke(matches, GCOV_SYM, force_run: false)
      @ceedling[:configurator].restore_config
    else
      @ceedling[:streaminator].stdout_puts("\nFound no tests including the given path or path component.")
    end
  end

  desc 'Run code coverage for changed files'
  task delta: [:directories] do
    @ceedling[:configurator].replace_flattened_config(@ceedling[GCOV_SYM].config)
    @ceedling[:test_invoker].setup_and_invoke(COLLECTION_ALL_TESTS, GCOV_SYM, force_run: false)
    @ceedling[:configurator].restore_config
  end

  # use a rule to increase efficiency for large projects
  # gcov test tasks by regex
  rule(/^#{GCOV_TASK_ROOT}\S+$/ => [
         proc do |task_name|
           test = task_name.sub(/#{GCOV_TASK_ROOT}/, '')
           test = "#{PROJECT_TEST_FILE_PREFIX}#{test}" unless test.start_with?(PROJECT_TEST_FILE_PREFIX)
           @ceedling[:file_finder].find_test_from_file_path(test)
         end
       ]) do |test|
    @ceedling[:rake_wrapper][:directories].invoke
    @ceedling[:configurator].replace_flattened_config(@ceedling[GCOV_SYM].config)
    @ceedling[:test_invoker].setup_and_invoke([test.source], GCOV_SYM)
    @ceedling[:configurator].restore_config
  end
end

if PROJECT_USE_DEEP_DEPENDENCIES
  namespace REFRESH_SYM do
    task GCOV_SYM do
      @ceedling[:configurator].replace_flattened_config(@ceedling[GCOV_SYM].config)
      @ceedling[:test_invoker].refresh_deep_dependencies
      @ceedling[:configurator].restore_config
    end
  end
end

namespace UTILS_SYM do
  # Report Creation Utilities
  UTILITY_NAME_GCOVR = "gcovr"
  UTILITY_NAME_REPORT_GENERATOR = "ReportGenerator"
  UTILITY_NAMES = [UTILITY_NAME_GCOVR, UTILITY_NAME_REPORT_GENERATOR]

  # Returns true is the given utility is enabled, otherwise returns false.
  def is_utility_enabled(opts, utility_name)
    return !(opts.nil?) && !(opts[:gcov_utilities].nil?) && (opts[:gcov_utilities].map(&:upcase).include? utility_name.upcase)
  end


  # Output the shell result to the console.
  def print_shell_result(shell_result)
    if !(shell_result.nil?)
      puts "Done in %.3f seconds." % shell_result[:time]

      if !(shell_result[:output].nil?) && (shell_result[:output].length > 0)
        puts shell_result[:output]
      end
    end
  end


  desc "Create gcov code coverage html/xml/json/text report(s). (Note: Must run 'ceedling gcov' first)."
  task GCOV_SYM do
    # Get the gcov options from project.yml.
    opts = @ceedling[:configurator].project_config_hash

    # Create the artifacts output directory.
    if !File.directory? GCOV_ARTIFACTS_PATH
      FileUtils.mkdir_p GCOV_ARTIFACTS_PATH
    end

    # Remove unsupported reporting utilities.
    if !(opts[:gcov_utilities].nil?)
      opts[:gcov_utilities].reject! { |item| !(UTILITY_NAMES.map(&:upcase).include? item.upcase) }
    end

    # Default to gcovr when no reporting utilities are specified.
    if opts[:gcov_utilities].nil? || opts[:gcov_utilities].empty?
      opts[:gcov_utilities] = [UTILITY_NAME_GCOVR]
    end

    if opts[:gcov_reports].nil?
      opts[:gcov_reports] = []
    end

    gcovr_reportinator = GcovrReportinator.new(@ceedling)
    gcovr_reportinator.support_deprecated_options(opts)

    if is_utility_enabled(opts, UTILITY_NAME_GCOVR)
      shell_result = nil
      total_time = Benchmark.realtime do
        shell_result = gcovr_reportinator.make_reports(opts)
      end
      if shell_result
        shell_result[:time] = total_time
        print_shell_result(shell_result)
      end
    end

    if is_utility_enabled(opts, UTILITY_NAME_REPORT_GENERATOR)
      shell_result = nil
      total_time = Benchmark.realtime do
        reportgenerator_reportinator = ReportGeneratorReportinator.new(@ceedling)
        shell_result = reportgenerator_reportinator.make_reports(opts)
      end
      if shell_result
        shell_result[:time] = total_time
        print_shell_result(shell_result)
      end
    end

  end
end
